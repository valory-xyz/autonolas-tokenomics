# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Autonolas Tokenomics — Solidity smart contracts for the Autonolas protocol's tokenomics system. Manages OLAS token rewards, bonding (LP tokens → OLAS), staking incentive distribution across 8+ chains, and protocol-owned liquidity. Inspired by OlympusDAO concepts. The Tokenomics contract is proxy-upgradeable.

## Build & Test Commands

### Prerequisites
- Node.js >= 18, Yarn
- Foundry (`forge`, `cast`)
- Clone with `git clone --recursive` (has submodules in `lib/`)

### Install
```bash
yarn install
```

### Compile
```bash
yarn compile          # Hardhat (includes Uniswap library hash adjustment steps)
forge build           # Foundry
```

The `yarn compile` script adjusts Uniswap pair init code hashes before and after compilation (see `scripts/uni-adjust/`).

### Test — Hardhat
```bash
yarn test                                                    # All Hardhat tests
npx hardhat test test/Tokenomics.js                          # Single Hardhat test file
```

### Test — Forge Unit Tests (no fork required)
```bash
forge test --mc Depository -vvv
forge test --mc Dispenser -vvv
forge test --mc Treasury -vvv
forge test --mc UniswapPriceOracleConstructorTest -vvv
forge test --mc UniswapPriceOracleGetPriceTest -vvv
forge test --mc UniswapPriceOracleUpdatePriceTest -vvv
forge test --mc UniswapPriceOracleGetTWAPTest -vvv
forge test --mc BalancerPriceOracleConstructorTest -vvv
forge test --mc BalancerPriceOracleGetPriceTest -vvv
forge test --mc BalancerPriceOracleUpdatePriceTest -vvv
forge test --mc BalancerPriceOracleGetTWAPTest -vvv
forge test --mc LPSwapCeloConstructorTest -vvv
forge test --mc LPSwapCeloSwapTest -vvv
forge test --mc LPSwapCeloSlippageTest -vvv
```

### Test — Forge Fork Tests (require RPC node URL for the target chain)
```bash
forge test -f $FORK_ETH_NODE_URL --mc LiquidityManagerETH -vvv       # ETH mainnet
forge test -f $FORK_ETH_NODE_URL --mc UniswapPriceOracleETH -vvv
forge test -f $FORK_ETH_NODE_URL --mc BuyBackBurnerUniswapETH -vvv
forge test -f $FORK_BASE_NODE_URL --mc LiquidityManagerBase -vvv      # Base
forge test -f $FORK_BASE_NODE_URL --mc BalancerPriceOracleBase -vvv
forge test -f $FORK_BASE_NODE_URL --mc BuyBackBurnerBalancerBase -vvv
forge test -f $FORK_POLYGON_NODE_URL --mc BuyBackBurnerBalancerPolygon -vvv   # Polygon
forge test -f $FORK_ARBITRUM_NODE_URL --mc BuyBackBurnerBalancerArbitrum -vvv  # Arbitrum
forge test -f https://forno.celo.org --mc LPSwapCeloForkTest -vvv             # Celo
```

### Coverage
```bash
yarn coverage         # Hardhat coverage (sets COVERAGE=1 env var, enables viaIR)
```

### Linting
```bash
./node_modules/.bin/eslint . --ext .js,.jsx,.ts,.tsx         # JS/TS linting
./node_modules/.bin/solhint contracts/interfaces/*.sol contracts/*.sol contracts/test/*.sol   # Solidity linting
```

### Static Audit (on-chain verification)
```bash
node scripts/audit_chains/audit_contracts_setup.js
```

## Architecture

### Core Contract System

Four interconnected contracts form the tokenomics engine:

- **Tokenomics** (`contracts/Tokenomics.sol`) — Central engine managing epochs, reward calculations for component/agent owners, bond discount factors, and staking emissions. Deployed behind `TokenomicsProxy` for upgradeability. Inherits constants from `TokenomicsConstants.sol`.
- **Treasury** (`contracts/Treasury.sol`) — Holds OLAS and ETH. Manages token enablement, transfers to Depository/Dispenser, and rebalancing based on tokenomics epoch rewards. Pausable.
- **Depository** (`contracts/Depository.sol`) — Bond depository where users deposit LP tokens and receive OLAS after a vesting period. Uses `GenericBondCalculator` for pricing.
- **Dispenser** (`contracts/Dispenser.sol`) — Distributes staking incentives from Tokenomics. Orchestrates cross-chain distribution via chain-specific L1 deposit processors.

### Cross-Chain Staking (`contracts/staking/`)

L1→L2 incentive distribution uses a paired processor/dispenser pattern per chain:

