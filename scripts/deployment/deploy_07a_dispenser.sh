#!/bin/bash

# Deploys the Dispenser implementation (proxy-based Dispenser). The constructor sets the
# implementation-bytecode immutables only; the mutable state is set by initialize(), which is
# delegatecall-ed by the DispenserProxy constructor in deploy_07b_dispenser_proxy.sh.
#
# WARNING: the constructor immutables are safety-critical — a wrong value silently rewires the proxy.
# Double-check tokenomicsProxyAddress (NOT the tokenomics implementation) and retainerAddress.
#
# Globals fields consumed:
#   olasAddress            : OLAS token address
#   tokenomicsProxyAddress : Tokenomics PROXY address (implementation immutable)
#   retainerAddress        : retainer in bytes32 form
# Globals fields written:
#   dispenserAddress       : deployed Dispenser implementation address (consumed by deploy_07b_*)

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
  esac
  if [ -n "$keyName" ] && [ "$API_KEY" == "" ]; then
    echo "set $keyName env variable"
    exit 0
  fi
fi

olasAddress=$(jq -r '.olasAddress' $globals)
tokenomicsProxyAddress=$(jq -r '.tokenomicsProxyAddress' $globals)
retainerAddress=$(jq -r '.retainerAddress' $globals)

if [ -z "$tokenomicsProxyAddress" ] || [ "$tokenomicsProxyAddress" == "null" ] \
   || [ "$tokenomicsProxyAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! tokenomicsProxyAddress is not set in $globals${reset}"
  exit 1
fi

contractName="Dispenser"
contractPath="contracts/$contractName.sol:$contractName"
constructorArgs="$olasAddress $tokenomicsProxyAddress $retainerAddress"
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
dispenserAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#dispenserAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"dispenserAddress":"'$dispenserAddress'"}' $globals)" > $globals

# Lock the standalone implementation: claim its (inert) storage owner so nobody else can initialize() it.
# The implementation is only ever delegatecall-ed by the proxy against the PROXY's storage, so the impl's own
# storage is never used and these are throwaway values (Vote Weighting is allowed to be zero at initialize).
# This sets owner != 0 on the impl, making a later initialize() revert AlreadyInitialized. Best-effort (the
# impl holds no funds and cannot affect the proxy, so an unlocked impl is harmless — this just removes the question).
zeroAddress="0x0000000000000000000000000000000000000000"
echo "${green}Locking the implementation (initialize on the impl itself)...${reset}"
lockResult=$(cast send --rpc-url $networkURL$API_KEY $walletArgs $dispenserAddress \
  "initialize(address,address,uint256,uint256)" $deployer $zeroAddress 1 1)
lockStatus=$(echo "$lockResult" | grep -iE '^status' | grep -oiE '1 \(success\)|0 \(failed\)')
if [ -z "$lockStatus" ] || [[ "$lockStatus" == 0* ]]; then
  echo "${red}!!! Implementation lock tx did not succeed — impl left unlocked. Harmless (the impl cannot affect the proxy), but investigate.${reset}"
else
  echo "${green}Implementation locked (status: $lockStatus)${reset}"
fi

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$dispenserAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address,bytes32)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}$contractName deployed at: $dispenserAddress${reset}"
