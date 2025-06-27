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

# Get globals file for L1: globals_mainnet or globals_sepolia
globalsL1="$(dirname "$0")/../globals_${1#*_}.json"
if [ ! -f $globalsL1 ]; then
  echo "${red}!!! $globalsL1 is not found${reset}"
  exit 0
fi

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

olasAddress=$(jq -r '.olasAddress' $globals)
serviceStakingFactoryAddress=$(jq -r '.serviceStakingFactoryAddress' $globals)
modeL2CrossDomainMessengerAddress=$(jq -r '.modeL2CrossDomainMessengerAddress' $globals)
modeDepositProcessorL1Address=$(jq -r '.modeDepositProcessorL1Address' $globals)
l1ChainId=$(jq -r '.l1ChainId' $globals)

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

contractPath="contracts/staking/OptimismTargetDispenserL2.sol:OptimismTargetDispenserL2"
constructorArgs="$olasAddress $serviceStakingFactoryAddress $modeL2CrossDomainMessengerAddress $modeDepositProcessorL1Address $l1ChainId"
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
modeTargetDispenserL2Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#modeTargetDispenserL2Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"modeTargetDispenserL2Address":"'$modeTargetDispenserL2Address'"}' $globals)" > $globals
# Also write the address into corresponding L1 JSON
echo "$(jq '. += {"modeTargetDispenserL2Address":"'$modeTargetDispenserL2Address'"}' $globalsL1)" > $globalsL1

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$modeTargetDispenserL2Address $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Contract deployed at: $modeTargetDispenserL2Address${reset}"