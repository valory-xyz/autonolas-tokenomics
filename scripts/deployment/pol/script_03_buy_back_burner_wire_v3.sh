#!/bin/bash

# Post-deploy V3 wiring for BuyBackBurner proxies. Configures V3 pools per second token and
# sets per-token slippage caps for the V3 buyBack path. Run AFTER both:
#   - the BuyBackBurner proxy is deployed (utils/deploy_03_*.sh or utils/deploy_04_*.sh)
#   - the LiquidityManager is deployed (pol/deploy_02_liquidity_manager_*.sh)
#
# Without this wiring, V3 buyBack reverts:
#   - UnauthorizedToken(secondToken) inside _buyOLASV3 if mapV3Pools[secondToken] is unset
#   - DEX-side amountOutMinimum revert if mapTokenMaxSlippages is unset (amountOutMin == TWAP
#     quote is not realistically reachable)
#
# Globals fields consumed:
#   buyBackBurnerProxyAddress  : already populated by utils/deploy_03/04 step
#   v3SecondTokens             : array of token addresses for V3 buyBack (the non-OLAS side)
#   v3Pools                    : array of canonical V3 pool addresses matching v3SecondTokens
#                                (factory ancestry is enforced on-chain by setV3Pools)
#   v3MaxSlippages             : array of bps (uint256) matching v3SecondTokens

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 eth_mainnet"
  exit 1
fi

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

buyBackBurnerProxyAddress=$(jq -r '.buyBackBurnerProxyAddress' $globals)
v3SecondTokens=$(jq -rc '.v3SecondTokens' $globals)
v3Pools=$(jq -rc '.v3Pools' $globals)
v3MaxSlippages=$(jq -rc '.v3MaxSlippages' $globals)

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

if [ "$buyBackBurnerProxyAddress" == "null" ] || [ -z "$buyBackBurnerProxyAddress" ]; then
  echo "${red}!!! buyBackBurnerProxyAddress is not set in $globals${reset}"
  exit 1
fi

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Configure V3 pools per secondToken on BuyBackBurner proxy${reset}"
castArgs="$buyBackBurnerProxyAddress setV3Pools(address[],address[]) $v3SecondTokens $v3Pools"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

echo "${green}Set per-token max slippage on BuyBackBurner proxy${reset}"
castArgs="$buyBackBurnerProxyAddress setMaxSlippages(address[],uint256[]) $v3SecondTokens $v3MaxSlippages"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

echo "${green}Done.${reset}"
