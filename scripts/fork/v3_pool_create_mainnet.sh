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
networkURL=$TENDERLY_VIRTUAL_TESTNET_RPC

olasAddress=$(jq -r '.olasAddress' $globals)
positionManagerV3="0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
wethAddress="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

# Get deployer based on the private key
echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
walletArgs="--private-key $PRIVATE_KEY"
deployer=$(cast wallet address $walletArgs)


castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"
#562444884711515384868438111
sqrtPriceX96="577056107611688611954243615"
feeTier="3000"
echo "${green}Create v3 pool${reset}"
castArgs="$positionManagerV3 createAndInitializePoolIfNecessary(address,address,uint24,uint160) $olasAddress $wethAddress $feeTier $sqrtPriceX96"
echo $castArgs
castCmd="$castSendHeader $castArgs --gas-limit 10000000"
result=$($castCmd)
echo "$result" | grep "status"
