#!/bin/bash

# Shared by deploy_00e_polygon_burn_forwarder.sh and deploy_00c_bridge2burner_polygon.sh, which source it, so that
# both derive the PolygonBurnForwarder from the same arguments, init code and CREATE2 address.
#
# The caller sets red / reset, and before the on-chain helpers also chainId and rpcURL. Every function returns
# non-zero on failure and the caller exits: call them directly (`pbfLoadArgs || exit 1`), not inside $(...),
# except getCode / callValue, which print their result (`x=$(getCode <address>) || exit 1`).

pbfContractName="PolygonBurnForwarder"
pbfContractPath="contracts/utils/$pbfContractName.sol:$pbfContractName"
# Deterministic CREATE2 deployer, at the same address and with the same code on Ethereum and Polygon
pbfFactory="0x4e59b44847b379578588920cA78FbF26c0B4956C"
pbfSalt=$(cast keccak "PolygonBurnForwarder")
# The address depends on the exact init code: pin the compiler for the build the address is derived from
pbfSolc="0.8.30"
pbfZeroAddress="0x0000000000000000000000000000000000000000"

# Reads the constructor arguments from both utils globals, whichever chain is being handled, so that the init code
# is identical on the two chains. Sets polygonOlas, l1Olas, olasBurner, polygonChainId, l1ChainId.
pbfLoadArgs() {
  local dir="$(dirname "${BASH_SOURCE[0]}")"
  local globalsPolygon="$dir/globals_polygon_mainnet.json"
  local globalsEth="$dir/globals_eth_mainnet.json"
  local g pair key val
  for g in $globalsPolygon $globalsEth; do
    if [ ! -f $g ]; then
      echo "${red}!!! $g is not found${reset}"
      return 1
    fi
  done
  polygonOlas=$(jq -r '.olasAddress' $globalsPolygon)
  l1Olas=$(jq -r '.olasAddress' $globalsEth)
  olasBurner=$(jq -r '.burnerAddress' $globalsEth)
  polygonChainId=$(jq -r '.chainId' $globalsPolygon)
  l1ChainId=$(jq -r '.chainId' $globalsEth)
  for pair in "polygonOlas:$polygonOlas" "l1Olas:$l1Olas" "olasBurner:$olasBurner" \
              "polygonChainId:$polygonChainId" "l1ChainId:$l1ChainId"; do
    key="${pair%%:*}"; val="${pair#*:}"
    if [ -z "$val" ] || [ "$val" == "null" ] || [ "$val" == "$pbfZeroAddress" ] || [ "$val" == "0" ]; then
      echo "${red}!!! $key is not set (or zero)${reset}"
      return 1
    fi
  done
}

# Builds the init code with the pinned compiler and computes the CREATE2 address. Needs pbfLoadArgs first.
# Sets encodedArgs, initCode, predicted.
pbfPredict() {
  local creationCode
  if ! creationCode=$(FOUNDRY_SOLC_VERSION=$pbfSolc forge inspect $pbfContractPath bytecode) \
     || [ -z "$creationCode" ] || [ "$creationCode" == "0x" ]; then
    echo "${red}!!! Could not get the $pbfContractName creation code with solc $pbfSolc${reset}"
    return 1
  fi
  encodedArgs=$(cast abi-encode "constructor(address,address,address,uint256,uint256)" \
    $polygonOlas $l1Olas $olasBurner $polygonChainId $l1ChainId)
  initCode="$creationCode${encodedArgs:2}"
  predicted=$(cast create2 --deployer $pbfFactory --salt $pbfSalt --init-code $initCode | awk '{print $NF}')
  if ! [[ "$predicted" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "${red}!!! Could not compute the CREATE2 address${reset}"
    return 1
  fi
}

# On-chain reads. A failed RPC call or a malformed response is an error, never "no code" or "already deployed".
getCode() {
  local out
  if ! out=$(cast code --rpc-url $rpcURL $1 2>/dev/null); then
    echo "${red}!!! Could not read the code at $1 on chain $chainId (RPC error)${reset}" >&2
    return 1
  fi
  if ! [[ "$out" =~ ^0x([0-9a-fA-F]{2})*$ ]]; then
    echo "${red}!!! Malformed code response for $1 on chain $chainId: '$out'${reset}" >&2
    return 1
  fi
  echo "$out"
}

# Reads a single-value getter; fails on an RPC error or an empty response
callValue() {
  local out
  if ! out=$(cast call --rpc-url $rpcURL $1 "$2" 2>/dev/null) || [ -z "$out" ]; then
    echo "${red}!!! Could not call $2 on $1 on chain $chainId (RPC error)${reset}" >&2
    return 1
  fi
  echo "$out" | awk '{print $1}' | tr '[:upper:]' '[:lower:]'
}

# The contract at the given address must have code and read back all five expected constructor arguments
pbfCheckDeployed() {
  local address=$1 code rPolygonOlas rL1Olas rOlasBurner rPolygonChainId rL1ChainId
  code=$(getCode $address) || return 1
  if [ "$code" == "0x" ]; then
    echo "${red}!!! No code at $address on chain $chainId${reset}"
    return 1
  fi
  rPolygonOlas=$(callValue $address "polygonOlas()(address)") || return 1
  rL1Olas=$(callValue $address "l1Olas()(address)") || return 1
  rOlasBurner=$(callValue $address "olasBurner()(address)") || return 1
  rPolygonChainId=$(callValue $address "polygonChainId()(uint256)") || return 1
  rL1ChainId=$(callValue $address "l1ChainId()(uint256)") || return 1
  if [ "$rPolygonOlas" != "$(echo $polygonOlas | tr '[:upper:]' '[:lower:]')" ] \
     || [ "$rL1Olas" != "$(echo $l1Olas | tr '[:upper:]' '[:lower:]')" ] \
     || [ "$rOlasBurner" != "$(echo $olasBurner | tr '[:upper:]' '[:lower:]')" ] \
     || [ "$rPolygonChainId" != "$polygonChainId" ] || [ "$rL1ChainId" != "$l1ChainId" ]; then
    echo "${red}!!! The contract at $address does not read back the expected $pbfContractName arguments${reset}"
    return 1
  fi
}
