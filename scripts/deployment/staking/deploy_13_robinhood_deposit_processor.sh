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
globalsL2="$(dirname "$0")/robinhood/globals_robinhood_$1.json"
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
dispenserAddress=$(jq -r '.dispenserAddress' $globals)
robinhoodL1ERC20GatewayRouterAddress=$(jq -r '.robinhoodL1ERC20GatewayRouterAddress' $globals)
robinhoodInboxAddress=$(jq -r '.robinhoodInboxAddress' $globals)
robinhoodL2TargetChainId=$(jq -r '.robinhoodL2TargetChainId' $globals)
robinhoodL1ERC20GatewayAddress=$(jq -r '.robinhoodL1ERC20GatewayAddress' $globals)
robinhoodOutboxAddress=$(jq -r '.robinhoodOutboxAddress' $globals)
robinhoodBridgeAddress=$(jq -r '.robinhoodBridgeAddress' $globals)

# Validate every constructor input before building the args. `--constructor-args $constructorArgs` is
# unquoted, so an empty value is collapsed by word-splitting rather than passed as an empty token. That
# fails at forge's arity check today, but a stale-but-well-formed address would deploy successfully against
# a wrong immutable binding, which is the hazard this actually guards.
zeroAddress="0x0000000000000000000000000000000000000000"
for pair in "olasAddress:$olasAddress" \
            "dispenserAddress:$dispenserAddress" \
            "robinhoodL1ERC20GatewayRouterAddress:$robinhoodL1ERC20GatewayRouterAddress" \
            "robinhoodInboxAddress:$robinhoodInboxAddress" \
            "robinhoodL2TargetChainId:$robinhoodL2TargetChainId" \
            "robinhoodL1ERC20GatewayAddress:$robinhoodL1ERC20GatewayAddress" \
            "robinhoodOutboxAddress:$robinhoodOutboxAddress" \
            "robinhoodBridgeAddress:$robinhoodBridgeAddress"; do
  key="${pair%%:*}"; val="${pair#*:}"
  if [ -z "$val" ] || [ "$val" == "null" ] || [ "$val" == "$zeroAddress" ] || [ "$val" == "0" ]; then
    echo "${red}!!! $key is not set (or zero) in $globals${reset}"
    exit 1
  fi
done

# Robinhood and Arbitrum One are both Arbitrum Orbit chains sharing ArbitrumDepositProcessorL1, and six of
# the eight constructor arguments are chain-specific. Carrying an Arbitrum One value over would deploy
# successfully and then route OLAS into Arbitrum's escrow under a 4663 chain tag - a silent, unrecoverable
# mis-send. Only _olas and _l1Dispenser are legitimately shared.
# Addresses are lowercased before comparison: block explorers and most CLI output render them
# unchecksummed, so a copied Arbitrum One value most often arrives in lowercase. An exact-string
# comparison would let exactly that paste through the guard.
for key in L1ERC20GatewayRouterAddress InboxAddress L2TargetChainId L1ERC20GatewayAddress OutboxAddress BridgeAddress; do
  rhVal=$(jq -r ".robinhood${key}" $globals | tr '[:upper:]' '[:lower:]')
  arbVal=$(jq -r ".arbitrum${key}" $globals | tr '[:upper:]' '[:lower:]')
  if [ "$arbVal" == "null" ]; then
    echo "${red}!!! arbitrum${key} is absent from $globals - cannot check robinhood${key} for reuse${reset}"
    exit 1
  fi
  if [ "$rhVal" == "$arbVal" ]; then
    echo "${red}!!! robinhood${key} equals arbitrum${key} ($rhVal)${reset}"
    echo "${red}!!! This would bridge to Arbitrum One while tagging chain 4663. Aborting.${reset}"
    exit 1
  fi
done

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

contractPath="contracts/staking/ArbitrumDepositProcessorL1.sol:ArbitrumDepositProcessorL1"
constructorArgs="$olasAddress $dispenserAddress $robinhoodL1ERC20GatewayRouterAddress $robinhoodInboxAddress $robinhoodL2TargetChainId $robinhoodL1ERC20GatewayAddress $robinhoodOutboxAddress $robinhoodBridgeAddress"
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
robinhoodDepositProcessorL1Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#robinhoodDepositProcessorL1Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 1
fi

# Write new deployed contract back into JSON
echo "$(jq '. += {"robinhoodDepositProcessorL1Address":"'$robinhoodDepositProcessorL1Address'"}' $globals)" > $globals
# Also write the address into corresponding L2 JSON
echo "$(jq '. += {"robinhoodDepositProcessorL1Address":"'$robinhoodDepositProcessorL1Address'"}' $globalsL2)" > $globalsL2

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$robinhoodDepositProcessorL1Address $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint256,address,address,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --chain-id "$chainId" --etherscan-api-key "$ETHERSCAN_API_KEY" $contractParams

  blockscoutURL=$(jq -r '.blockscoutURL' $globals)
  if [ "$blockscoutURL" != "null" ]; then
    echo "${green}Verifying contract on Blockscout...${reset}"
    forge verify-contract --verifier blockscout --verifier-url "$blockscoutURL/api" $contractParams
  fi
fi

echo "${green}Contract deployed at: $robinhoodDepositProcessorL1Address${reset}"