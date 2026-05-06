#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

# Check for Alchemy keys
if [[ "$networkURL" == *"alchemy.com"* ]]; then
  case $chainId in
    1)        API_KEY=$ALCHEMY_API_KEY_MAINNET; keyName="ALCHEMY_API_KEY_MAINNET" ;;
    11155111) API_KEY=$ALCHEMY_API_KEY_SEPOLIA; keyName="ALCHEMY_API_KEY_SEPOLIA" ;;
    137)      API_KEY=$ALCHEMY_API_KEY_MATIC;   keyName="ALCHEMY_API_KEY_MATIC" ;;
    80002)    API_KEY=$ALCHEMY_API_KEY_AMOY;    keyName="ALCHEMY_API_KEY_AMOY" ;;
  esac
  if [ -n "$keyName" ] && [ "$API_KEY" == "" ]; then
    echo "set $keyName env variable"
    exit 0
  fi
fi

# For ETH mainnet: just burner and timelock, for others: bridge2Burner and bridgeMediator
if [ $chainId == 1 ] || [ $chainId == 11155111 ]; then
  bridge2BurnerAddress=$(jq -r '.burnerAddress' $globals)
  bridgeMediatorAddress=$(jq -r ".timelockAddress" $globals)
else
  bridge2BurnerAddress=$(jq -r '.bridge2BurnerAddress' $globals)
  bridgeMediatorAddress=$(jq -r ".bridgeMediatorAddress" $globals)
fi

liquidityManagerAddress=$(jq -r '.liquidityManagerProxyAddress' $globals)
swapRouterV3Address=$(jq -r '.swapRouterV3Address' $globals)

# Both fields must be set explicitly in globals — real addresses for V3-enabled,
# `0x0000000000000000000000000000000000000000` for V3-disabled. Empty/null means
# "operator hasn't decided yet" and we refuse to deploy.
# NOTE: for V3-enabled, wire the LiquidityManager *proxy*, not the impl — the BBB
# calls factoryV3() through it and the proxy delegatecall-reads the impl's immutables.
if [ -z "$liquidityManagerAddress" ] || [ "$liquidityManagerAddress" == "null" ]; then
  echo "${red}!!! liquidityManagerProxyAddress is not set in $globals."
  echo "    Populate with the LM proxy address (V3 enabled) or 0x0000000000000000000000000000000000000000 (V3 disabled).${reset}"
  exit 1
fi
if [ -z "$swapRouterV3Address" ] || [ "$swapRouterV3Address" == "null" ]; then
  echo "${red}!!! swapRouterV3Address is not set in $globals."
  echo "    Populate with the concentrated-liquidity router address (V3 enabled) or 0x0000000000000000000000000000000000000000 (V3 disabled).${reset}"
  exit 1
fi

contractName="BuyBackBurnerUniswap"
contractPath="contracts/utils/$contractName.sol:$contractName"
constructorArgs="$liquidityManagerAddress $bridge2BurnerAddress $bridgeMediatorAddress $swapRouterV3Address"
contractArgs="$contractPath --constructor-args $constructorArgs"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Deployment message
echo "${green}Deploying from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Deployment of: $contractArgs${reset}"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
buyBackBurnerAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#buyBackBurnerAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"buyBackBurnerAddress":"'$buyBackBurnerAddress'"}' $globals)" > $globals

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$buyBackBurnerAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}$contractName deployed at: $buyBackBurnerAddress${reset}"