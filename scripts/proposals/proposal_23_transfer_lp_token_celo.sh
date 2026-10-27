#!/bin/bash
#
# Celo OLAS/CELO LP transfer and swap.
# Run with "lp" first. After the full LP transfer arrives on Celo, run with "fund".
# Funding requires EXPECTED_CELO_LP_AMOUNT in native Celo LP base units, accounting
# for bridge decimal conversion. Verify against the executed LP transfer, not a dust balance.
# Re-run the funding pre-flight immediately before execution; generation is not an on-chain guard.
#
# PRE-FLIGHT — read the target pair's reserves before submitting, and again if this reverts.
#
# The target OLAS/WCELO pair is created lazily and anyone may create and seed it first. LPSwapCelo guards a
# pre-existing pair whose reserves are *skewed*, by deriving minimum amounts from the TWAP-protected
# removal — but a pair seeded on ONE SIDE ONLY is neither empty nor quotable, so the router reverts inside
# UniswapV2Library.quote ("INSUFFICIENT_LIQUIDITY") before those minimums are ever consulted. The guard is
# bypassed rather than triggered, which is why the revert looks unrelated to slippage.
#
# Nothing is lost when this happens: the transaction is atomic, so the source LP removal rolls back. But the
# pair keeps its state, so every retry fails identically until it is repaired.
#
#   Check:  cast call <OLAS/WCELO pair> "getReserves()(uint112,uint112,uint32)" --rpc-url <celo>
#   Repair: if exactly one reserve is zero, send dust of the missing token to the pair, call sync(), retry.
#           Both are permissionless, so this needs no privileged key.
#
# See docs/Vulnerabilities_list_tokenomics.md entry 37.
#

stage=${1:-}
if [ "$stage" != "lp" ] && [ "$stage" != "fund" ]; then
  echo "Usage: $0 lp|fund"
  exit 1
fi

red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)

# Globals files
globalsMainnet="scripts/deployment/globals_mainnet.json"
globalsStaking="scripts/deployment/staking/globals_mainnet.json"
globalsCelo="scripts/deployment/staking/celo/globals_celo_mainnet.json"
globalsCeloUtils="scripts/deployment/utils/globals_celo_mainnet.json"

for f in $globalsMainnet $globalsStaking $globalsCelo $globalsCeloUtils; do
  if [ ! -f "$f" ]; then
    echo "${red}!!! $f is not found${reset}"
    exit 1
  fi
done

# Check OLAS_AMOUNT env variable
if [ "$stage" == "fund" ] && [ -z "$OLAS_AMOUNT" ]; then
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

# Bridge mediator on Celo (recipient of the LPSwapCelo *outputs*, and migrate() target below)
bridgeMediatorAddress=$(jq -r '.bridgeMediatorAddress' $globalsCelo)

# LPSwapCelo on Celo — recipient of the bridged LP and the OLAS pre-funding.
# swapLiquidity() reads both from its OWN balance (IToken(...).balanceOf(address(this))), so the
# inputs must land on this contract. It then sends the re-added liquidity and any dust on to
# BRIDGE_MEDIATOR itself. Bridging the inputs to the mediator instead would strand the migration
# until governance forwarded them here in a second proposal.
# Read from the utils globals, which is where deploy_05_lp_swap_celo.sh records the address
# (it writes to "$(dirname "$0")/globals_<network>.json"); the staking globals above never gets it.
lpSwapCeloAddress=$(jq -r '.lpSwapCeloAddress' $globalsCeloUtils)
if [ -z "$lpSwapCeloAddress" ] || [ "$lpSwapCeloAddress" == "null" ]; then
  echo "${red}lpSwapCeloAddress is not set in $globalsCeloUtils — deploy LPSwapCelo first (scripts/deployment/utils/deploy_05_lp_swap_celo.sh celo_mainnet)${reset}"
  exit 1
fi

# Bridged LP token address
lpTokenAddress="0xC085F31E4ca659fF8A17042dDB26f1dcA2fBdAB4"

# RPC URL
networkURL=$(jq -r '.networkURL' $globalsMainnet)

echo "${green}=== Celo liquidity migration proposal: $stage ===${reset}"
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
echo "LPSwapCelo:          $lpSwapCeloAddress"
echo "Wormhole Chain ID:   $celoWormholeL2TargetChainId"
echo ""

if [ "$stage" == "lp" ]; then
# Step 0: Fetch LP token balance of Treasury
echo "${green}Fetching LP token balance of Treasury...${reset}"
if ! lpBalance=$(cast call --rpc-url ${networkURL}${ALCHEMY_API_KEY_MAINNET} $lpTokenAddress "balanceOf(address)(uint256)" $treasuryAddress); then
  echo "${red}Failed to read Treasury LP balance${reset}"
  exit 1
