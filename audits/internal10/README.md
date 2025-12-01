# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `3b21f24ca7832b37780c509251cec589a675c2a3` or `tag: v1.4.2-pre-internal-audit`<br> 

## Objectives
The audit focused on contracts related to BuyBackBurner*.sol in this repo.

### Storage and proxy
New contracts not affected Tokenomics storage. 

### Testing and coverage
Testing must be done through forge fork testing  <br>
https://getfoundry.sh/forge/reference/coverage.html <br>

### Security issues.
#### Notes. Fixing comments/name param
```
    /// @param fee Fee tier.
    function checkPoolPrices(address token0, address token1, address uniV3PositionManager, uint24 fee) external view {
    =>
    int24 feeTierOrTickSpacing
```
[]

#### Notes. Missing check?
```
        // Check for value underflow
        if (tickSpacing < 0) {
            revert Underflow(tickSpacing, 0);
        }
         return ICLFactory(factory).getPool(tokens[0], tokens[1], tickSpacing);
```
[]

#### Notes. Discuss linking options 
```
It is necessary to somehow more clearly comment on the fact that the code associated with the balancer is tightly tied to the code slipstream (aero/velo):
CL code:
    /// @dev Performs swap for OLAS on V3 DEX.
    function _performSwap(address token, uint256 tokenAmount, int24 tickSpacing)
        internal
        virtual
        override
        returns (uint256 olasAmount)
    {
        IERC20(token).approve(routerV3, tokenAmount);

        IRouterV3.ExactInputSingleParams memory params = IRouterV3.ExactInputSingleParams({
            tokenIn: token,
            tokenOut: olas,
            tickSpacing: tickSpacing,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tokenAmount,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        // Swap tokens
        olasAmount = IRouterV3(routerV3).exactInputSingle(params);
    }
Uniswapv3 code:
        /// @dev Performs swap for OLAS on V3 DEX.
        function _performSwap(address token, uint256 tokenAmount, int24 feeTier)
        internal
        virtual
        override
        returns (uint256 olasAmount)
    {
        IERC20(token).approve(routerV3, tokenAmount);

        IRouterV3.ExactInputSingleParams memory params = IRouterV3.ExactInputSingleParams({
            tokenIn: token,
            tokenOut: olas,
            fee: uint24(feeTier),
            recipient: address(this),
            amountIn: tokenAmount,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        // Swap tokens
        olasAmount = IRouterV3(routerV3).exactInputSingle(params);
    }
It is possible to explicitly specify the type DEX?
function buyBack(address token, uint256 tokenAmount, int24 feeTierOrTickSpacing, uint8 typeDEX) external virtual { 
if typeDEX == CL:
            IRouterV3.ExactInputSingleParams memory params = IRouterV3.ExactInputSingleParams({
            tokenIn: token,
            tokenOut: olas,
            tickSpacing: tickSpacing,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tokenAmount,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });
else:
     IRouterV3.ExactInputSingleParams memory params = IRouterV3.ExactInputSingleParams({
            tokenIn: token,
            tokenOut: olas,
            fee: uint24(feeTier),
            recipient: address(this),
            amountIn: tokenAmount,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });
```
[]