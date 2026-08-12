#!/bin/bash

# Deploys DispenserProxy pointing at the Dispenser implementation from deploy_07a_dispenser.sh.
# The proxy constructor delegatecall-initializes the impl via
# Dispenser.initialize(address _treasury, address _voteWeighting, uint256 _maxNumClaimingEpochs,
# uint256 _maxNumStakingTargets); the caller (deployer) becomes the proxy owner atomically, and
# staking incentives are paused until the DAO wires and unpauses them.
#
# Vote Weighting is initialized to the ZERO address on purpose: it is deployed AFTER this proxy (its
# `dispenser` immutable binds this proxy's address), so it cannot exist yet at init time. It is wired in
# afterwards with script_dispenser_change_managers.sh, while the proxy is still paused. This is what breaks
# the otherwise-circular deploy order (Dispenser <-> Vote Weighting).
#
# Deploy order: deploy_07a (impl) -> deploy_07b (proxy, VW = 0) -> deploy Vote Weighting(ve, THIS proxy) ->
#               script_dispenser_change_managers.sh (sets the real VW) -> set deposit processors -> unpause.
#
# Globals fields consumed:
#   dispenserAddress      : Dispenser implementation (written by deploy_07a_*)
#   treasuryAddress       : Treasury address
#   maxNumClaimingEpochs  : max number of epochs to claim staking incentives for
#   maxNumStakingTargets  : max number of staking targets on a single chain Id
# Globals fields written:
#   dispenserProxyAddress : deployed proxy address (the live Dispenser address to wire everywhere,
#                           and the address Vote Weighting must be deployed against)

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

dispenserAddress=$(jq -r '.dispenserAddress' $globals)
treasuryAddress=$(jq -r '.treasuryAddress' $globals)
maxNumClaimingEpochs=$(jq -r '.maxNumClaimingEpochs' $globals)
maxNumStakingTargets=$(jq -r '.maxNumStakingTargets' $globals)

if [ -z "$dispenserAddress" ] || [ "$dispenserAddress" == "null" ] \
   || [ "$dispenserAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! dispenserAddress (impl) is not set in $globals${reset}"
  exit 1
fi

# Vote Weighting is wired later via script_dispenser_change_managers.sh — initialize with the zero address
voteWeightingAddress="0x0000000000000000000000000000000000000000"
proxyData=$(cast calldata "initialize(address,address,uint256,uint256)" $treasuryAddress $voteWeightingAddress $maxNumClaimingEpochs $maxNumStakingTargets)

contractName="DispenserProxy"
contractPath="contracts/proxies/$contractName.sol:$contractName"
constructorArgs="$dispenserAddress $proxyData"
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
dispenserProxyAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#dispenserProxyAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"dispenserProxyAddress":"'$dispenserProxyAddress'"}' $globals)" > $globals

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$dispenserProxyAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,bytes)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}$contractName deployed at: $dispenserProxyAddress${reset}"
