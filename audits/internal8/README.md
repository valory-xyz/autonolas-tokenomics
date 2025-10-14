# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `c0969e8a4fc6fd77727841402d38cc7c1d536721` or `tag: v1.4.0-pre-internal-audit`<br> 

## Objectives
The audit focused on contracts related to POL Manager in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal8/analysis/contracts) 

### Storage and proxy
New contracts not affected Tokenomics storage. 

### Testing and coverage
Testing must be done through forge fork testing (Please test not only the fresh ("good") pool, but also the cases with the price at the border MAX/MIN tick). <br>
https://getfoundry.sh/forge/reference/coverage.html <br>

### Security issues.
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal8/analysis/slither_full.txt) <br>

#### Issue
#### High. constructor vs initialize for implementation
```
Issue for proxy-implementation design.
constructor(
        address _olas,
        address _treasury,
        address _positionManagerV3,
        address _neighborhoodScanner,
        uint16 _observationCardinality,
        uint16 _maxSlippage
    ) => 
    address public owner; // storage in implementation context
    owner = msg.sender;
Same for:
- LiquidityManagerOptimism is LiquidityManagerCore
- LiquidityManagerETH is LiquidityManagerCore

+
    // Max slippage for pool operations (in BPS, bound by 10_000)
    uint16 public maxSlippage; -> immutable? // not storage
```
[]

#### High/Medium. mapPoolAddressPositionIds[pool] and workflow
```
There are many cases where a position is reset during contract execution.
But there's no clear understanding of what to do next, because the position is assigned only once in convertToV3.
changeRanges required mapPoolAddressPositionIds[pool] != 0

for example:
decreaseLiquidity or transferPositionId
mapPoolAddressPositionIds[pool] = 0
-> ????
because impossible set mapPoolAddressPositionIds[pool] = new.
```
[x] Fixed

#### High. Incorrect logic _increaseLiquidity
```
Not quite correct logic, which looks correct and probably works in non-boundary cases.
Fix:
function _increaseLiquidity(
    address pool,
    uint256 positionId,
    uint256[] memory inputAmounts
) internal returns (uint128 liquidity, uint256[] memory amountsIn) {
    // 1) Current price
    (uint160 sqrtPriceX96, ) = _getPriceAndObservationIndexFromSlot0(pool);

    // 2) Current ticks
    {
        uint128 Lpos; // Lpos non eq Ladd
        (, , , , , ticks[0], ticks[1], Lpos, , , , ) =
            IPositionManagerV3(positionManagerV3).positions(positionId);
    }

    // 3) border
    uint160 sqrtA = TickMath.getSqrtRatioAtTick(ticks[0]);
    uint160 sqrtB = TickMath.getSqrtRatioAtTick(ticks[1]);

    // 4) Ladd! not Lpos, can't compare Lpos vs Ladd!
    uint128 Ladd = LiquidityAmounts.getLiquidityForAmounts(
        sqrtPriceX96, sqrtA, sqrtB,
        inputAmounts[0], inputAmounts[1]
    );
    require(Ladd > 0, "NoLiquidityToAdd");

    // 5) Used by Ladd (Critical)
    (uint256 use0, uint256 use1) =
        LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtA, sqrtB, Ladd);

    // 6) Min based on user, not by input! Critical
    uint256 amount0Min = use0 * (MAX_BPS - maxSlippage) / MAX_BPS;
    uint256 amount1Min = use1 * (MAX_BPS - maxSlippage) / MAX_BPS;

    // 7) call increase
    (liquidity, amountsIn[0], amountsIn[1]) =
        IPositionManagerV3(positionManagerV3).increaseLiquidity(
            IPositionManagerV3.IncreaseLiquidityParams({
                tokenId: positionId,
                amount0Desired: inputAmounts[0],
                amount1Desired: inputAmounts[1],
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                deadline: block.timestamp + DEADLINE
            })
        );
}
```
[x] Fixed

