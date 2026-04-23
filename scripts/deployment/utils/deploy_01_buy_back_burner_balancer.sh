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

# V3 path is optional. Policy (fail-closed by default — see PR #278 review):
#   - Both fields populated (non-zero): V3 enabled.
#   - Both fields empty / null / zero: V3 disabled — REQUIRES explicit V3_DISABLED=true opt-in.
#     Without the opt-in we refuse to deploy, so a misconfigured V3-intended chain
#     cannot silently land in V3-disabled mode and only surface at runtime via
#     V3PathDisabled.
#   - Mixed (one zero, one non-zero): rejected unconditionally — likely a globals
#     misconfiguration (e.g. swap router populated but LM proxy not yet deployed).
#
# NOTE: when V3 is enabled, we wire the LiquidityManager *proxy* here, not the impl —
# the BBB calls factoryV3() through it and the proxy delegatecall-reads the impl's
# immutables, preserving a future changeImplementation() upgrade path.
ZERO_ADDR="0x0000000000000000000000000000000000000000"
lmEmpty=0; rtEmpty=0
[ -z "$liquidityManagerAddress" ] || [ "$liquidityManagerAddress" == "null" ] || [ "$liquidityManagerAddress" == "$ZERO_ADDR" ] && lmEmpty=1
[ -z "$swapRouterV3Address" ]     || [ "$swapRouterV3Address" == "null" ]     || [ "$swapRouterV3Address" == "$ZERO_ADDR" ]     && rtEmpty=1

if [ $lmEmpty -ne $rtEmpty ]; then
  echo "${red}!!! Partial V3 config in $globals — refusing to deploy."
  echo "    liquidityManagerProxyAddress and swapRouterV3Address must BOTH be populated"
  echo "    (V3 enabled) or BOTH be empty/zero (V3 disabled)."
  echo "    Got:"
  echo "      liquidityManagerProxyAddress = '$liquidityManagerAddress'"
  echo "      swapRouterV3Address          = '$swapRouterV3Address'${reset}"
  exit 1
fi

if [ $lmEmpty -eq 1 ]; then
  if [ "$V3_DISABLED" != "true" ]; then
    echo "${red}!!! liquidityManagerProxyAddress and swapRouterV3Address are both empty/zero in $globals."
    echo ""
    echo "    To deploy a V3-disabled (V2-only) BBB, opt in explicitly:"
    echo "        V3_DISABLED=true ./scripts/deployment/utils/deploy_01_buy_back_burner_balancer.sh $1"
    echo ""
    echo "    Otherwise populate BOTH fields in $globals before re-running."
    echo "    (LiquidityManager proxy: deploy via scripts/deployment/pol/deploy_03_liquidity_manager_proxy.sh,"
    echo "     then copy the resulting liquidityManagerProxyAddress here.)${reset}"
    exit 1
  fi
  liquidityManagerAddress="$ZERO_ADDR"
  swapRouterV3Address="$ZERO_ADDR"
  echo "${green}V3_DISABLED=true acknowledged — deploying V2-only BBB (LM/swapRouter set to address(0)).${reset}"
fi

contractName="BuyBackBurnerBalancer"
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