- **L1 side**: `DefaultDepositProcessorL1` base → chain-specific implementations (`ArbitrumDepositProcessorL1`, `GnosisDepositProcessorL1`, `OptimismDepositProcessorL1`, `PolygonDepositProcessorL1`, `WormholeDepositProcessorL1`)
- **L2 side**: `DefaultTargetDispenserL2` base → chain-specific implementations (same chain prefixes)
- **L1-only**: `EthereumDepositProcessor` for Ethereum mainnet staking

### Protocol Owned Liquidity (`contracts/pol/`)

- `LiquidityManagerCore` / `LiquidityManagerETH` / `LiquidityManagerOptimism` — Manage protocol-owned liquidity positions (Uniswap V3). Proxy-upgradeable via `LiquidityManagerProxy`.

### Utilities (`contracts/utils/`)

- `BuyBackBurner*` — Buy-back-and-burn mechanisms (Uniswap and Balancer variants) with proxy support
- `Bridge2Burner*` — Bridge tokens then burn (Gnosis, Optimism, Polygon, Arbitrum variants)
- `LPSwapCelo` — Swaps whOLAS-CELO liquidity to OLAS-CELO liquidity on Celo (Ubeswap V2), with TWAP-based slippage protection via `UniswapPriceOracle`, then bridges leftover OLAS via OP-stack L2StandardBridge and whOLAS via Wormhole Token Bridge to L1 Timelock

### Price Oracles (`contracts/oracles/`)

- `UniswapPriceOracle` / `BalancerPriceOracle` — On-chain price feeds for OLAS

## Solidity Configuration

- **Primary compiler**: 0.8.30, optimizer 20 runs, EVM target Prague, viaIR in coverage mode
- **Secondary compilers**: 0.5.16, 0.6.6 (Uniswap V2 compatibility)
- **Foundry**: optimizer 100 runs, viaIR always on, Prague EVM
- Struct fields are carefully packed into 256-bit slots (documented in comments) for gas efficiency
- Custom errors with parameters (not string reverts)
- CEI (Checks-Effects-Interactions) pattern enforced; 8-bit reentrancy locks for storage packing

## Celo Fork Testing

WCELO (`0x471EcE3750Da237f93B8E339c536989b8978a438`) is Celo's native GoldToken proxy, which uses Celo-specific precompiles for balance management. These precompiles are **not available in forge fork mode**, causing `transfer`/`transferFrom` to silently fail. The workaround in fork tests is to `vm.etch` a standard ERC20 (e.g., `MockERC20`) over the WCELO address and restore the pair's balance via `deal()`. See `test/LPSwapCelo.t.sol` `LPSwapCeloForkBaseSetup.setUp()` for the pattern.

The Wormhole Token Bridge truncates amounts to 8 decimal places, so up to ~1e10 wei dust of whOLAS may remain after bridging. Assertions should use `assertLt(..., 1e10)` instead of `assertEq(..., 0)`.

## Cross-Chain Governance Proposals

For L2 calls from L1 governance (OP-stack chains like Celo, Optimism, Base, Mode), the pattern is:
1. Encode each L2 call using `solidityPack(["address", "uint96", "uint32", "bytes"], [target, value, dataLength, calldata])`
2. Concatenate multiple packed calls
3. Wrap in `processMessageFromSource(bytes)` for the OptimismMessenger (bridge mediator on L2)
4. Wrap in `sendMessage(address, bytes, uint32)` for the L1 CrossDomainMessenger proxy

See `scripts/proposals/proposal_23_migrate_l2_dispenser_celo.js` (JS/ethers) and `scripts/proposals/proposal_23_transfer_lp_token_celo.sh` (bash/cast) for examples.

## Deployment

Sequential deployment scripts in `scripts/deployment/` (steps 01–17). Contract ABIs for deployment are in `abis/`. Deployed addresses and configuration are in `docs/configuration.json`.

## Network Support

Mainnets: Ethereum, Polygon, Gnosis, Arbitrum, Optimism, Base, Celo, Mode
Testnets: Sepolia, Polygon Amoy, Chiado, Arbitrum Sepolia, Optimism Sepolia, Base Sepolia, Celo Alfajores, Mode Sepolia

## Key Dependencies

- `@prb/math` (=4.0.2) — Fixed-point arithmetic
- `@uniswap/v2-core`, `@uniswap/v2-periphery` — LP token calculations
- `wormhole-solidity-sdk` — Celo cross-chain bridging
- `@arbitrum/sdk` — Arbitrum bridge integration
- `@balancer-labs/sdk` — Balancer protocol integration
- Submodules in `lib/`: forge-std, fx-portal (Polygon), zuniswapv2
