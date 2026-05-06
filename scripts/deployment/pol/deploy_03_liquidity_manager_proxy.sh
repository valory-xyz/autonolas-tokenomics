#!/bin/bash

# Deploys LiquidityManagerProxy pointing at the LiquidityManager implementation from
# deploy_02_liquidity_manager_*.sh. The proxy constructor delegatecall-initializes the impl
# via LiquidityManagerCore.initialize(uint16 _maxSlippage).
#
# Globals fields consumed:
#   liquidityManagerAddress       : LiquidityManager impl (written by deploy_02_*)
#   liquidityManagerMaxSlippage   : uint16 in BPS (MAX_BPS = 10_000); e.g. "500" = 5%
# Globals fields written:
#   liquidityManagerProxyAddress  : deployed proxy address (written to BOTH this folder's
#                                   globals_<network>.json AND ../utils/globals_<network>.json
#                                   so the BBB impl deploy step picks it up automatically)

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="$(dirname "$0")/globals_$1.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

# Get utils globals file — proxy address is consumed by BBB impl deploy step
globalsUtils="$(dirname "$0")/../utils/globals_$1.json"
if [ ! -f $globalsUtils ]; then
  echo "${red}!!! $globalsUtils is not found${reset}"
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

liquidityManagerAddress=$(jq -r '.liquidityManagerAddress' $globals)
liquidityManagerMaxSlippage=$(jq -r '.liquidityManagerMaxSlippage' $globals)

if [ -z "$liquidityManagerAddress" ] || [ "$liquidityManagerAddress" == "null" ] \
   || [ "$liquidityManagerAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! liquidityManagerAddress (impl) is not set in $globals${reset}"
  exit 1
fi
if [ -z "$liquidityManagerMaxSlippage" ] || [ "$liquidityManagerMaxSlippage" == "null" ]; then
  echo "${red}!!! liquidityManagerMaxSlippage is not set in $globals${reset}"
  exit 1
fi

proxyData=$(cast calldata "initialize(uint16)" $liquidityManagerMaxSlippage)

contractName="LiquidityManagerProxy"
contractPath="contracts/proxies/$contractName.sol:$contractName"
constructorArgs="$liquidityManagerAddress $proxyData"
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
liquidityManagerProxyAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#liquidityManagerProxyAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Write new deployed contract back into JSON (both pol/ and utils/)
echo "$(jq '. += {"liquidityManagerProxyAddress":"'$liquidityManagerProxyAddress'"}' $globals)" > $globals
echo "$(jq '. += {"liquidityManagerProxyAddress":"'$liquidityManagerProxyAddress'"}' $globalsUtils)" > $globalsUtils

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$liquidityManagerProxyAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,bytes)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}$contractName deployed at: $liquidityManagerProxyAddress${reset}"
