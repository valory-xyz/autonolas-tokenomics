#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Get globals file for L2
globalsL2="$(dirname "$0")/polygon/globals_polygon_$1.json"
if [ ! -f $globalsL2 ]; then
  echo "${red}!!! $globalsL2 is not found${reset}"
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
polygonRootChainManagerProxyAddress=$(jq -r '.polygonRootChainManagerProxyAddress' $globals)
polygonFXRootAddress=$(jq -r '.polygonFXRootAddress' $globals)
polygonL2TargetChainId=$(jq -r '.polygonL2TargetChainId' $globals)
polygonCheckpointManagerAddress=$(jq -r '.polygonCheckpointManagerAddress' $globals)
polygonERC20PredicateAddress=$(jq -r '.polygonERC20PredicateAddress' $globals)

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

contractPath="contracts/staking/PolygonDepositProcessorL1.sol:PolygonDepositProcessorL1"
constructorArgs="$olasAddress $dispenserAddress $polygonRootChainManagerProxyAddress $polygonFXRootAddress $polygonL2TargetChainId $polygonCheckpointManagerAddress $polygonERC20PredicateAddress"
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
echo "${green}Deploying from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Deployment of: $contractArgs${reset}"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL$API_KEY $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
polygonDepositProcessorL1Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#polygonDepositProcessorL1Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"polygonDepositProcessorL1Address":"'$polygonDepositProcessorL1Address'"}' $globals)" > $globals
# Also write the address into corresponding L2 JSON
echo "$(jq '. += {"polygonDepositProcessorL1Address":"'$polygonDepositProcessorL1Address'"}' $globalsL2)" > $globalsL2

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$polygonDepositProcessorL1Address $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256,address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Contract deployed at: $polygonDepositProcessorL1Address${reset}"