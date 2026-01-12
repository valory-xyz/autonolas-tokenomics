# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `180f6340c6abdfecda07de7e4d1607c4cd8ca979` or `tag: v1.4.2-pre-internal-audit`<br> 

## Objectives
The audit focused on contracts related to BuyBackBurner*.sol in this repo.

### Storage and proxy
New contracts not affected Tokenomics storage. 

### Testing and coverage
Testing must be done through forge fork testing  <br>
https://getfoundry.sh/forge/reference/coverage.html <br>

### Security issues.
### Medium. emit TokenTransferred vs IERC20(olas).transfer
```
Typo in replace
-        emit TokenTransferred(bridge2Burner, tokenAmount);              
+        emit TokenTransferred(bridge2Burner, secondTokenAmount);

Issue: in IERC20(olas).transfer(bridge2Burner, olasAmount); // olasAmount -> bridge2Burner
emit TokenTransferred(bridge2Burner, secondTokenAmount); // secondTokenAmount (?) -> bridge2Burner
function buyBack(address secondToken, uint256 secondTokenAmount, int24 feeTierOrTickSpacing) external virtual {
        ... 
        // Transfer OLAS to bridge2Burner contract
        IERC20(olas).transfer(bridge2Burner, olasAmount);

        emit TokenTransferred(bridge2Burner, secondTokenAmount);
```
[]

### Medium. updateOraclePrice(address poolOracle) by any poolOracle
```
Now the function has become:
function updateOraclePrice(address poolOracle) external {
    bool success = IOracle(poolOracle).updatePrice();
    require(success, "Oracle price update failed");
    emit OraclePriceUpdated(poolOracle, msg.sender);
}
The problem is not that someone will “update the price” (this was a public function before), but that now the contract makes an external call to an arbitrary address passed by the user.
Check poolOracle == mapV2Oracles[<someSecondToken>] ?
```
[]

### Medium/Low/Notices. Double check logic in BuyBackBurnerBalancer
```
Now: 
function _performSwap(address secondToken, uint256 secondTokenAmount, address poolOracle) internal virtual override returns (uint256 olasAmount) {
        // Get balancer vault address
        address balVault = IOracle(poolOracle).balancerVault();

        // Get balancer pool Id
        bytes32 balPoolId = IOracle(poolOracle).balancerPoolId();
vs
    // Balancer vault address
    address public balancerVault;
    // Balancer pool Id
    bytes32 public balancerPoolId;

So now everything depends on poolOracle. Please, double check.
```
[]

### Low. commented address public oracle; as unused
```
address public oracle;
By proxy design we can't remove variable from storage layout. Please, comment it as unused.
```
[]

### Low. IOracle interface name conflict
```
Potential IOracle interface name conflict (compile/type confusion)

A local interface has been added to BuyBackBurnerBalancer.sol:

interface IOracle {
function balancerVault() external view returns (address);
function balancerPoolId() external view returns (bytes32);
}

However, BuyBackBurner.sol already uses IOracle(...) with methods like validatePrice(), getPrice(), and updatePrice() (judging by the calls in the patch).
```
[]