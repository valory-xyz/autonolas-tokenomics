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

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

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

olasAddress=$(jq -r '.olasAddress' $globals)
# Recipient: the PolygonBurnForwarder, recorded here by deploy_00e_polygon_burn_forwarder.sh polygon_mainnet. Deploy
# it first. The bridge mediator is no longer a valid destination: OLAS sent there never reaches the L1 burner.
polygonBurnForwarderAddress=$(jq -r '.polygonBurnForwarderAddress' $globals)

zeroAddress="0x0000000000000000000000000000000000000000"
if [ -z "$polygonBurnForwarderAddress" ] || [ "$polygonBurnForwarderAddress" == "null" ] \
   || [ "$polygonBurnForwarderAddress" == "$zeroAddress" ]; then
  echo "${red}!!! polygonBurnForwarderAddress is not set (or zero) in $globals: run deploy_00e_polygon_burn_forwarder.sh first${reset}"
  exit 1
fi

# The recipient must be THE PolygonBurnForwarder: the address deploy_00e derives from both globals (CREATE2, pinned
# solc), with code, reading back all five expected constructor arguments, on this chain and for this OLAS. Every
# read must succeed: a failed RPC call is an error, never a pass.
rpcURL="$networkURL$API_KEY"
source "$(dirname "$0")/polygon_burn_forwarder_common.sh"
pbfLoadArgs || exit 1
if [ "$chainId" != "$polygonChainId" ] \
   || [ "$(echo $olasAddress | tr '[:upper:]' '[:lower:]')" != "$(echo $polygonOlas | tr '[:upper:]' '[:lower:]')" ]; then
  echo "${red}!!! $globals is for OLAS $olasAddress on chain $chainId; the forwarder is for $polygonOlas on $polygonChainId${reset}"
  exit 1
fi
pbfPredict || exit 1
if [ "$(echo $polygonBurnForwarderAddress | tr '[:upper:]' '[:lower:]')" != "$(echo $predicted | tr '[:upper:]' '[:lower:]')" ]; then
  echo "${red}!!! polygonBurnForwarderAddress $polygonBurnForwarderAddress is not the CREATE2 address $predicted${reset}"
  exit 1
fi
pbfCheckDeployed $polygonBurnForwarderAddress || exit 1

contractName="Bridge2BurnerPolygon"
contractPath="contracts/utils/$contractName.sol:$contractName"
# Second arg is the PolygonBurnForwarder (held in the inherited l2TokenRelayer slot); see Bridge2BurnerPolygon NatSpec.
constructorArgs="$olasAddress $polygonBurnForwarderAddress"
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
bridge2BurnerAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#bridge2BurnerAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON (utils + pol if present)
echo "$(jq '. += {"bridge2BurnerAddress":"'$bridge2BurnerAddress'"}' $globals)" > $globals

# Conditionally dual-write into pol/globals_<network>.json — pol/deploy_02_liquidity_manager_*.sh
# reads bridge2BurnerAddress from there. V3-enabled chains have pol/globals_*.json; V2-only
# chains (gnosis, polygon, arbitrum, celo) do not — silently skip in that case.
globalsPol="$(dirname "$0")/../pol/globals_$1.json"
if [ -f "$globalsPol" ]; then
  echo "$(jq '. += {"bridge2BurnerAddress":"'$bridge2BurnerAddress'"}' "$globalsPol")" > "$globalsPol"
fi

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$bridge2BurnerAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}$contractName deployed at: $bridge2BurnerAddress${reset}"
