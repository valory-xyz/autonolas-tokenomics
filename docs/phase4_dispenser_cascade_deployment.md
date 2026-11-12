# Phase-4 Dispenser cascade — new-stack deployment (O4)

Deployed the replacement Dispenser cascade **in parallel to the live one**, built from `main`
with Forge 1.7.1 / solc 0.8.30 (optimizer 200, viaIR, Prague). The new Dispenser proxy is
**paused and EOA-owned**; the live cascade (`0x5650300f` + the 2024 contracts) is untouched until
the governance cutover. Deployer `0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E`.

## L1 core (Ethereum)
| Contract | Address |
|---|---|
| Dispenser implementation | `0x6f44B0Ab54f0cD5854A21a9e71C78c4F7cDf28f7` |
| DispenserProxy (callable) | `0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D` |
| VoteWeighting (governance repo) | `0xe8748e2CE2a4621425499bd26Aa8EF95Cf0C0730` |

Proxy initialized `(treasury=0xa0DA53447C0f6C4987964d8463da7e6628B30f82, voteWeighting=0, maxNumClaimingEpochs=1, maxNumStakingTargets=10)`,
owner = deployer, paused = StakingIncentivesPaused. Implementation locked (own `initialize()` reverts).
VoteWeighting binds the proxy and reads veOLAS `0x7e01A500805f8A52Fad229b3015AD130A332B7b3`.

## Deposit processor (L1) + target dispenser (L2) pairs
Each deployed, audited (before/after link), and linked (L1 `l2TargetDispenser` set, L1 owner cleared);
Polygon also sets the FxPortal `fxRootTunnel`/`fxChildTunnel` both ways. Every L2 dispenser carries the
`migratedTo`/`forward` fix.

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

## Not yet done (post-deploy, EOA-owned)
`changeManagers` (wire VoteWeighting) + `set_deposit_processors` (register the 9 routes) + audit, then
`changeOwner(Timelock)` on the proxy and `changeOwner(mediator)` on each L2 dispenser. The dispenser
audit before these steps reports the documented transitional diffs (owner, VW=0, paused, routes=0,
Tokenomics/Treasury still on old dispenser).
