#!/bin/bash

# Upgrades the LiquidityManagerProxy to a freshly-deployed LiquidityManager* implementation by calling
# changeImplementation(address) on the proxy. The proxy owner is the Autonolas deployer EOA (ownership was
# deliberately left with the deployer while POL is not operational), so this is a plain single-signer
# cast send — NOT a Timelock/DAO proposal.
#
# Prerequisite: deploy the new implementation first (deploy_02_liquidity_manager_univ2univ3.sh /
# deploy_02_liquidity_manager_balancer_slipstream.sh) and write its address into `liquidityManagerAddress` in the
# globals file. The proxy address is read from `liquidityManagerProxyAddress`.
#
# IMPORTANT ordering: the fail-closed price guard means the first convertToV3 reverts on a brand-new /
# quiet pool. Perform this upgrade BEFORE seeding any POL, then follow docs/liquidity_migration_runbook.md
# (pre-warm the pool) before the first seed.

# Check if $1 is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <network>"
  echo "Example: $0 eth_mainnet"
  exit 1
fi

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
useLedger=$(jq -r '.useLedger' $globals)
derivationPath=$(jq -r '.derivationPath' $globals)
chainId=$(jq -r '.chainId' $globals)
networkURL=$(jq -r '.networkURL' $globals)

liquidityManagerAddress=$(jq -r '.liquidityManagerAddress' $globals)
liquidityManagerProxyAddress=$(jq -r '.liquidityManagerProxyAddress' $globals)

