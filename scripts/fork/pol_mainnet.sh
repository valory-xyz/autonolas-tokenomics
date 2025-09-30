#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Get globals file
globals="scripts/deployment/globals_mainnet.json"
if [ ! -f $globals ]; then
  echo "${red}!!! $globals is not found${reset}"
  exit 0
fi

TENDERLY_VIRTUAL_TESTNET_RPC=$1

# Read variables using jq
contractVerification=$(jq -r '.contractVerification' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$TENDERLY_VIRTUAL_TESTNET_RPC

olasAddress=$(jq -r '.olasAddress' $globals)
timelockAddress=$(jq -r '.timelockAddress' $globals)
#oracleV2Address=$(jq -r '.oracleV2Address' $globals)
#routerV2Address=$(jq -r '.routerV2Address' $globals)
routerV2Address="0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
#positionManagerV3=$(jq -r '.positionManagerV3' $globals)
positionManagerV3="0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
maxSlippage="5000" #$(jq -r '.maxSlippage' $globals)
treasuryAddress=$(jq -r '.treasuryAddress' $globals)

wethAddress="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
pairAddress="0x09D1d767eDF8Fa23A64C51fa559E0688E526812F"
maxSlippageOracle="50"

# Get deployer based on the private key
echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
walletArgs="--private-key $PRIVATE_KEY"
deployer=$(cast wallet address $walletArgs)

contractName="UniswapPriceOracle"
contractPath="contracts/oracles/$contractName.sol:$contractName"
constructorArgs="$wethAddress $maxSlippageOracle $pairAddress"
contractArgs="$contractPath --constructor-args $constructorArgs"

# Deployment message
echo "${green}Deploying from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Deployment of: $contractArgs${reset}"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
oracleV2Address=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#oracleV2Address}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$oracleV2Address $contractPath --constructor-args $(cast abi-encode "constructor(address,uint256,address)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  TENDERLY_VERIFIER_URL="$TENDERLY_VIRTUAL_TESTNET_RPC/verify/etherscan"
  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --verifier-url $TENDERLY_VERIFIER_URL --etherscan-api-key $TENDERLY_ACCESS_TOKEN $contractParams
fi

echo "${green}$contractName deployed at: $oracleV2Address${reset}"



contractName="LiquidityManagerETH"
contractPath="contracts/pol/$contractName.sol:$contractName"
constructorArgs="$olasAddress $timelockAddress $oracleV2Address $routerV2Address $positionManagerV3 $maxSlippage"
contractArgs="$contractPath --constructor-args $constructorArgs"


# Deployment message
echo "${green}Deploying from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Deployment of: $contractArgs${reset}"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
liquidityManagerETHAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#liquidityManagerETHAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$liquidityManagerETHAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,uint16)" $constructorArgs)"
  echo "Verification contract params: $contractParams"

  TENDERLY_VERIFIER_URL="$TENDERLY_VIRTUAL_TESTNET_RPC/verify/etherscan"
  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --verifier-url $TENDERLY_VERIFIER_URL --etherscan-api-key $TENDERLY_ACCESS_TOKEN $contractParams
fi

echo "${green}$contractName deployed at: $liquidityManagerETHAddress${reset}"


castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Transfer v2 liquidity to LiquidityManagerETH${reset}"
castArgs="$treasuryAddress withdraw(address,uint256,address) $liquidityManagerETHAddress 63657402469742352862258 $pairAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

echo "${green}Convert liquidity v2 to v3${reset}"
castArgs="$liquidityManagerETHAddress convertToV3(address,uint24,uint16,uint32,uint32) $pairAddress 10000 10000 10000 10000"
echo $castArgs
castCmd="$castSendHeader $castArgs --gas-limit 10000000"
result=$($castCmd)
echo "$result" | grep "status"