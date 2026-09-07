#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 1
fi

# Get globals file for L2
globalsL2="$(dirname "$0")/robinhood/globals_robinhood_$1.json"
if [ ! -f $globalsL2 ]; then
  echo "${red}!!! $globalsL2 is not found${reset}"
  exit 1
fi

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

olasAddress=$(jq -r '.olasAddress' $globals)
dispenserProxyAddress=$(jq -r '.dispenserProxyAddress' $globals)
robinhoodL1ERC20GatewayRouterAddress=$(jq -r '.robinhoodL1ERC20GatewayRouterAddress' $globals)
robinhoodInboxAddress=$(jq -r '.robinhoodInboxAddress' $globals)
robinhoodL2TargetChainId=$(jq -r '.robinhoodL2TargetChainId' $globals)
robinhoodL1ERC20GatewayAddress=$(jq -r '.robinhoodL1ERC20GatewayAddress' $globals)
robinhoodOutboxAddress=$(jq -r '.robinhoodOutboxAddress' $globals)
robinhoodBridgeAddress=$(jq -r '.robinhoodBridgeAddress' $globals)

# Preflight on the Dispenser binding. l1Dispenser is `immutable` in DefaultDepositProcessorL1, so a processor
# deployed against the wrong Dispenser cannot be repaired — claims from the live one revert ManagerOnly.
# deploy_07b_dispenser_proxy.sh writes dispenserProxyAddress into scripts/deployment/globals_<network>.json,
# a DIFFERENT file from this one, so a proxy migration silently leaves the value here stale.
zeroAddress="0x0000000000000000000000000000000000000000"
if [ -z "$dispenserProxyAddress" ] || [ "$dispenserProxyAddress" == "null" ] \
   || [ "$dispenserProxyAddress" == "$zeroAddress" ]; then
  echo "${red}!!! dispenserProxyAddress is not set (or zero) in $globals${reset}"
  exit 1
fi
deploymentGlobals="$(dirname "$0")/../globals_${1}.json"
if [ -f "$deploymentGlobals" ]; then
  liveDispenser=$(jq -r '.dispenserProxyAddress // .dispenserAddress // empty' "$deploymentGlobals")
  if [ -n "$liveDispenser" ] \
     && [ "$(echo "$liveDispenser" | tr '[:upper:]' '[:lower:]')" != "$(echo "$dispenserProxyAddress" | tr '[:upper:]' '[:lower:]')" ]; then
    echo "${red}!!! Dispenser binding mismatch — refusing to deploy an immutable binding to a stale address${reset}"
    echo "${red}    $globals            dispenserProxyAddress = $dispenserProxyAddress${reset}"
    echo "${red}    $deploymentGlobals  says the live Dispenser is $liveDispenser${reset}"
    echo "${red}    Reconcile the two before deploying; l1Dispenser cannot be changed afterwards.${reset}"
    exit 1
  fi
fi


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

contractPath="contracts/staking/ArbitrumDepositProcessorL1.sol:ArbitrumDepositProcessorL1"
constructorArgs="$olasAddress $dispenserProxyAddress $robinhoodL1ERC20GatewayRouterAddress $robinhoodInboxAddress $robinhoodL2TargetChainId $robinhoodL1ERC20GatewayAddress $robinhoodOutboxAddress $robinhoodBridgeAddress"
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
robinhoodDepositProcessorL1Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#robinhoodDepositProcessorL1Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 1
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"robinhoodDepositProcessorL1Address":"'$robinhoodDepositProcessorL1Address'"}' $globals)" > $globals
# Also write the address into corresponding L2 JSON
echo "$(jq '. += {"robinhoodDepositProcessorL1Address":"'$robinhoodDepositProcessorL1Address'"}' $globalsL2)" > $globalsL2

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$robinhoodDepositProcessorL1Address $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256,address,address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Contract deployed at: $robinhoodDepositProcessorL1Address${reset}"