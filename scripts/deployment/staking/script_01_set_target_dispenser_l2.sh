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
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)


depositProcessorL1Address=$(jq -r ".${network}DepositProcessorL1Address" $globals)
targetDispenserL2Address=$(jq -r ".${network}TargetDispenserL2Address" $globalsL2)

# Getting L1 Alchemy API key
if [ $chainId == 1 ]; then
  API_KEY=$ALCHEMY_API_KEY_MAINNET
  if [ "$API_KEY" == "" ]; then
      echo "set ALCHEMY_API_KEY_MAINNET env variable"
      exit 0
  fi
elif [ $chainId == 11155111 ]; then
    API_KEY=$ALCHEMY_API_KEY_SEPOLIA
    if [ "$API_KEY" == "" ]; then
        echo "set ALCHEMY_API_KEY_SEPOLIA env variable"
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
echo "${green}EOA to set TargetDispenserL2 in DepositProcessorL1 and zero the owner${reset}"

castCallHeader="cast call --rpc-url $networkURL$API_KEY"
castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
addressZero=$(cast address-zero)

# Check for assigned l2TargetDispenser value
echo "Network: ${network}"
if [ "$depositProcessorL1Address" == "null" ]; then
  echo "${red}!!!${network}DepositProcessorL1Address is not set${reset}"
  echo ""
else
  echo "${green}Checking ${network}TargetDispenserL2Address address in $depositProcessorL1Address${reset}"
  castArgs="$depositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "${green}Setting ${network}TargetDispenserL2 address${reset}"
    castArgs="$depositProcessorL1Address setL2TargetDispenser(address) $targetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "${green}l2TargetDispenser is already set to address $resultAddress${reset}"
    echo ""
  fi
fi
