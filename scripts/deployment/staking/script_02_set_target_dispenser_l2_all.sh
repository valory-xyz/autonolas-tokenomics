#!/bin/bash

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "!!! $globals is not found"
  exit 0
fi

# Read variables using jq
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

arbitrumDepositProcessorL1Address=$(jq -r '.arbitrumDepositProcessorL1Address' $globals)
arbitrumTargetDispenserL2Address=$(jq -r '.arbitrumTargetDispenserL2Address' $globals)
baseDepositProcessorL1Address=$(jq -r '.baseDepositProcessorL1Address' $globals)
baseTargetDispenserL2Address=$(jq -r '.baseTargetDispenserL2Address' $globals)
celoDepositProcessorL1Address=$(jq -r '.celoDepositProcessorL1Address' $globals)
celoTargetDispenserL2Address=$(jq -r '.celoTargetDispenserL2Address' $globals)
gnosisDepositProcessorL1Address=$(jq -r '.gnosisDepositProcessorL1Address' $globals)
gnosisTargetDispenserL2Address=$(jq -r '.gnosisTargetDispenserL2Address' $globals)
modeDepositProcessorL1Address=$(jq -r '.modeDepositProcessorL1Address' $globals)
modeTargetDispenserL2Address=$(jq -r '.modeTargetDispenserL2Address' $globals)
optimismDepositProcessorL1Address=$(jq -r '.optimismDepositProcessorL1Address' $globals)
optimismTargetDispenserL2Address=$(jq -r '.optimismTargetDispenserL2Address' $globals)
polygonDepositProcessorL1Address=$(jq -r '.polygonDepositProcessorL1Address' $globals)
polygonTargetDispenserL2Address=$(jq -r '.polygonTargetDispenserL2Address' $globals)

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
echo "Casting from: $deployer"
echo "RPC: $networkURL"
echo "EOA to TargetDispenserL2 in DepositProcessorL1 and zero the owner"

castCallHeader="cast call --rpc-url $networkURL$API_KEY"
castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
addressZero=$(cast address-zero)

### Arbitrum
# Check for assigned l2TargetDispenser value
echo "ARBITRUM"
if [ "$arbitrumDepositProcessorL1Address" == "null" ]; then
  echo "!!!arbitrumDepositProcessorL1Address is not set"
  echo ""
else
  echo "Checking arbitrumTargetDispenserL2Address address in $arbitrumDepositProcessorL1Address"
  castArgs="$arbitrumDepositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "Setting arbitrumTargetDispenserL2Address address"
    castArgs="$arbitrumDepositProcessorL1Address setL2TargetDispenser(address) $arbitrumTargetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "l2TargetDispenser is already set to address $resultAddress"
    echo ""
  fi
fi


### Base
# Check for assigned l2TargetDispenser value
echo "BASE"
if [ "$baseDepositProcessorL1Address" == "null" ]; then
  echo "!!!baseDepositProcessorL1Address is not set"
  echo ""
else
  echo "Checking baseTargetDispenserL2Address address in $baseDepositProcessorL1Address"
  castArgs="$baseDepositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "Setting baseTargetDispenserL2Address address"
    castArgs="$baseDepositProcessorL1Address setL2TargetDispenser(address) $baseTargetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "l2TargetDispenser is already set to address $resultAddress"
    echo ""
  fi
fi


### Celo
# Check for assigned l2TargetDispenser value
echo "CELO"
if [ "$celoDepositProcessorL1Address" == "null" ]; then
  echo "!!!celoDepositProcessorL1Address is not set"
  echo ""
else
  echo "Checking celoTargetDispenserL2Address address in $celoDepositProcessorL1Address"
  castArgs="$celoDepositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "Setting celoTargetDispenserL2Address address"
    castArgs="$celoDepositProcessorL1Address setL2TargetDispenser(address) $celoTargetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "l2TargetDispenser is already set to address $resultAddress"
    echo ""
  fi
fi


### Gnosis
# Check for assigned l2TargetDispenser value
echo "GNOSIS"
if [ "$gnosisDepositProcessorL1Address" == "null" ]; then
  echo "!!!gnosisDepositProcessorL1Address is not set"
  echo ""
else
  echo "Checking gnosisTargetDispenserL2Address address in $gnosisDepositProcessorL1Address"
  castArgs="$gnosisDepositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "Setting gnosisTargetDispenserL2Address address"
    castArgs="$gnosisDepositProcessorL1Address setL2TargetDispenser(address) $gnosisTargetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "l2TargetDispenser is already set to address $resultAddress"
    echo ""
  fi
fi


### Mode
# Check for assigned l2TargetDispenser value
echo "MODE"
if [ "$modeDepositProcessorL1Address" == "null" ]; then
  echo "!!!modeDepositProcessorL1Address is not set"
  echo ""
else
  echo "Checking modeTargetDispenserL2Address address in $modeDepositProcessorL1Address"
  castArgs="$modeDepositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "Setting modeTargetDispenserL2Address address"
    castArgs="$modeDepositProcessorL1Address setL2TargetDispenser(address) $modeTargetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "l2TargetDispenser is already set to address $resultAddress"
    echo ""
  fi
fi


### Optimism
# Check for assigned l2TargetDispenser value
echo "OPTIMISM"
if [ "$optimismDepositProcessorL1Address" == "null" ]; then
  echo "!!!optimismDepositProcessorL1Address is not set"
  echo ""
else
  echo "Checking optimismTargetDispenserL2Address address in $optimismDepositProcessorL1Address"
  castArgs="$optimismDepositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "Setting optimismTargetDispenserL2Address address"
    castArgs="$optimismDepositProcessorL1Address setL2TargetDispenser(address) $optimismTargetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "l2TargetDispenser is already set to address $resultAddress"
    echo ""
  fi
fi


### Polygon
# Check for assigned l2TargetDispenser value
echo "POLYGON"
if [ "$polygonDepositProcessorL1Address" == "null" ]; then
  echo "!!!polygonDepositProcessorL1Address is not set"
  echo ""
else
  echo "Checking polygonTargetDispenserL2Address address in $polygonDepositProcessorL1Address"
  castArgs="$polygonDepositProcessorL1Address l2TargetDispenser()"
  castCmd="$castCallHeader $castArgs"
  # Get l2TargetDispenser address
  resultBytes32=$($castCmd)
  resultAddress=$(cast parse-bytes32-address $resultBytes32)

  # Assign l2TargetDispenser value if it is still not set
  if [ "$resultAddress" == "$addressZero" ]; then
    echo "Setting polygonTargetDispenserL2Address address"
    castArgs="$polygonDepositProcessorL1Address setL2TargetDispenser(address) $polygonTargetDispenserL2Address"
    echo $castArgs
    castCmd="$castSendHeader $castArgs"
    result=$($castCmd)
    echo "$result" | grep "status"
  else
    echo "l2TargetDispenser is already set to address $resultAddress"
    echo ""
  fi
fi
