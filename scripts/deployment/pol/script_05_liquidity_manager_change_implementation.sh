#!/bin/bash

# Upgrades the LiquidityManagerProxy to a freshly-deployed LiquidityManager* implementation by calling
# changeImplementation(address) on the proxy. The proxy owner is the Autonolas deployer EOA (ownership was
# deliberately left with the deployer while POL is not operational), so this is a plain single-signer
# cast send — NOT a Timelock/DAO proposal.
#
# Prerequisite: deploy the new implementation first (deploy_02_liquidity_manager_eth.sh /
# deploy_02_liquidity_manager_optimism.sh) and write its address into `liquidityManagerAddress` in the
# globals file. The proxy address is read from `liquidityManagerProxyAddress`.
#
# IMPORTANT ordering: the fail-closed price guard means the first convertToV3 reverts on a brand-new /
# quiet pool. Perform this upgrade BEFORE seeding any POL, then follow docs/liquidity_migration_runbook.md
# (pre-warm the pool) before the first seed.

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 eth_mainnet"
  exit 1
fi

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
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

liquidityManagerAddress=$(jq -r '.liquidityManagerAddress' $globals)
liquidityManagerProxyAddress=$(jq -r '.liquidityManagerProxyAddress' $globals)

# Guard against a misconfigured globals file — changeImplementation(0x0/null) would brick the proxy
if [ -z "$liquidityManagerAddress" ] || [ "$liquidityManagerAddress" == "null" ]; then
  echo "${red}!!! liquidityManagerAddress is empty in $globals — deploy the new implementation first${reset}"
  exit 0
fi
if [ -z "$liquidityManagerProxyAddress" ] || [ "$liquidityManagerProxyAddress" == "null" ]; then
  echo "${red}!!! liquidityManagerProxyAddress is empty in $globals${reset}"
  exit 0
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

echo "${green}Change LiquidityManager implementation in its proxy${reset}"
castArgs="$liquidityManagerProxyAddress changeImplementation(address) $liquidityManagerAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
