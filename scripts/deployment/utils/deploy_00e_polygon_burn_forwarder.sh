#!/bin/bash

# Deploys PolygonBurnForwarder by CREATE2 at the same address on Polygon and on Ethereum.
#
# Usage: deploy_00e_polygon_burn_forwarder.sh <polygon_mainnet|eth_mainnet>
# Run it once per chain, from the same checkout and build: the address depends on the exact init code.
#
# The constructor arguments, init code and address are derived by polygon_burn_forwarder_common.sh, shared with
# deploy_00c_bridge2burner_polygon.sh. The arguments are read from BOTH globals files, whichever chain is being
# deployed, and the init code is built with solc 0.8.30 pinned, so that it is identical on the two chains:
#   polygonOlas    : olasAddress in globals_polygon_mainnet.json
#   l1Olas         : olasAddress in globals_eth_mainnet.json
#   olasBurner     : burnerAddress in globals_eth_mainnet.json
#   polygonChainId : chainId in globals_polygon_mainnet.json
#   l1ChainId      : chainId in globals_eth_mainnet.json
# The deployment goes through the deterministic CREATE2 deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C (same
# address and code on both chains) with salt keccak256("PolygonBurnForwarder"). The predicted address is checked
# before sending: if the other chain already records polygonBurnForwarderAddress, the two must match, or nothing is
# sent. The deployed address is written to the deployed chain's globals as polygonBurnForwarderAddress.

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

case "$1" in
  polygon_mainnet) other="eth_mainnet" ;;
  eth_mainnet)     other="polygon_mainnet" ;;
  *)
    echo "${red}!!! Usage: $0 <polygon_mainnet|eth_mainnet>${reset}"
    exit 1
    ;;
esac

# Get globals files
globals="$(dirname "$0")/globals_$1.json"
globalsOther="$(dirname "$0")/globals_$other.json"
# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

# Shared PolygonBurnForwarder derivation: arguments, init code, CREATE2 address, on-chain checks
source "$(dirname "$0")/polygon_burn_forwarder_common.sh"
pbfLoadArgs || exit 1

# Check for Alchemy keys
if [[ "$networkURL" == *"alchemy.com"* ]]; then
  case $chainId in
    1)        API_KEY=$ALCHEMY_API_KEY_MAINNET; keyName="ALCHEMY_API_KEY_MAINNET" ;;
    137)      API_KEY=$ALCHEMY_API_KEY_MATIC;   keyName="ALCHEMY_API_KEY_MATIC" ;;
  esac
  if [ -n "$keyName" ] && [ "$API_KEY" == "" ]; then
    echo "set $keyName env variable"
    exit 1
  fi
fi
rpcURL="$networkURL$API_KEY"

# The RPC must serve the chain this globals file describes
if ! rpcChainId=$(cast chain-id --rpc-url $rpcURL 2>/dev/null) || [ "$rpcChainId" != "$chainId" ]; then
  echo "${red}!!! The RPC for $1 reports chain '${rpcChainId}', expected $chainId (or it is unreachable)${reset}"
  exit 1
fi

contractName=$pbfContractName
contractPath=$pbfContractPath
create2Factory=$pbfFactory
salt=$pbfSalt

# The factory must be live on this chain
factoryCode=$(getCode $create2Factory) || exit 1
if [ "$factoryCode" == "0x" ]; then
  echo "${red}!!! CREATE2 factory $create2Factory has no code on chain $chainId${reset}"
  exit 1
fi

# Init code (solc pinned) and CREATE2 address
pbfPredict || exit 1

echo "${green}$contractName on chain $chainId${reset}"
echo "  polygonOlas=$polygonOlas l1Olas=$l1Olas olasBurner=$olasBurner chainIds=$polygonChainId/$l1ChainId"
echo "  solc $pbfSolc, init code hash: $(cast keccak $initCode)"
echo "  predicted address: $predicted"

# Cross-chain check: the address must match the one already deployed on the other chain, if any
otherAddress=$(jq -r '.polygonBurnForwarderAddress' $globalsOther)
if [ -n "$otherAddress" ] && [ "$otherAddress" != "null" ]; then
  if [ "$(echo $otherAddress | tr '[:upper:]' '[:lower:]')" != "$(echo $predicted | tr '[:upper:]' '[:lower:]')" ]; then
    echo "${red}!!! Predicted $predicted differs from $otherAddress recorded on $other: the init code differs${reset}"
    echo "${red}    (compiler version or settings, or constructor arguments). Nothing was sent.${reset}"
    exit 1
  fi
  echo "  matches $other: $otherAddress"
else
  echo "  first of the two deployments: deploy the other chain from this same checkout and build"
fi

# Deploy unless it already exists at the predicted address
predictedCode=$(getCode $predicted) || exit 1
if [ "$predictedCode" != "0x" ]; then
  echo "${green}Code already present at $predicted${reset}"
else
  # Get deployer based on the ledger flag
  if [ "$useLedger" == "true" ]; then
    walletArgs="-l --mnemonic-derivation-path $derivationPath"
    deployer=$(cast wallet address $walletArgs)
  else
    echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
    walletArgs="--private-key $PRIVATE_KEY"
    deployer=$(cast wallet address $walletArgs)
  fi
  echo "${green}Deploying from: $deployer${reset}"

  # The factory takes salt ++ init code as calldata
  if ! result=$(cast send --rpc-url $rpcURL $walletArgs $create2Factory "$salt${initCode:2}"); then
    echo "${red}!!! The deployment transaction could not be sent${reset}"
    exit 1
  fi
  echo "$result" | grep -E "status|transactionHash"
  if ! echo "$result" | grep -qE "^status +1"; then
    echo "${red}!!! The deployment transaction failed${reset}"
    exit 1
  fi

  predictedCode=$(getCode $predicted) || exit 1
  if [ "$predictedCode" == "0x" ]; then
    echo "${red}!!! No code at the predicted address $predicted after deployment${reset}"
    exit 1
  fi
fi

# Success is recorded only once the contract at the predicted address reads back the expected immutables
pbfCheckDeployed $predicted || exit 1
echo "${green}Verified on-chain: $predicted is $contractName with the expected arguments${reset}"

# Write the deployed address back into this chain's globals
echo "$(jq '. += {"polygonBurnForwarderAddress":"'$predicted'"}' $globals)" > $globals

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$predicted $contractPath --constructor-args $encodedArgs"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  FOUNDRY_SOLC_VERSION=$pbfSolc forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    FOUNDRY_SOLC_VERSION=$pbfSolc forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}$contractName deployed at: $predicted${reset}"
