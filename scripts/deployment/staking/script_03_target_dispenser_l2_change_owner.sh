#!/bin/bash

# Get globals file
globals="$(dirname "$0")/${1%_*}/globals_$1.json"
if [ ! -f $globals ]; then
  echo "!!! $globals is not found"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

optimismTargetDispenserL2Address=$(jq -r '.optimismTargetDispenserL2Address' $globals)
bridgeMediatorAddress=$(jq -r '.bridgeMediatorAddress' $globals)

# Check for Polygon keys only since on other networks those are not needed
if [ $chainId == 137 ]; then
  API_KEY=$ALCHEMY_API_KEY_MATIC
  if [ "$API_KEY" == "" ]; then
      echo "set ALCHEMY_API_KEY_MATIC env variable"
      exit 0
  fi
elif [ $chainId == 80002 ]; then
    API_KEY=$ALCHEMY_API_KEY_AMOY
    if [ "$API_KEY" == "" ]; then
        echo "set ALCHEMY_API_KEY_AMOY env variable"
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

# Cast command
echo "Casting from: $deployer"
echo "RPC: $networkURL"
echo "EOA to change owner in TargetDispenserL2"

castHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

castArgs="$optimismTargetDispenserL2Address changeOwner(address) $bridgeMediatorAddress"
echo $castArgs
castCmd="$castHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"