### High. Issue check/logic/execution olasBurnRate in convertToV3
```
1.
        // Recalculate amounts for adding position liquidity depending on conversion rate
        if (olasBurnRate < MAX_BPS) { // 0 < 10_000. => maybe burn if olasBurnRate > 0 ???
            // Initial token management: burn OLAS, transfer another token
            amounts = _manageUtilityAmounts(tokens, olasBurnRate, true);
        }

You must either prohibit the burning of all OLAS/transfer all non-OLAS or be sure to add dust liquidity. 
Not sure, designed for extreme cases:
olasBurnRate = or ~= MAX_BPS.
```
[x] Fixed

### High. Unsafe value0InToken1
```
Possible overflow in 
        unchecked {
            uint256 num = uint256(sqrtP) * uint256(sqrtP);           // !!! possible overflow 160+160 > 256
            return FullMath.mulDiv(amount, num, 1 << 192);
        }

Fix:
function value0InToken1(uint256 amount, uint160 sqrtP) internal pure returns (uint256) {
    if (amount == 0) return 0;
    // amount * sqrtP / 2^96
    uint256 tmp = FullMath.mulDiv(amount, sqrtP, FixedPoint96.Q96);
    // (amount * sqrtP / 2^96) * sqrtP / 2^96  == amount * (sqrtP^2) / 2^192
    return FullMath.mulDiv(tmp, sqrtP, FixedPoint96.Q96);
}
```
[x] Fixed

### Medium/Notes. The problem is in the design (increaseLiquidity vs decreaseLiquidity)
```
function convertToV3
(liquidity, amounts) = _increaseLiquidity(v3Pool, positionId, amounts);
increaseLiquidity must be a separate symmetric function.
The workflow of mapPoolAddressPositionIds[v3Pool] (positionId) must be described separately and explicitly as critical issue of contract.
```
[x] Noted, but if we need to convert more V2 tokens, this path must remain as positionId already exists

#### Medium/Low. Token like USDT as token1.
```
function _manageUtilityAmounts(address[] memory tokens, uint32 conversionRate, bool burnOrTransfer)
        internal returns (uint256[] memory updatedBalances)
         // Transfer to Treasury
        if (tokenAmount > 0) {
            IToken(tokens[1]).transfer(treasury, tokenAmount);
        }
We haven't encountered such a case, but it will be a problem for example for USDT.
interface IUSDT {
    function transfer(address, uint256) external;
}
```
[x] Fixed

#### Medium?/Notes. Rewrite variable without usage
```
function _adjustTicksAndMintPosition()
(optimizedTicks, liquidity, amountsIn) =
            INeighborhoodScanner(neighborhoodScanner).optimizeLiquidityAmounts(centerSqrtPriceX96, initTicks,
                tickSpacing, inputAmounts, scan);
.. liqudity not used and rewrited again
(positionId, liquidity, amountsIn) =
            _mintV3(tokens, amountsIn, amountsMin, optimizedTicks, feeTierOrTickSpacing, centerSqrtPriceX96);
```
[x] Fixed

#### Medium. Double check code with utilization
```
    I'm not sure that this check is really necessary in actual code. Please, double check scanNeighborhood/utilization logic
    function _scanNeighborhood()
        uint160[] memory sqrtAB = new uint160[](2);
        sqrtAB[0] = TickMath.getSqrtRatioAtTick(ticks[0]);
        sqrtAB[1] = TickMath.getSqrtRatioAtTick(ticks[1]);

        uint256[] memory utilization1e18BeforeAfter = new uint256[](2);
        uint256[] memory amountsMin = new uint256[](2);

        // Compute expected amounts for increase (TWAP) -> slippage guards
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtP, sqrtAB[0], sqrtAB[1], amounts[0], amounts[1]);
        // Check for zero value
        if (liquidity > 0) {
            (amountsMin[0], amountsMin[1]) =
                LiquidityAmounts.getAmountsForLiquidity(sqrtP, sqrtAB[0], sqrtAB[1], liquidity);

            utilization1e18BeforeAfter[0] = utilization1e18(amountsMin, amounts, sqrtP);
        }

```
[x] Fixed

