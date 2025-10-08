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
observationCardinality="60" #$(jq -r '.observationCardinality' $globals)
maxSlippage="5000" #$(jq -r '.maxSlippage' $globals)
treasuryAddress=$(jq -r '.treasuryAddress' $globals)

wethAddress="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
pairAddress="0x09D1d767eDF8Fa23A64C51fa559E0688E526812F"
pairBytes32Address="0x00000000000000000000000009D1d767eDF8Fa23A64C51fa559E0688E526812F"
maxSlippageOracle="50"

# Get deployer based on the private key
echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
walletArgs="--private-key $PRIVATE_KEY"
deployer=$(cast wallet address $walletArgs)


contractName="NeighborhoodScanner"
contractPath="contracts/pol/$contractName.sol:$contractName"
contractArgs="$contractPath"

# Deployment message
echo "${green}Deploying from: $deployer${reset}"
echo "RPC: $networkURL"
echo "${green}Deployment of: $contractArgs${reset}"

# Deploy the contract and capture the address
execCmd="forge create --broadcast --rpc-url $networkURL $walletArgs $contractArgs"
deploymentOutput=$($execCmd)
neighborhoodScannerAddress=$(echo "$deploymentOutput" | grep 'Deployed to:' | awk '{print $3}')

# Get output length
outputLength=${#neighborhoodScannerAddress}

# Check for the deployed address
if [ $outputLength != 42 ]; then
  echo "${red}!!! The contract was not deployed...${reset}"
  exit 0
fi

# Verify contract
if [ "$contractVerification" == "true" ]; then
  contractParams="$neighborhoodScannerAddress $contractPath"
  echo "Verification contract params: $contractParams"

  TENDERLY_VERIFIER_URL="$TENDERLY_VIRTUAL_TESTNET_RPC/verify/etherscan"
  echo "${green}Verifying contract on Etherscan...${reset}"
  forge verify-contract --verifier-url $TENDERLY_VERIFIER_URL --etherscan-api-key $TENDERLY_ACCESS_TOKEN $contractParams
fi

echo "${green}$contractName deployed at: $neighborhoodScannerAddress${reset}"


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


#neighborhoodScannerAddress="0x17806E2a12d5E0F48C9803cd397DB3F044DA3b77"
#oracleV2Address="0xf805DfF246CC208CD2F08ffaD242b7C32bc93623"
contractName="LiquidityManagerETH"
contractPath="contracts/pol/$contractName.sol:$contractName"
constructorArgs="$olasAddress $timelockAddress $positionManagerV3 $neighborhoodScannerAddress $observationCardinality $maxSlippage $oracleV2Address $routerV2Address"
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
  contractParams="$liquidityManagerETHAddress $contractPath --constructor-args $(cast abi-encode "constructor(address,address,address,address,uint16,uint16,address,address)" $constructorArgs)"
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

sqrtPriceX96="534584642253494991316723471"
feeTier="3000"
echo "${green}Create v3 pool${reset}"
castArgs="$positionManagerV3 createAndInitializePoolIfNecessary(address,address,uint24,uint160) $olasAddress $wethAddress $feeTier $sqrtPriceX96"
echo $castArgs
castCmd="$castSendHeader $castArgs --gas-limit 10000000"
result=$($castCmd)
echo "$result" | grep "status"

liquidityManagerETHAddress="0xf805DfF246CC208CD2F08ffaD242b7C32bc93623"
feeTier="3000"
tickShifts="[-27000,17000]"
conversionRatio="10000"
scan="true"
echo "${green}Convert liquidity v2 to v3${reset}"
castArgs="$liquidityManagerETHAddress convertToV3(address[],bytes32,int24,int24[],uint16,bool) [$olasAddress,$wethAddress] $pairBytes32Address $feeTier $tickShifts $conversionRatio $scan"
echo $castArgs
castCmd="$castSendHeader $castArgs --gas-limit 10000000"
result=$($castCmd)
echo "$result" | grep "status"

feeTier="3000"
decreaseBPS="1000"
olasWithdrawRate="1000"
echo "${green}Convert liquidity v2 to v3${reset}"
castArgs="$liquidityManagerETHAddress decreaseLiquidity(address[],int24,uint16,uint16) [$olasAddress,$wethAddress] $feeTier $decreaseBPS $olasWithdrawRate"
echo $castArgs
castCmd="$castSendHeader $castArgs --gas-limit 10000000"
result=$($castCmd)
echo "$result" | grep "status"

feeTier="3000"
tickShifts="[-60000,50000]"
scan="true"
echo "${green}Convert liquidity v2 to v3${reset}"
castArgs="$liquidityManagerETHAddress changeRanges(address[],int24,int24[],bool) [$olasAddress,$wethAddress] $feeTier $tickShifts $scan"
echo $castArgs
castCmd="$castSendHeader $castArgs --gas-limit 10000000"
result=$($castCmd)
echo "$result" | grep "status"


# 0-10_000 scan: (1095749, 296529313208847165116700, 11600311078511418647320239, 1308995137273818446)
# 0-10_000 NO scan: (tokenId = 1095760, liquidity = 285849558401305010535305, amount0 = 11600311078511418647320259, amount1 = 1261850566779017633)
# 5_000-5_000 NO scan: tokenId = 1095760, liquidity = 282406627568043750504737, amount0 = 7230462299149671543408528, amount1 = 605380455860687285676
# 5_000-5_000 scan: tokenId = 1095760, liquidity = 293024292431549955228145, amount0 = 7989555146328987190087827, amount1 = 605380455860687285676
# 2_500-5_000 NO scan: tokenId = 1095760, liquidity = 453083716487657519572652, amount0 = 11600311078511418647320261, amount1 = 444284751492942740375
# 2_500-7_500 NO scan: tokenId = 1095760, liquidity = 341349770097768902143153, amount0 = 11600311078511418647320258, amount1 = 334720697878339393167
# 2_500-2_500 NO scan: tokenId = 1095760, liquidity = 617369887011999881316450, amount0 = 9312934452099441370697994, amount1 = 605380455860687285676
# 1_000-1_000 NO scan: tokenId = 1095760, liquidity = 1564126911624377359055496, amount0 = 11165025660744591306452400, amount1 = 605380455860687285676
# 1_000-1_000 scan: tokenId = 1095760, liquidity = 1278144088969628280075128, amount0 = 11600311078511418647320264, amount1 = 361484111146014781789