#!/bin/bash

# Whitelists every L1 deposit processor on the live Dispenser via
# setDepositProcessorChainIds(address[],uint256[]), mapping each L2 target chain Id to its L1 processor
# (and the mainnet chain Id to the L1-only EthereumDepositProcessor). This is the forge/cast equivalent of
# the hardhat deploy_10_set_deposit_processors.js, and additionally registers the Mode processor.
#
# Run this after all L1 deposit processors have been deployed (their addresses populated in the staking
# globals). Registering a processor here is what lets the Dispenser
# route staking incentives to each chain. There is no zero-processor guard in the Dispenser: a chain left
# unregistered resolves to a zero processor and reverts the claim (and in the batch path the zero-address
# call reverts the whole batch, taking the other chains' claims down with it) — not a silent skip.
#
# Ownership note: on a FRESH deployment the Dispenser owner is still the deploying EOA, so this runs as a
# direct cast send. That is not the live mainnet situation: Dispenser.owner() is the DAO Timelock today, so
# against the live Dispenser this call reverts OwnerOnly and must go through a governance proposal instead.
# Treat this script as fresh-deployment tooling and as a source of the calldata for that proposal.
#
# Usage: deploy_10_set_deposit_processors.sh <network>
#
# Globals fields consumed:
#   dispenserProxyAddress (root globals ../globals_<network>.json, where it exists) : DispenserProxy address;
#   dispenserAddress (this globals, networks without a root globals)               : Dispenser address
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

zeroAddress="0x0000000000000000000000000000000000000000"

# Dispenser to whitelist on. Where a root deployment globals exists (mainnet), it is the DispenserProxy that
# deploy_07b_dispenser_proxy.sh records there, not this globals' dispenserAddress, which keeps the pre-proxy
# Dispenser. Networks without a root globals (test networks) keep using this globals' dispenserAddress.
globalsRoot="$(dirname "$0")/../globals_$1.json"
if [ -f $globalsRoot ]; then
  dispenserAddress=$(jq -r '.dispenserProxyAddress' $globalsRoot)
  dispenserSource="dispenserProxyAddress in $globalsRoot"
else
  dispenserAddress=$(jq -r '.dispenserAddress' $globals)
  dispenserSource="dispenserAddress in $globals"
fi
if [ -z "$dispenserAddress" ] || [ "$dispenserAddress" == "null" ] \
   || [ "$dispenserAddress" == "$zeroAddress" ]; then
  echo "${red}!!! $dispenserSource is not set (or zero)${reset}"
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
  "Robinhood robinhoodDepositProcessorL1Address robinhoodL2TargetChainId"
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

# Where the address comes from the root globals, it must be the DispenserProxy for the implementation that
# deploy_07a_dispenser.sh recorded there as dispenserAddress: the proxy's PROXY_DISPENSER slot must hold that
# implementation, and the implementation must have code. Checking for the PROXY_DISPENSER() getter is not
# enough, since the implementation exposes the same constant.
if [ -f $globalsRoot ]; then
  dispenserImplementation=$(jq -r '.dispenserAddress' $globalsRoot)
  proxySlot=$(cast storage --rpc-url $networkURL$API_KEY $dispenserAddress \
    0x8bd249c73459f2c50400ebdc57436101fc7d9a76908baf1ba5be362b47b48f83)
  slotImplementation=$(cast parse-bytes32-address $proxySlot 2>/dev/null)
  implementationCode=$(cast code --rpc-url $networkURL$API_KEY $dispenserImplementation 2>/dev/null)
  lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
  if [ "$(lower $slotImplementation)" != "$(lower $dispenserImplementation)" ] \
     || [ "$(lower $dispenserAddress)" == "$(lower $dispenserImplementation)" ] \
     || [ -z "$implementationCode" ] || [ "$implementationCode" == "0x" ]; then
    echo "${red}!!! $dispenserAddress is not a DispenserProxy for the implementation $dispenserImplementation${reset}"
    echo "${red}    (PROXY_DISPENSER slot holds '${slotImplementation:-<unreadable>}'; see $globalsRoot)${reset}"
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

echo "${green}Whitelist L1 deposit processors on the Dispenser${reset}"
echo "  dispenserProxy : $dispenserAddress"
for i in "${!labels[@]}"; do
  echo "  ${labels[$i]} (chainId ${chainIds[$i]}) -> ${addresses[$i]}"
done

castArgs="$dispenserAddress setDepositProcessorChainIds(address[],uint256[]) [$addrList] [$chainList]"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

# Post-call sanity: every chain Id must now resolve to the processor we set
echo "${green}Verifying mapChainIdDepositProcessors${reset}"
mismatch=0
for i in "${!chainIds[@]}"; do
  onchain=$(cast call --rpc-url $networkURL$API_KEY $dispenserAddress "mapChainIdDepositProcessors(uint256)(address)" "${chainIds[$i]}")
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
