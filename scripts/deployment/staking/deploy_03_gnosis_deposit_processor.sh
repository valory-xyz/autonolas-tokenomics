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
globalsL2="$(dirname "$0")/gnosis/globals_gnosis_$1.json"
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
# L1 Dispenser, bound as this processor's immutable l1Dispenser: a processor bound to the wrong address can only be
# redeployed. Where a root deployment globals exists (mainnet), it is the DispenserProxy that
# deploy_07b_dispenser_proxy.sh records there as dispenserProxyAddress, and further down the proxy's PROXY_DISPENSER
# slot must hold the implementation deploy_07a_dispenser.sh records there as dispenserAddress, with code (the
# PROXY_DISPENSER() getter alone would also pass the implementation). This globals' dispenserAddress keeps the
# pre-proxy Dispenser; it is used only on test networks, which have no root globals.
globalsRoot="$(dirname "$0")/../globals_$1.json"
if [ -f $globalsRoot ]; then
  dispenserAddress=$(jq -r '.dispenserProxyAddress' $globalsRoot)
  dispenserSource="dispenserProxyAddress in $globalsRoot"
else
  # Without a root globals this must be a test network: never fall back to the pre-proxy Dispenser on mainnet
  if [ "$chainId" == "1" ]; then
    echo "${red}!!! $globalsRoot is not found: on mainnet the DispenserProxy is read from it${reset}"
    exit 1
  fi
  dispenserAddress=$(jq -r '.dispenserAddress' $globals)
  dispenserSource="dispenserAddress in $globals"
fi
if [ -z "$dispenserAddress" ] || [ "$dispenserAddress" == "null" ] \
   || [ "$dispenserAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! $dispenserSource is not set (or zero)${reset}"
  exit 1
fi
gnosisOmniBridgeAddress=$(jq -r '.gnosisOmniBridgeAddress' $globals)
gnosisAMBForeignAddress=$(jq -r '.gnosisAMBForeignAddress' $globals)
gnosisL2TargetChainId=$(jq -r '.gnosisL2TargetChainId' $globals)

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

# The DispenserProxy check described where dispenserAddress is read
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
else
  # Test networks: the connected chain must be the one these globals describe, and never mainnet
  if ! connectedChainId=$(cast chain-id --rpc-url $networkURL$API_KEY 2>/dev/null) \
     || [ "$connectedChainId" != "$chainId" ] || [ "$connectedChainId" == "1" ]; then
    echo "${red}!!! Connected to chain '${connectedChainId}', expected $chainId (and not mainnet) for $dispenserSource${reset}"
    exit 1
  fi
fi

contractPath="contracts/staking/GnosisDepositProcessorL1.sol:GnosisDepositProcessorL1"
constructorArgs="$olasAddress $dispenserAddress $gnosisOmniBridgeAddress $gnosisAMBForeignAddress $gnosisL2TargetChainId"
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
gnosisDepositProcessorL1Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#gnosisDepositProcessorL1Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 1
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"gnosisDepositProcessorL1Address":"'$gnosisDepositProcessorL1Address'"}' $globals)" > $globals
# Also write the address into corresponding L2 JSON
echo "$(jq '. += {"gnosisDepositProcessorL1Address":"'$gnosisDepositProcessorL1Address'"}' $globalsL2)" > $globalsL2

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$gnosisDepositProcessorL1Address $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Contract deployed at: $gnosisDepositProcessorL1Address${reset}"