fi
# cast annotates a decoded uint as "N [1.23eK]"; keep only the integer before it reaches cast calldata.
lpBalance=${lpBalance%% *}
echo "LP token balance: $lpBalance"

if [[ ! "$lpBalance" =~ ^[1-9][0-9]*$ ]]; then
  echo "${red}LP token balance is zero or unreadable, nothing to transfer${reset}"
  exit 1
fi

# Recommended funding floor: the bridged amount truncated to Wormhole's 8-decimal precision (the bridge
# drops dust below 1e10 wei). Pass this as EXPECTED_CELO_LP_AMOUNT to the fund stage rather than a free
# value, so a native-LP donation cannot satisfy the balance check with a too-small expected amount.
# Truncate via string ops: 1e18-scale values overflow 64-bit bash arithmetic.
if [ ${#lpBalance} -gt 10 ]; then
  expectedCeloLp="${lpBalance:0:${#lpBalance}-10}0000000000"
else
  expectedCeloLp=0
fi

# Convert the LPSwapCelo address to bytes32 for the Wormhole recipient
recipientBytes32=$(cast --to-bytes32 $lpSwapCeloAddress)

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

# Do not report success unless every calldata blob was actually produced (no `set -e` in this script).
for cd in "$calldata1" "$calldata2a" "$calldata2b" "$calldata3"; do
  if [[ ! "$cd" =~ ^0x[0-9a-fA-F]+$ ]]; then
    echo "${red}Calldata generation failed; not emitting a success result${reset}"
    exit 1
  fi
done

echo "targets = [$treasuryAddress, $lpTokenAddress, $wormholeL1TokenRelayerAddress, $treasuryAddress]"
echo "values  = [0, 0, 0, 0]"
echo "calldatas = [$calldata1, $calldata2a, $calldata2b, $calldata3]"
echo 'description = "Transfer LP tokens to the Celo liquidity migration helper and disable the Treasury LP token"'
echo "Wait for full LP arrival before generating the separate funding proposal."
echo "Recommended EXPECTED_CELO_LP_AMOUNT for the fund stage (bridged amount truncated to 8 decimals): $expectedCeloLp"
exit 0
fi

# Funding is a separate proposal, generated only after verifying the native LP balance on Celo.
if [[ ! "$EXPECTED_CELO_LP_AMOUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "EXPECTED_CELO_LP_AMOUNT must be a positive integer in native Celo LP base units."
  exit 1
fi
celoNetworkURL=$(jq -r '.networkURL' "$globalsCeloUtils")
celoLpTokenAddress="0x2976Fa805141b467BCBc6334a69AffF4D914d96A"
if ! arrivedLp=$(cast call --rpc-url "$celoNetworkURL" "$celoLpTokenAddress" "balanceOf(address)(uint256)" "$lpSwapCeloAddress"); then
  echo "Cannot verify LP arrival on Celo; refusing to generate funding calldata."
  exit 1
fi
# cast may append a scientific-notation annotation to large uint256 values.
arrivedLp=${arrivedLp%% *}
if [[ ! "$arrivedLp" =~ ^[0-9]+$ ]]; then
  echo "Invalid Celo LP balance; refusing to generate funding calldata."
  exit 1
fi
# Compare decimal strings without overflowing shell integer arithmetic.
if [[ ${#arrivedLp} -lt ${#EXPECTED_CELO_LP_AMOUNT} ]] ||
   { [[ ${#arrivedLp} -eq ${#EXPECTED_CELO_LP_AMOUNT} ]] && [[ "$arrivedLp" < "$EXPECTED_CELO_LP_AMOUNT" ]]; }; then
  echo "Celo LP balance $arrivedLp is below expected amount $EXPECTED_CELO_LP_AMOUNT."
  exit 1
fi
echo "Verified Celo LP balance: $arrivedLp (expected at least $EXPECTED_CELO_LP_AMOUNT)."

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
calldata4b=$(cast calldata "depositERC20To(address,address,address,uint256,uint32,bytes)" $olasAddress $celoOLASAddress $lpSwapCeloAddress $OLAS_AMOUNT $minGasLimit "0x")
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
echo "targets = [$olasAddress, $celoL1StandardBridgeProxyAddress, $celoL1CDMProxyAddress]"
echo "values  = [0, 0, 0]"
echo "calldatas = [$calldata4a, $calldata4b, $calldata5]"
echo "description = \"Fund the Celo liquidity migration helper after verified LP arrival and migrate the old Celo target dispenser\""
