#!/bin/bash

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "!!! $globals is not found"
  exit 0
fi

# Get globals file for L2
globalsL2="$(dirname "$0")/optimism/globals_optimism_$1.json"
if [ ! -f $globalsL2 ]; then
  echo "!!! $globalsL2 is not found"
  exit 0
fi

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

olasAddress=$(jq -r '.olasAddress' $globals)
dispenserAddress=$(jq -r '.dispenserAddress' $globals)
optimismL1StandardBridgeProxyAddress=$(jq -r '.optimismL1StandardBridgeProxyAddress' $globals)
optimismL1CrossDomainMessengerProxyAddress=$(jq -r '.optimismL1CrossDomainMessengerProxyAddress' $globals)
optimismL2TargetChainId=$(jq -r '.optimismL2TargetChainId' $globals)
optimismOLASAddress=$(jq -r '.optimismOLASAddress' $globals)

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

contractPath="contracts/staking/OptimismDepositProcessorL1.sol:OptimismDepositProcessorL1"
constructorArgs="$olasAddress $dispenserAddress $optimismL1StandardBridgeProxyAddress $optimismL1CrossDomainMessengerProxyAddress $optimismL2TargetChainId $optimismOLASAddress"
contractArgs="$contractPath --constructor-args $constructorArgs"

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

# Deployment message
echo "Deploying from: $deployer"
echo "RPC: $networkURL"
echo "Deployment of: $contractArgs"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
optimismDepositProcessorL1Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#optimismDepositProcessorL1Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "!!! The contract was not deployed..."
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"optimismDepositProcessorL1Address":"'$optimismDepositProcessorL1Address'"}' $globals)" > $globals
# Also write the address into corresponding L2 JSON
echo "$(jq '. += {"optimismDepositProcessorL1Address":"'$optimismDepositProcessorL1Address'"}' $globalsL2)" > $globalsL2

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$optimismDepositProcessorL1Address $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "Verifying contract on Etherscan..."
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "Verifying contract on Blockscout..."
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "Contract deployed at: $optimismDepositProcessorL1Address"