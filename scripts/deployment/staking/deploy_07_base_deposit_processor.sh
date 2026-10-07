#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 1
fi

# Get globals file for L2
globalsL2="$(dirname "$0")/base/globals_base_$1.json"
if [ ! -f $globalsL2 ]; then
  echo "${red}!!! $globalsL2 is not found${reset}"
  exit 1
fi

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

olasAddress=$(jq -r '.olasAddress' $globals)
# L1 Dispenser, bound as this processor's immutable l1Dispenser. Where a root deployment globals exists (mainnet),
# it is the DispenserProxy that deploy_07b_dispenser_proxy.sh records there: this globals' dispenserAddress keeps
# the pre-proxy Dispenser, and a processor bound to it could only be fixed by a redeploy. Networks without a root
# globals (test networks) keep using this globals' dispenserAddress.
globalsRoot="$(dirname "$0")/../globals_$1.json"
if [ -f $globalsRoot ]; then
  dispenserAddress=$(jq -r '.dispenserProxyAddress' $globalsRoot)
  dispenserSource="dispenserProxyAddress in $globalsRoot"
else
  dispenserAddress=$(jq -r '.dispenserAddress' $globals)
  dispenserSource="dispenserAddress in $globals"
fi
if [ -z "$dispenserAddress" ] || [ "$dispenserAddress" == "null" ] \
   || [ "$dispenserAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! $dispenserSource is not set (or zero)${reset}"
  exit 1
fi
baseL1StandardBridgeProxyAddress=$(jq -r '.baseL1StandardBridgeProxyAddress' $globals)
baseL1CrossDomainMessengerProxyAddress=$(jq -r '.baseL1CrossDomainMessengerProxyAddress' $globals)
baseL2TargetChainId=$(jq -r '.baseL2TargetChainId' $globals)
baseOLASAddress=$(jq -r '.baseOLASAddress' $globals)

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

contractPath="contracts/staking/OptimismDepositProcessorL1.sol:OptimismDepositProcessorL1"
constructorArgs="$olasAddress $dispenserAddress $baseL1StandardBridgeProxyAddress $baseL1CrossDomainMessengerProxyAddress $baseL2TargetChainId $baseOLASAddress"
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
baseDepositProcessorL1Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#baseDepositProcessorL1Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 1
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"baseDepositProcessorL1Address":"'$baseDepositProcessorL1Address'"}' $globals)" > $globals
# Also write the address into corresponding L2 JSON
echo "$(jq '. += {"baseDepositProcessorL1Address":"'$baseDepositProcessorL1Address'"}' $globalsL2)" > $globalsL2

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$baseDepositProcessorL1Address $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Contract deployed at: $baseDepositProcessorL1Address${reset}"