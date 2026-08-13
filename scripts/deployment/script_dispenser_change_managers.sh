#!/bin/bash

# Wires the Vote Weighting contract into the live DispenserProxy via changeManagers(address,address).
#
# Why this is a separate step: on a fresh deploy the DispenserProxy is initialized with a zero Vote
# Weighting (the Vote Weighting contract is deployed AFTER the proxy, against the proxy's own address as
# an immutable). The proxy therefore ships paused; this script sets the real Vote Weighting once it exists.
# Treasury is passed as the zero address here (it is already set at initialize(), and a zero argument is a
# no-op in changeManagers) — only Vote Weighting is wired.
#
# Ownership note: immediately after deploy the DispenserProxy owner is the deploying EOA, so this runs as a
# direct cast send. Once ownership is transferred to the DAO Timelock this same call becomes a governance
# proposal instead — do not run this script directly against a DAO-owned proxy.
#
# The setter requires staking incentives to be paused (StakingIncentivesPaused / AllPaused); a fresh proxy
# is StakingIncentivesPaused by construction, so no extra pause step is needed before this call.
#
# Usage: script_dispenser_change_managers.sh <network>
#
# Globals fields consumed:
#   dispenserProxyAddress : live DispenserProxy address
#   voteWeightingAddress  : Vote Weighting address to wire in

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 mainnet"
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

dispenserProxyAddress=$(jq -r '.dispenserProxyAddress' $globals)
voteWeightingAddress=$(jq -r '.voteWeightingAddress' $globals)

# Hard-fail on a missing/zero Vote Weighting — wiring the proxy to the zero address is a silent brick
if [ -z "$voteWeightingAddress" ] || [ "$voteWeightingAddress" == "null" ] \
   || [ "$voteWeightingAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! voteWeightingAddress is not set (or zero) in $globals${reset}"
  exit 1
fi

if [ -z "$dispenserProxyAddress" ] || [ "$dispenserProxyAddress" == "null" ] \
   || [ "$dispenserProxyAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! dispenserProxyAddress is not set (or zero) in $globals${reset}"
  exit 1
fi

# Check for Alchemy keys
if [[ "$networkURL" == *"alchemy.com"* ]]; then
  case $chainId in
    1)        API_KEY=$ALCHEMY_API_KEY_MAINNET; keyName="ALCHEMY_API_KEY_MAINNET" ;;
    11155111) API_KEY=$ALCHEMY_API_KEY_SEPOLIA; keyName="ALCHEMY_API_KEY_SEPOLIA" ;;
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

zeroAddress="0x0000000000000000000000000000000000000000"

echo "${green}Wire Vote Weighting into the DispenserProxy${reset}"
echo "  dispenserProxy : $dispenserProxyAddress"
echo "  voteWeighting  : $voteWeightingAddress"
castArgs="$dispenserProxyAddress changeManagers(address,address) $zeroAddress $voteWeightingAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

# Post-call sanity: the proxy must now report the wired Vote Weighting
voteWeightingGetter=$(cast call --rpc-url $networkURL$API_KEY $dispenserProxyAddress "voteWeighting()(address)")
echo "  voteWeighting() : $voteWeightingGetter (must be $voteWeightingAddress)"
if [ "$(echo $voteWeightingGetter | tr '[:upper:]' '[:lower:]')" != "$(echo $voteWeightingAddress | tr '[:upper:]' '[:lower:]')" ]; then
  echo "${red}!!! voteWeighting() does not match — wiring did not take effect${reset}"
  exit 1
fi
echo "${green}Vote Weighting wired${reset}"
