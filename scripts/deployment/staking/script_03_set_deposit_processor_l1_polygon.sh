#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get network name from network_mainnet or network_sepolia or another testnet
network=${1%_*}

# Get globals file
globals="$(dirname "$0")/globals_${1#*_}.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Get globals file for L2
globalsL2="$(dirname "$0")/${network}/globals_$1.json"
if [ ! -f $globalsL2 ]; then
  echo "${red}!!! $globalsL2 is not found${reset}"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globalsL2)
networkURL=$(jq -r '.networkURL' $globalsL2)


depositProcessorL1Address=$(jq -r ".${network}DepositProcessorL1Address" $globals)
targetDispenserL2Address=$(jq -r ".${network}TargetDispenserL2Address" $globalsL2)

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
echo "${green}Casting from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}EOA to set fxRootTunnel as DepositProcessorL1 in TargetDispenserL2${reset}"

castCallHeader="cast call --rpc-url $networkURL$API_KEY"
castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
addressZero=$(cast address-zero)

# Check for assigned l2TargetDispenser value
echo "Network: ${network}"
if [ "$targetDispenserL2Address" == "null" ]; then
  echo "${red}!!!${network}TargetDispenserL2Address is not set${reset}"
  echo ""
else
  echo "${green}Checking fxRootTunnel address in ${network}TargetDispenserL2Address${reset}"
  castArgs="$targetDispenserL2Address fxRootTunnel()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign fxRootTunnel as l1DepositProcessor  value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "${green}Setting fxRootTunnel as ${network}DepositProcessorL1 address${reset}"
    castArgs="$targetDispenserL2Address setFxRootTunnel(address) $depositProcessorL1Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "${green}l2TargetDispenser is already set to address $resultAddress${reset}"
    echo ""
  fi
fi
