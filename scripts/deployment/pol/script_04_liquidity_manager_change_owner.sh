#!/bin/bash

# Transfers LiquidityManager proxy ownership from the deployer to the chain's DAO executor.
# Target owner = bridgeMediatorAddress (L2) || timelockAddress (L1 mainnet), mirroring the
# convention used elsewhere in deploy scripts. Only chains with a deployed LM proxy are valid
# targets: eth_mainnet, base_mainnet, optimism_mainnet (per pol/globals_*.json availability).
#
# Pre-flight: confirm the current proxy owner equals the signer derived from $derivationPath
# and bail out early — LiquidityManagerCore.changeOwner reverts with OwnerOnly otherwise.

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

liquidityManagerProxyAddress=$(jq -r '.liquidityManagerProxyAddress' $globals)
bridgeMediatorAddress=$(jq -r '.bridgeMediatorAddress' $globals)
timelockAddress=$(jq -r '.timelockAddress' $globals)

if [ "$bridgeMediatorAddress" != "null" ] && [ -n "$bridgeMediatorAddress" ]; then
  newOwnerAddress="$bridgeMediatorAddress"
elif [ "$timelockAddress" != "null" ] && [ -n "$timelockAddress" ]; then
  newOwnerAddress="$timelockAddress"
else
  echo "${red}!!! Neither bridgeMediatorAddress nor timelockAddress is set in $globals${reset}"
  exit 1
fi

if [ "$liquidityManagerProxyAddress" == "null" ] || [ -z "$liquidityManagerProxyAddress" ]; then
  echo "${red}!!! liquidityManagerProxyAddress is not set in $globals${reset}"
  exit 1
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

# Pre-flight: current owner must equal the signer; otherwise changeOwner reverts.
currentOwner=$(cast call --rpc-url $networkURL$API_KEY $liquidityManagerProxyAddress "owner()(address)")
if [ "${currentOwner,,}" != "${deployer,,}" ]; then
  echo "${red}!!! Signer $deployer is not the current LM proxy owner ($currentOwner).${reset}"
  echo "${red}    Set derivationPath in $globals to the path that controls $currentOwner, then re-run.${reset}"
  exit 1
fi

if [ "${currentOwner,,}" == "${newOwnerAddress,,}" ]; then
  echo "${green}LiquidityManager proxy $liquidityManagerProxyAddress is already owned by $newOwnerAddress. Nothing to do.${reset}"
  exit 0
fi

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Change LiquidityManager proxy owner: $currentOwner -> $newOwnerAddress${reset}"
castArgs="$liquidityManagerProxyAddress changeOwner(address) $newOwnerAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