#### Low?/Notes. Double check logic _manageUtilityAmounts
```
    function decreaseLiquidity(address[] memory tokens, int24 feeTierOrTickSpacing, uint16 decreaseRate, uint16 olasBurnRate)
        external returns (uint256 positionId, uint256[] memory amounts)
        // Transfer OLAS and another token to treasury
        if (olasBurnRate > 0) {
            _manageUtilityAmounts(tokens, olasBurnRate, true); // Logically, it meant that Olas tokens should be touched.
        }

        // Manage collected amounts - transfer both to treasury
        _manageUtilityAmounts(tokens, MAX_BPS, false);

1. if olasBurnRate > 0
        _manageUtilityAmounts(address[] memory tokens, uint32 conversionRate, bool burnOrTransfer)
        amounts[0] = IToken(tokens[0]).balanceOf(address(this));
        amounts[1] = IToken(tokens[1]).balanceOf(address(this));

        // Adjust amounts
        if (conversionRate < MAX_BPS) {
            updatedBalances[0] = amounts[0];
            updatedBalances[1] = amounts[1];

            amounts[0] = (amounts[0] * conversionRate) / MAX_BPS;
            amounts[1] = (amounts[1] * conversionRate) / MAX_BPS;

            updatedBalances[0] -= amounts[0];
            updatedBalances[1] -= amounts[1];
        }
        => amounts[1] = (amounts[1] * conversionRate) / MAX_BPS;
        tokenAmount = amounts[1];
        // Transfer to Treasury
        if (tokenAmount > 0) {
            IToken(tokens[1]).transfer(treasury, tokenAmount); // transfer "olasBurnRate" token1 share to treasury.
        }
2. _manageUtilityAmounts(tokens, MAX_BPS, false); => will take the remaining token1, but this will make two transfers instead of one.
In general, this will not lead to problems, but only because the remainder will be taken based on the balances.
```
[x] Noted

### Low. Unnamed revert()
```
autonolas-tokenomics$ grep -r "revert()" contracts/pol/*
contracts/pol/LiquidityManagerCore.sol:            revert();
contracts/pol/LiquidityManagerCore.sol:            revert();
contracts/pol/LiquidityManagerETH.sol:            revert();
contracts/pol/LiquidityManagerETH.sol:            revert();
contracts/pol/LiquidityManagerETH.sol:            revert();
contracts/pol/LiquidityManagerETH.sol:            revert();
contracts/pol/LiquidityManagerOptimism.sol:            revert();
contracts/pol/LiquidityManagerOptimism.sol:            revert();
contracts/pol/NeighborhoodScanner.sol:            revert();
```
[x] Fixed

### Low. A lot missing NatSpec
```
Example:
function _mintV3(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory amountsMin,
        int24[] memory ticks,
        int24 feeTierOrTickSpacing,
        uint160 centerSqrtPriceX96
    ) internal virtual returns (uint256 positionId, uint128 liquidity, uint256[] memory amountsOut);
```
[]

### Low. External fucntion with no events
```
The absence of events makes subgraph monitoring/using impossible
- convertToV3
- collectFees
- changeRanges
- decreaseLiquidity
```
[x] Fixed

### Low. Remove variable NEAR_STEPS = SAFETY_STEPS
```
// Steps near to tick boundaries
    int24 internal constant NEAR_STEPS = SAFETY_STEPS;
```
[x] Fixed

### Notes. decreaseLiquidity function burns olasBurnRate% of (fee + decreaseLiquidity)
```
It should be clear at the specification level that the burn rate applies to all "received" (from pool) olas, and not just to fee.
To avoid incorrect conclusions for DAO
```
[]



