// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LiquidityManagerCore} from "./LiquidityManagerCore.sol";

/// @dev Expected token addresses do not match provided ones.
/// @param provided Provided token addresses.
/// @param expected Expected token addresses.
error WrongTokenAddresses(address[] provided, address[] expected);

/// @title Liquidity Manager Source Base - Shared base for POL withdrawal mixins
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @dev Common base for the source-side withdrawal mixins (Uniswap V2, Balancer). The withdrawal itself carries
///      no price oracle: source-pool manipulation is gated in `convertToV3`, which cross-checks the ratio of the
///      removed tokens against the gate-verified V3 slot0 price (bounded by `maxSlippage`). A proportional
///      removal returns the pool's token ratio, so a manipulated source pool produces a ratio far from the V3
///      price and is rejected there; the removal passes zero per-token floors to the router/vault accordingly.
abstract contract LiquidityManagerSourceBase is LiquidityManagerCore {}
