#!/bin/bash

# ============================================================================
# DANGER: in-place implementation upgrade via `changeImplementation`.
#
# The PR #272 `BuyBackBurner` storage layout inserts `mapV3Pools` into the
# base class, shifting derived-class slots (`router` on Uniswap; `balancerVault`
# / `balancerPoolId` on Balancer). Pointing an existing pre-V3 BBB proxy at
# the new implementation will silently corrupt those slots and dead-end the
# V2 `buyBack` path. See `audits/internal15/README.md` H-01 for the full
# layout analysis and `audits/internal15/FINAL_REVIEW.md` S-1 for the
# remediation rationale.
#
# Preferred path: fresh re-deploy via the proxy scripts (creates new BBB
# proxies; pre-existing proxies stay on their original impl):
#   scripts/deployment/utils/deploy_03_buy_back_burner_balancer_proxy.sh
#   scripts/deployment/utils/deploy_04_buy_back_burner_uniswap_proxy.sh
#
# To run anyway (e.g. on a brand-new proxy already initialized with the new
# layout), set the explicit acknowledgement:
#   I_ACKNOWLEDGE_PRE_V3_LAYOUT_RISK=1 ./script_01_buy_back_burner_change_implementation.sh <network>
# ============================================================================

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 eth_mainnet"
  exit 1
fi

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Hard guard: refuse to run without explicit acknowledgement of the storage-layout risk.
if [ "$I_ACKNOWLEDGE_PRE_V3_LAYOUT_RISK" != "1" ]; then
  echo "${red}!!! Refusing to run: in-place \`changeImplementation\` can silently corrupt"
  echo "    derived-class storage on pre-V3 BBB proxies (router / balancerVault /"
  echo "    balancerPoolId end up reading from the wrong slots → V2 \`buyBack\` dies)."
  echo ""
  echo "    Preferred path: fresh re-deploy via deploy_03 / deploy_04 proxy scripts."
  echo ""
  echo "    To override (only safe on a brand-new proxy initialized with the post-#272"
  echo "    layout), set in your environment:"
  echo "        I_ACKNOWLEDGE_PRE_V3_LAYOUT_RISK=1${reset}"
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

buyBackBurnerAddress=$(jq -r '.buyBackBurnerAddress' $globals)
buyBackBurnerProxyAddress=$(jq -r '.buyBackBurnerProxyAddress' $globals)

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

echo "${green}Change BuyBackBurner implementation in its proxy${reset}"
castArgs="$buyBackBurnerProxyAddress changeImplementation(address) $buyBackBurnerAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
