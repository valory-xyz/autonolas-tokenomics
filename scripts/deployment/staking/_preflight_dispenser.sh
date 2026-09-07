#!/bin/bash
# Shared preflight for every script that binds or registers against the L1 Dispenser.
#
# WHY THIS EXISTS. DefaultDepositProcessorL1.l1Dispenser is `immutable`, so a processor deployed against the
# wrong Dispenser can never be repaired — claims from the live one revert ManagerOnly. The trap is that
# deploy_07b_dispenser_proxy.sh writes `dispenserProxyAddress` into scripts/deployment/globals_<network>.json,
# a DIFFERENT file from the staking globals these scripts read, so a Dispenser proxy migration silently leaves
# the value here pointing at the retired contract.
#
# Expects in scope: $globals, $dispenserProxyAddress, $1 (network suffix), and the red/green/reset vars.
# Source it immediately after reading dispenserProxyAddress and before building any constructor args.

zeroAddress="0x0000000000000000000000000000000000000000"
if [ -z "$dispenserProxyAddress" ] || [ "$dispenserProxyAddress" == "null" ] \
   || [ "$dispenserProxyAddress" == "$zeroAddress" ]; then
  echo "${red}!!! dispenserProxyAddress is not set (or zero) in $globals${reset}"
  exit 1
fi

deploymentGlobals="$(dirname "$0")/../globals_${1}.json"
if [ ! -f "$deploymentGlobals" ]; then
  # Warn rather than fail: not every network has a deployment-side globals file, and failing here would
  # regress runs that work today. Silence would be the wrong shape for a guard against an unrecoverable
  # binding, so it is loud.
  echo "${red}!!! WARNING: cannot cross-check the Dispenser binding — $deploymentGlobals not found.${reset}"
  echo "${red}!!!          l1Dispenser is immutable. Confirm $dispenserProxyAddress is the live Dispenser${reset}"
  echo "${red}!!!          before continuing.${reset}"
else
  liveDispenser=$(jq -r '.dispenserProxyAddress // .dispenserAddress // empty' "$deploymentGlobals")
  if [ -z "$liveDispenser" ]; then
    echo "${red}!!! $deploymentGlobals has neither dispenserProxyAddress nor dispenserAddress${reset}"
    exit 1
  fi
  if [ "$(echo "$liveDispenser" | tr '[:upper:]' '[:lower:]')" \
     != "$(echo "$dispenserProxyAddress" | tr '[:upper:]' '[:lower:]')" ]; then
    echo "${red}!!! Dispenser binding mismatch — refusing to bind to a stale address${reset}"
    echo "${red}    $globals            dispenserProxyAddress = $dispenserProxyAddress${reset}"
    echo "${red}    $deploymentGlobals  says the live Dispenser is $liveDispenser${reset}"
    echo "${red}    Reconcile the two before deploying; l1Dispenser cannot be changed afterwards.${reset}"
    exit 1
  fi
  echo "${green}Dispenser binding cross-checked against $deploymentGlobals${reset}"
fi
