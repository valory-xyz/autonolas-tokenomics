#!/bin/bash

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Globals files
globalsMainnet="scripts/deployment/globals_mainnet.json"
globalsStaking="scripts/deployment/staking/globals_mainnet.json"
globalsCelo="scripts/deployment/staking/celo/globals_celo_mainnet.json"

for f in $globalsMainnet $globalsStaking $globalsCelo; do
  if [ ! -f "$f" ]; then
    echo "${red}!!! $f is not found${reset}"
    exit 1
  fi
done

# Check OLAS_AMOUNT env variable
if [ -z "$OLAS_AMOUNT" ]; then
  echo "${red}!!! OLAS_AMOUNT env variable is not set${reset}"
  exit 1
fi

# Addresses from mainnet globals
timelockAddress=$(jq -r '.timelockAddress' $globalsMainnet)
treasuryAddress=$(jq -r '.treasuryAddress' $globalsMainnet)
olasAddress=$(jq -r '.olasAddress' $globalsMainnet)

# Wormhole addresses from staking globals
wormholeL1TokenRelayerAddress=$(jq -r '.wormholeL1TokenRelayerAddress' $globalsStaking)
celoWormholeL2TargetChainId=$(jq -r '.celoWormholeL2TargetChainId' $globalsStaking)

# Celo L1 Standard Bridge
celoL1StandardBridgeProxyAddress=$(jq -r '.celoL1StandardBridgeProxyAddress' $globalsStaking)

# Celo OLAS address (L2 token)
celoOLASAddress=$(jq -r '.celoOLASAddress' $globalsStaking)

# Bridge mediator on Celo (recipient of LP tokens)
bridgeMediatorAddress=$(jq -r '.bridgeMediatorAddress' $globalsCelo)

# Bridged LP token address
lpTokenAddress="0xC085F31E4ca659fF8A17042dDB26f1dcA2fBdAB4"

# RPC URL
networkURL=$(jq -r '.networkURL' $globalsMainnet)

echo "${green}=== Proposal 24: Transfer bridged LP tokens from Treasury to Celo ===${reset}"
echo ""
echo "Treasury:            $treasuryAddress"
echo "Timelock:            $timelockAddress"
echo "OLAS:                $olasAddress"
echo "OLAS Amount:         $OLAS_AMOUNT"
echo "LP Token:            $lpTokenAddress"
echo "Wormhole Bridge:     $wormholeL1TokenRelayerAddress"
echo "Celo Std Bridge:     $celoL1StandardBridgeProxyAddress"
echo "Celo OLAS (L2):      $celoOLASAddress"
echo "Bridge Mediator:     $bridgeMediatorAddress"
echo "Wormhole Chain ID:   $celoWormholeL2TargetChainId"
echo ""

# Step 0: Fetch LP token balance of Treasury
echo "${green}Fetching LP token balance of Treasury...${reset}"
lpBalance=$(cast call --rpc-url ${networkURL}${ALCHEMY_API_KEY_MAINNET} $lpTokenAddress "balanceOf(address)(uint256)" $treasuryAddress)
echo "LP token balance: $lpBalance"

if [ "$lpBalance" == "0" ]; then
  echo "${red}LP token balance is zero, nothing to transfer${reset}"
  exit 1
fi

# Convert bridgeMediator address to bytes32 for Wormhole recipient
recipientBytes32=$(cast --to-bytes32 $bridgeMediatorAddress)

# Step 1: Treasury.withdraw(timelockAddress, lpBalance, lpTokenAddress)
echo ""
echo "${green}Step 1: Treasury.withdraw() - withdraw LP tokens to Timelock${reset}"
calldata1=$(cast calldata "withdraw(address,uint256,address)" $timelockAddress $lpBalance $lpTokenAddress)
echo "Target:   $treasuryAddress"
echo "Value:    0"
echo "Calldata: $calldata1"

# Step 2a: LP token approve Wormhole Token Bridge
echo ""
echo "${green}Step 2a: LP token approve() - approve Wormhole Token Bridge${reset}"
calldata2a=$(cast calldata "approve(address,uint256)" $wormholeL1TokenRelayerAddress $lpBalance)
echo "Target:   $lpTokenAddress"
echo "Value:    0"
echo "Calldata: $calldata2a"

# Step 2b: Wormhole Token Bridge transferTokens()
# transferTokens(address token, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce)
echo ""
echo "${green}Step 2b: Wormhole transferTokens() - bridge LP tokens to Celo${reset}"
nonce=0
arbiterFee=0
calldata2b=$(cast calldata "transferTokens(address,uint256,uint16,bytes32,uint256,uint32)" $lpTokenAddress $lpBalance $celoWormholeL2TargetChainId $recipientBytes32 $arbiterFee $nonce)
echo "Target:   $wormholeL1TokenRelayerAddress"
echo "Value:    0"
echo "Calldata: $calldata2b"