# Guard against a misconfigured globals file — changeImplementation(0x0/null) would brick the proxy
if [ -z "$liquidityManagerAddress" ] || [ "$liquidityManagerAddress" == "null" ] \
   || [ "$liquidityManagerAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! liquidityManagerAddress is empty/zero in $globals — deploy the new implementation first${reset}"
  exit 1
fi
if [ -z "$liquidityManagerProxyAddress" ] || [ "$liquidityManagerProxyAddress" == "null" ] \
   || [ "$liquidityManagerProxyAddress" == "0x0000000000000000000000000000000000000000" ]; then
  echo "${red}!!! liquidityManagerProxyAddress is empty/zero in $globals${reset}"
  exit 1
fi

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

# Get deployer based on the ledger flag
if [ "$useLedger" == "true" ]; then
  walletArgs="-l --mnemonic-derivation-path $derivationPath"
  deployer=$(cast wallet address $walletArgs)
else
  echo "Using PRIVATE_KEY: ${PRIVATE_KEY:0:6}..."
  walletArgs="--private-key $PRIVATE_KEY"
  deployer=$(cast wallet address $walletArgs)
fi

castSendHeader="cast send --rpc-url $networkURL$API_KEY $walletArgs"

echo "${green}Change LiquidityManager implementation in its proxy${reset}"
castArgs="$liquidityManagerProxyAddress changeImplementation(address) $liquidityManagerAddress"
echo $castArgs
castCmd="$castSendHeader $castArgs"
result=$($castCmd)
echo "$result" | grep "status"

# Assert the tx succeeded — a reverted changeImplementation would otherwise print a status line and look done
txStatus=$(echo "$result" | grep -iE '^status' | grep -oiE '1 \(success\)|0 \(failed\)')
if [ -z "$txStatus" ] || [[ "$txStatus" == 0* ]]; then
  echo "${red}!!! changeImplementation transaction did not succeed${reset}"
  exit 1
fi

# Post-condition: read back the implementation slot and confirm the swap actually landed. The proxy stores the
# implementation at keccak256("PROXY_LIQUIDITY_MANAGER"). This is the only safety net for a single-signer upgrade.
implSlot="0xf7d1f641b01c7d29322d281367bfc337651cbfb5a9b1c387d2132d8792d212cd"
storedRaw=$(cast storage $liquidityManagerProxyAddress $implSlot --rpc-url $networkURL$API_KEY)
storedImpl="0x${storedRaw: -40}"
echo "  implementation slot -> $storedImpl (must be $liquidityManagerAddress)"
if [ "$(echo $storedImpl | tr '[:upper:]' '[:lower:]')" != "$(echo $liquidityManagerAddress | tr '[:upper:]' '[:lower:]')" ]; then
  echo "${red}!!! Implementation slot does not match liquidityManagerAddress — the upgrade did not land${reset}"
  exit 1
fi
# Variant guard: confirm the deployed impl matches globals on BOTH axes the four leaves (UniV2UniV3 /
# BalancerSlipstream / BalancerUniV3 / UniV2UniV3Bridge) vary on — SOURCE DEX and BURN MODE. They share one
# `liquidityManagerAddress` key and changeImplementation accepts any address by convention, so a wrong
# deploy_02_* lands a wrong-variant impl the slot read-back above cannot catch (it only proves the proxy
# points where globals said).
routerV2Address=$(jq -r '.routerV2Address // empty' $globals)
balancerVaultAddress=$(jq -r '.balancerVaultAddress // empty' $globals)
bridge2BurnerAddress=$(jq -r '.bridge2BurnerAddress // empty' $globals)
zero="0x0000000000000000000000000000000000000000"

# (1) SOURCE DEX: read a source-distinguishing immutable via the proxy and assert it matches globals. Does NOT
#     distinguish a Slipstream vs UniV3 target (both Balancer-source, identical getter sets — genuinely unclosable).
if [ -n "$routerV2Address" ] && [ "$routerV2Address" != "$zero" ]; then
  onchain=$(cast call $liquidityManagerProxyAddress "routerV2()(address)" --rpc-url $networkURL$API_KEY 2>/dev/null)
  echo "  source variant -> UniV2 (routerV2 $onchain, expected $routerV2Address)"
  if [ "$(echo $onchain | tr '[:upper:]' '[:lower:]')" != "$(echo $routerV2Address | tr '[:upper:]' '[:lower:]')" ]; then
    echo "${red}!!! Deployed impl routerV2 != globals routerV2Address — wrong LM variant for this chain${reset}"
    exit 1
  fi
elif [ -n "$balancerVaultAddress" ] && [ "$balancerVaultAddress" != "$zero" ]; then
  onchain=$(cast call $liquidityManagerProxyAddress "balancerVault()(address)" --rpc-url $networkURL$API_KEY 2>/dev/null)
  echo "  source variant -> Balancer (balancerVault $onchain, expected $balancerVaultAddress)"
  if [ "$(echo $onchain | tr '[:upper:]' '[:lower:]')" != "$(echo $balancerVaultAddress | tr '[:upper:]' '[:lower:]')" ]; then
    echo "${red}!!! Deployed impl balancerVault != globals balancerVaultAddress — wrong LM variant for this chain${reset}"
    exit 1
  fi
else
  # Single-signer EOA path, no proposal review: an unset source key is the case to STOP on, not skip.
  echo "${red}!!! Cannot determine expected source variant (neither routerV2Address nor balancerVaultAddress set) — aborting${reset}"
  exit 1
fi

# (2) BURN MODE: source alone no longer pins the variant — LiquidityManagerUniV2UniV3 (L1 direct OLAS.burn) and
#     LiquidityManagerUniV2UniV3Bridge (L2 bridge burn) share the same UniV2 source getter. Only the bridge
#     variants expose bridge2Burner(); the L1-burn leaf does not. Assert against the globals so a wrong burn
#     mode (e.g. the L1-burn leaf on an L2) is caught here rather than at runtime on the first burn.
if [ -n "$bridge2BurnerAddress" ] && [ "$bridge2BurnerAddress" != "$zero" ]; then
  onchain=$(cast call $liquidityManagerProxyAddress "bridge2Burner()(address)" --rpc-url $networkURL$API_KEY 2>/dev/null)
  echo "  burn mode -> bridge (bridge2Burner $onchain, expected $bridge2BurnerAddress)"
  if [ "$(echo $onchain | tr '[:upper:]' '[:lower:]')" != "$(echo $bridge2BurnerAddress | tr '[:upper:]' '[:lower:]')" ]; then
    echo "${red}!!! Deployed impl bridge2Burner != globals bridge2BurnerAddress — wrong burn mode (expected an L2 bridge-burn variant)${reset}"
    exit 1
  fi
else
  # No bridge2BurnerAddress in globals -> expect an L1 direct-burn variant, which does NOT expose bridge2Burner().
  if cast call $liquidityManagerProxyAddress "bridge2Burner()(address)" --rpc-url $networkURL$API_KEY >/dev/null 2>&1; then
    echo "${red}!!! Deployed impl exposes bridge2Burner() but globals has no bridge2BurnerAddress — expected an L1 direct-burn variant${reset}"
    exit 1
  fi
  echo "  burn mode -> L1 direct (bridge2Burner() absent, as expected)"
fi

echo "${green}LiquidityManager implementation upgraded and verified${reset}"
