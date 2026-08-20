#!/bin/bash

# Whitelists every L1 deposit processor on the live DispenserProxy via
# setDepositProcessorChainIds(address[],uint256[]), mapping each L2 target chain Id to its L1 processor
# (and the mainnet chain Id to the L1-only EthereumDepositProcessor). This is the forge/cast equivalent of
# the hardhat deploy_10_set_deposit_processors.js, and additionally registers the Mode processor.
#
# Run this after all L1 deposit processors have been deployed (their addresses populated in the staking
# globals) and after the DispenserProxy is live. Registering a processor here is what lets the Dispenser
# route staking incentives to each chain. There is no zero-processor guard in the Dispenser: a chain left
# unregistered resolves to a zero processor and reverts the claim (and in the batch path the zero-address
# call reverts the whole batch, taking the other chains' claims down with it) — not a silent skip.
#
# Ownership note: immediately after deploy the DispenserProxy owner is the deploying EOA, so this runs as a
# direct cast send. Once ownership is transferred to the DAO Timelock this same call becomes a governance
# proposal instead — do not run this script directly against a DAO-owned proxy.
#
# Usage: deploy_10_set_deposit_processors.sh <network>
#
# Globals fields consumed:
#   dispenserProxyAddress                 : live DispenserProxy address
#   chainId                               : L1 chain Id (used as the Ethereum/L1-only processor key)
#   {arbitrum,base,celo,gnosis,optimism,polygon,mode}DepositProcessorL1Address, ethereumDepositProcessorAddress
#   {arbitrum,base,celo,gnosis,optimism,polygon,mode}L2TargetChainId

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
  # exit 1 (not the 0 some per-network deploy scripts use): this is a single terminal step, often &&-chained
  # after the per-chain deploys, so a missing globals must fail the chain rather than read as success.
  exit 1
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)
dispenserProxyAddress=$(jq -r '.dispenserProxyAddress' $globals)

zeroAddress="0x0000000000000000000000000000000000000000"

if [ -z "$dispenserProxyAddress" ] || [ "$dispenserProxyAddress" == "null" ] \
   || [ "$dispenserProxyAddress" == "$zeroAddress" ]; then
  echo "${red}!!! dispenserProxyAddress is not set (or zero) in $globals${reset}"
  exit 1
fi

# Processor rows: "Label addressKey chainIdKey". The Ethereum row is L1-only — its key is the L1 chain Id
# itself (__L1__ sentinel), not an L2 target chain Id.
rows=(
  "Arbitrum arbitrumDepositProcessorL1Address arbitrumL2TargetChainId"
  "Base baseDepositProcessorL1Address baseL2TargetChainId"
  "Celo celoDepositProcessorL1Address celoL2TargetChainId"
  "Gnosis gnosisDepositProcessorL1Address gnosisL2TargetChainId"
  "Optimism optimismDepositProcessorL1Address optimismL2TargetChainId"
  "Polygon polygonDepositProcessorL1Address polygonL2TargetChainId"
  "Mode modeDepositProcessorL1Address modeL2TargetChainId"
  "Ethereum ethereumDepositProcessorAddress __L1__"
)

# Build the two aligned arrays, hard-failing on any missing/zero entry — whitelisting a zero processor or a
# zero chain Id would silently disable that chain (and a zero chain Id reverts ZeroValue on-chain anyway).
labels=()
addresses=()
chainIds=()
for row in "${rows[@]}"; do
  read -r label addrKey chainKey <<< "$row"
  addr=$(jq -r ".$addrKey" $globals)
  if [ "$chainKey" == "__L1__" ]; then
    cid=$chainId
  else
    cid=$(jq -r ".$chainKey" $globals)
  fi

  if [ -z "$addr" ] || [ "$addr" == "null" ] || [ "$addr" == "$zeroAddress" ]; then
    echo "${red}!!! $label: $addrKey is not set (or zero) in $globals${reset}"
    exit 1
  fi
  if [ -z "$cid" ] || [ "$cid" == "null" ] || [ "$cid" == "0" ]; then
    echo "${red}!!! $label: chain Id ($chainKey) is not set (or zero) in $globals${reset}"
    exit 1
  fi

  labels+=("$label")
  addresses+=("$addr")
  chainIds+=("$cid")
done

# Join into cast array literals
addrList=$(IFS=,; echo "${addresses[*]}")
chainList=$(IFS=,; echo "${chainIds[*]}")

# Check for Alchemy keys
if [[ "$networkURL" == *"alchemy.com"* ]]; then
  case $chainId in
    1)        API_KEY=$ALCHEMY_API_KEY_MAINNET; keyName="ALCHEMY_API_KEY_MAINNET" ;;
    11155111) API_KEY=$ALCHEMY_API_KEY_SEPOLIA; keyName="ALCHEMY_API_KEY_SEPOLIA" ;;
  esac
  if [ -n "$keyName" ] && [ "$API_KEY" == "" ]; then
    echo "set $keyName env variable"
    exit 1
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

echo "${green}Whitelist L1 deposit processors on the DispenserProxy${reset}"
echo "  dispenserProxy : $dispenserProxyAddress"
for i in "${!labels[@]}"; do
  echo "  ${labels[$i]} (chainId ${chainIds[$i]}) -> ${addresses[$i]}"
done

castArgs="$dispenserProxyAddress setDepositProcessorChainIds(address[],uint256[]) [$addrList] [$chainList]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

# Post-call sanity: every chain Id must now resolve to the processor we set
echo "${green}Verifying mapChainIdDepositProcessors${reset}"
mismatch=0
for i in "${!chainIds[@]}"; do
  onchain=$(cast call --rpc-url $networkURL$API_KEY $dispenserProxyAddress "mapChainIdDepositProcessors(uint256)(address)" "${chainIds[$i]}")
  if [ "$(echo $onchain | tr '[:upper:]' '[:lower:]')" != "$(echo ${addresses[$i]} | tr '[:upper:]' '[:lower:]')" ]; then
    echo "${red}!!! ${labels[$i]} (chainId ${chainIds[$i]}): on-chain $onchain != ${addresses[$i]}${reset}"
    mismatch=1
  fi
done
if [ "$mismatch" != "0" ]; then
  echo "${red}!!! One or more deposit processors did not take effect${reset}"
  exit 1
fi
echo "${green}All deposit processors whitelisted${reset}"
