#!/bin/bash

# Sets LiquidityManagerCore.maxSlippage on the proxy to `liquidityManagerMaxSlippage` from globals, by calling
# changeMaxSlippage(uint16) on the proxy. The proxy owner is the Autonolas deployer EOA (ownership deliberately
# left with the deployer while POL is not operational), so this is a plain single-signer cast send.
#
# When it is needed: a freshly-deployed proxy (deploy_03) already `initialize`s maxSlippage from globals, so it
# does NOT need this. This script is for proxies UPGRADED in place via script_05 (changeImplementation) — that
# path swaps the implementation but does not re-run `initialize` (it reverts AlreadyInitialized), so the proxy
# keeps whatever maxSlippage it was first initialized with. Run this after script_05 to move an existing proxy
# to the current `liquidityManagerMaxSlippage` value (e.g. the 10% -> 5% re-tasking for the V2<->V3 ratio gate).

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
liquidityManagerMaxSlippage=$(jq -r '.liquidityManagerMaxSlippage' $globals)

# Guard against a misconfigured globals file
if [ -z "$liquidityManagerProxyAddress" ] || [ "$liquidityManagerProxyAddress" == "null" ] \
   || [ "$liquidityManagerProxyAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! liquidityManagerProxyAddress is empty/zero in $globals${reset}"
  exit 1
fi
# changeMaxSlippage reverts on 0 and on > MAX_BPS (10_000); refuse those here rather than send a failing tx
if [ -z "$liquidityManagerMaxSlippage" ] || [ "$liquidityManagerMaxSlippage" == "null" ] \
   || [ "$liquidityManagerMaxSlippage" -eq 0 ] || [ "$liquidityManagerMaxSlippage" -gt 10000 ]; then
  echo "${red}!!! liquidityManagerMaxSlippage must be in 1..10000 (got '$liquidityManagerMaxSlippage') in $globals${reset}"
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

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Set LiquidityManager maxSlippage to $liquidityManagerMaxSlippage BPS on its proxy${reset}"
castArgs="$liquidityManagerProxyAddress changeMaxSlippage(uint16) $liquidityManagerMaxSlippage"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

# Assert the tx succeeded — a reverted changeMaxSlippage would otherwise print a status line and look done
txStatus=$(echo "$result" | grep -iE '^status' | grep -oiE '1 \(success\)|0 \(failed\)')
if [ -z "$txStatus" ] || [[ "$txStatus" == 0* ]]; then
  echo "${red}!!! changeMaxSlippage transaction did not succeed${reset}"
  exit 1
fi

# Post-condition: read back maxSlippage() and confirm it landed
storedSlippage=$(cast call $liquidityManagerProxyAddress "maxSlippage()(uint16)" --rpc-url $networkURL$API_KEY)
echo "  maxSlippage -> $storedSlippage (must be $liquidityManagerMaxSlippage)"
if [ "$storedSlippage" != "$liquidityManagerMaxSlippage" ]; then
  echo "${red}!!! On-chain maxSlippage does not match liquidityManagerMaxSlippage — the change did not land${reset}"
  exit 1
fi

echo "${green}LiquidityManager maxSlippage updated and verified${reset}"
