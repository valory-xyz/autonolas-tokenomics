# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `8a814d05f154a29d14a21b966b8081b9b91faeb4` or `tag: v1.4.1-pre-internal-audit`<br> 

## Objectives
The audit focused on contracts related to Bridge2Burner/BuyBackBurner in this repo.

### Storage and proxy
New contracts not affected Tokenomics storage. 

### Testing and coverage
Testing must be done through forge fork testing  <br>
https://getfoundry.sh/forge/reference/coverage.html <br>

### Security issues.
#### Issue
#### High/Notes. Why 2 steps algo?
```
Current design:
Bridge2Burner.relayToL1Burner() for every chain
BuyBackBurner.bridge2Burn() + address Bridge2Burner for every chain

user -> BuyBackBurner.bridge2Burn() -> transfer OLAS -> Bridge2Burner
user -> Bridge2Burner.relayToL1Burner() -> IBridge(l2TokenRelayer).relayTokens -> transfer OLAS -> l2TokenRelayer

Why not just included code of Bridge2Burner inside BuyBackBurner?
user -> BuyBackBurner.relayToL1Burner() -> IBridge(l2TokenRelayer).relayTokens -> transfer OLAS -> l2TokenRelayer
```
[]

#### Low/Notes. Why payable?
```
function relayToL1Burner(bytes memory bridgePayload) external payable virtual
with
if (msg.value > 0) {
    revert ZeroValueOnly();
} in all implementation.
Why is this function declared as payable?
```
[]

#### Medium. Improved logic for rare observe revert?
```
        // Check if the pool has sufficient observation history
        (uint32 oldestTimestamp, , , ) = IUniswapV3(pool).observations(observationIndex);
        if (oldestTimestamp + SECONDS_AGO < block.timestamp) {
            return;
        }

        // Check TWAP or historical data
        uint256 twapPrice = _getTwapFromOracle(pool)
vs new logic in pol contract:
        // Check if the pool has sufficient observation history
        (uint32 oldestTimestamp, , , ) = IUniswapV3(pool).observations(observationIndex);
        if (oldestTimestamp + SECONDS_AGO < block.timestamp) {
            return;
        }

uint256 twapPrice = _getTwapFromOracle(pool) -> (int56[] memory tickCumulatives, ) = IUniswapV3(pool).observe(secondsAgos) -> revert
Should we improve as stated in the `LiqudityManagerCore` contract, given the potential for revert in `observe`?       
```
[]

### Medium/Notes. Not BBB for UniV3.
```
uint256[] memory amounts = IUniswap(router).swapExactTokensForTokens()
Should we make (planned?) a separate contract that works with Uniswapv3 (BBBUniswapV3)?
```
[]