# Step 3: Treasury.disableToken(lpTokenAddress)
echo ""
echo "${green}Step 3: Treasury.disableToken() - disable LP token in Treasury${reset}"
calldata3=$(cast calldata "disableToken(address)" $lpTokenAddress)
echo "Target:   $treasuryAddress"
echo "Value:    0"
echo "Calldata: $calldata3"

# Step 4a: OLAS approve Celo L1 Standard Bridge
echo ""
echo "${green}Step 4a: OLAS approve() - approve Celo L1 Standard Bridge${reset}"
calldata4a=$(cast calldata "approve(address,uint256)" $celoL1StandardBridgeProxyAddress $OLAS_AMOUNT)
echo "Target:   $olasAddress"
echo "Value:    0"
echo "Calldata: $calldata4a"

# Step 4b: Bridge OLAS to Celo via L1 Standard Bridge
# depositERC20To(address _l1Token, address _l2Token, address _to, uint256 _amount, uint32 _minGasLimit, bytes _extraData)
echo ""
echo "${green}Step 4b: depositERC20To() - bridge OLAS to Celo${reset}"
minGasLimit=300000
calldata4b=$(cast calldata "depositERC20To(address,address,address,uint256,uint32,bytes)" $olasAddress $celoOLASAddress $bridgeMediatorAddress $OLAS_AMOUNT $minGasLimit "0x")
echo "Target:   $celoL1StandardBridgeProxyAddress"
echo "Value:    0"
echo "Calldata: $calldata4b"

# Step 5: Migrate old CeloTargetDispenserL2 via CrossDomainMessenger
# The old dispenser on Celo must be paused first, then migrated to bridgeMediator.
# This requires sending a cross-chain message from L1 through the CDMProxy -> OptimismMessenger.
echo ""
echo "${green}Step 5: Migrate old CeloTargetDispenserL2 via CrossDomainMessenger${reset}"

# Celo L1 CrossDomainMessenger proxy address
celoL1CDMProxyAddress=$(jq -r '.celoL1CrossDomainMessengerProxyAddress' $globalsStaking)

# Old Celo target dispenser on Celo L2
oldDispenserAddress="0xb4096d181C08DDF75f1A63918cCa0d1023C4e6C7"

echo "CDM Proxy:           $celoL1CDMProxyAddress"
echo "Old Dispenser (L2):  $oldDispenserAddress"
echo "Migrate to:          $bridgeMediatorAddress"

# Encode L2 calls: pause() and migrate(bridgeMediatorAddress)
pauseCalldata=$(cast calldata "pause()")
migrateCalldata=$(cast calldata "migrate(address)" $bridgeMediatorAddress)

# Build solidityPack for each L2 call:
# format: abi.encodePacked(address target, uint96 value, uint32 dataLength, bytes data)
addrHex=$(echo $oldDispenserAddress | sed 's/0x//')
valueHex="000000000000000000000000"  # uint96 = 0

# Pack pause() call
pauseDataHex=$(echo $pauseCalldata | sed 's/0x//')
pauseLenHex=$(printf "%08x" $((${#pauseDataHex} / 2)))

# Pack migrate() call
migrateDataHex=$(echo $migrateCalldata | sed 's/0x//')
migrateLenHex=$(printf "%08x" $((${#migrateDataHex} / 2)))

# Concatenate both packed calls
packedData="0x${addrHex}${valueHex}${pauseLenHex}${pauseDataHex}${addrHex}${valueHex}${migrateLenHex}${migrateDataHex}"

# Wrap in processMessageFromSource(bytes) for the OptimismMessenger on Celo
messengerPayload=$(cast calldata "processMessageFromSource(bytes)" $packedData)

# Wrap in sendMessage(address, bytes, uint32) for the CDMProxy on mainnet
cdmMinGasLimit=2000000
calldata5=$(cast calldata "sendMessage(address,bytes,uint32)" $bridgeMediatorAddress $messengerPayload $cdmMinGasLimit)
echo "Target:   $celoL1CDMProxyAddress"
echo "Value:    0"
echo "Calldata: $calldata5"

# Summary
echo ""
echo "${green}=== Proposal Summary ===${reset}"
echo ""
echo "targets = [$treasuryAddress, $lpTokenAddress, $wormholeL1TokenRelayerAddress, $treasuryAddress, $olasAddress, $celoL1StandardBridgeProxyAddress, $celoL1CDMProxyAddress]"
echo "values  = [0, 0, 0, 0, 0, 0, 0]"
echo "calldatas = [$calldata1, $calldata2a, $calldata2b, $calldata3, $calldata4a, $calldata4b, $calldata5]"
echo "description = \"Transfer bridged LP tokens and OLAS from Treasury to Celo bridge mediator, disable LP token, and migrate old Celo target dispenser\""
