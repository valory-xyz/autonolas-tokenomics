# Dispenser cascade deployment record

Built from `main` with Forge 1.7.1 / solc 0.8.30 (optimizer 200, viaIR, Prague).
Deployer `0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E`. The Dispenser proxy is deployed
paused and owned by the deployer; manager/route configuration and ownership handover to
the Timelock are performed separately.

## L1 core (Ethereum)
| Contract | Address |
|---|---|
| Dispenser implementation | `0x6f44B0Ab54f0cD5854A21a9e71C78c4F7cDf28f7` |
| DispenserProxy (callable) | `0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D` |
| VoteWeighting (governance repo) | `0xe8748e2CE2a4621425499bd26Aa8EF95Cf0C0730` |

Proxy initialized `(treasury=0xa0DA53447C0f6C4987964d8463da7e6628B30f82, voteWeighting=0, maxNumClaimingEpochs=1, maxNumStakingTargets=10)`;
owner = deployer; paused = StakingIncentivesPaused; implementation locked (its own `initialize()`
reverts). VoteWeighting binds the proxy and reads veOLAS `0x7e01A500805f8A52Fad229b3015AD130A332B7b3`.

## Deposit processor (L1) + target dispenser (L2) pairs
Each deployed, audited before and after linking, and linked (L1 `l2TargetDispenser` set, L1 owner
cleared). Polygon also links the FxPortal `fxRootTunnel`/`fxChildTunnel` both ways.

| Chain | DepositProcessorL1 | TargetDispenserL2 |
|---|---|---|
| Ethereum | `0x0984f182eBC49149406Cc3D579686AA8080AEa32` | — |
| Arbitrum | `0xFBB25d10a2Cd2c28403F6edb1D25C27F7Da60656` | `0x820ca542d5876FDEf240584F6f3924852D527FED` |
| Gnosis | `0x307234E1eF3E493287C7914eeeBC946e6d5ea113` | `0x0F991957e0Eb075E55c31635df297D5c0a0774e2` |
| Optimism | `0x914DBe131641374cb84eDf24087893Fe12D880Ad` | `0x5050c577583D25Ff9C9492A39e8D1B94028ffA55` |
| Base | `0x4D3adDE29234E3431af001eb420d704a161103A3` | `0x6D8CbEbCAD7397c63347D44448147Db05E7d17B0` |
| Celo | `0x26c2527F6f8CdC75AaBE5d0E8379d62f25Fc8d49` | `0x6F121552765424f0B2331B541C0938480cA314Db` |
| Mode | `0xf1C564eA76A81f3dE1b4c53938B67C48104bc6cc` | `0x90b8E448cA219C01e1516D11Aa49442674855c94` |
| Polygon | `0x293f01CBDF7dA067334d6701Aa7f748d0E76fe49` | `0x3284f2Da76f4f7ac749Fd072c366Af688d76a8AD` |
| Robinhood | `0xCd4dDd34C7a5C3dA5E9361ceDC8b6fa04b40f22E` | `0x90b8E448cA219C01e1516D11Aa49442674855c94` |

## Remaining (separate steps, while the deployer owns the proxy, then handover)
`changeManagers` (set VoteWeighting) + processor-route registration + audit, then
`changeOwner(Timelock)` on the proxy and `changeOwner(bridgeMediator)` on each L2 dispenser. The
dispenser audit before those steps reports the expected pre-configuration differences.
