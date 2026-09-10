#!/bin/bash

# Transfers BuyBackBurner proxy ownership from the deployer to the chain's DAO executor.
# Target owner is taken from the same field the deploy script used for `treasury`:
#   newOwner = bridgeMediatorAddress  (on L2 chains)
#           || timelockAddress        (on L1 mainnet)
#
# IMPORTANT — Base BBB proxy:
#   The Base proxy was deployed in the agents.fun era under derivation path m/44'/60'/9'/0/0
#   (owner 0x6F7a4938AB3bbF69480E7C109Af778ee78099Be7). All other chains use the Autonolas
#   deployer at m/44'/60'/2'/0/0. To run this script on base_mainnet, temporarily set
#   `derivationPath` in scripts/deployment/utils/globals_base_mainnet.json to
#   "m/44'/60'/9'/0/0" so the ledger signs from the legacy owner, then revert.
#
# Pre-flight: confirm the current proxy owner matches the signer derived from $derivationPath,
# and bail out early if not — `changeOwner` reverts with OwnerOnly otherwise.

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

buyBackBurnerProxyAddress=$(jq -r '.buyBackBurnerProxyAddress' $globals)
bridgeMediatorAddress=$(jq -r '.bridgeMediatorAddress' $globals)
timelockAddress=$(jq -r '.timelockAddress' $globals)

# Mirror the deploy scripts: treasury / new-owner = bridgeMediator on L2, timelock on L1.
if [ "$bridgeMediatorAddress" != "null" ] && [ -n "$bridgeMediatorAddress" ]; then
  newOwnerAddress="$bridgeMediatorAddress"
elif [ "$timelockAddress" != "null" ] && [ -n "$timelockAddress" ]; then
  newOwnerAddress="$timelockAddress"
else
  echo "${red}!!! Neither bridgeMediatorAddress nor timelockAddress is set in $globals${reset}"
  exit 1
fi

if [ "$buyBackBurnerProxyAddress" == "null" ] || [ -z "$buyBackBurnerProxyAddress" ]; then
  echo "${red}!!! buyBackBurnerProxyAddress is not set in $globals${reset}"
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
currentOwner=$(cast call --rpc-url $networkURL$API_KEY $buyBackBurnerProxyAddress "owner()(address)")
# A failed call returns an empty string, which would otherwise compare unequal to the signer and
# report a missing derivation path for an owner that was never read.
if ! [[ "$currentOwner" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "${red}!!! Failed to read BuyBackBurner proxy owner() (got: $currentOwner)${reset}"
  exit 1
fi

# Addresses are lowercased with tr rather than the ${var,,} expansion, which is bash 4 only: macOS
# still ships bash 3.2, where it aborts the script with "bad substitution". That failed safe here,
# before the cast send below, but it meant this handover could not be completed from a Mac at all.
currentOwnerLc=$(echo "$currentOwner" | tr '[:upper:]' '[:lower:]')
deployerLc=$(echo "$deployer" | tr '[:upper:]' '[:lower:]')
newOwnerLc=$(echo "$newOwnerAddress" | tr '[:upper:]' '[:lower:]')

# The already-done case is tested before the signer check, not after it. Once the handover has
# succeeded the signer is by definition no longer the owner, so the original order reported a
# completed transfer as a hard failure telling the operator to find a derivation path for the
# bridge mediator - an address nobody holds a key for.
if [ "$currentOwnerLc" == "$newOwnerLc" ]; then
  echo "${green}BuyBackBurner proxy $buyBackBurnerProxyAddress is already owned by $newOwnerAddress. Nothing to do.${reset}"
  exit 0
fi

if [ "$currentOwnerLc" != "$deployerLc" ]; then
  echo "${red}!!! Signer $deployer is not the current BBB proxy owner ($currentOwner).${reset}"
  echo "${red}    Set derivationPath in $globals to the path that controls $currentOwner, then re-run.${reset}"
  exit 1
fi

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Change BuyBackBurner proxy owner: $currentOwner -> $newOwnerAddress${reset}"
castArgs="$buyBackBurnerProxyAddress changeOwner(address) $newOwnerAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
