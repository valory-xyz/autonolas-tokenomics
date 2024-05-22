# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `ae0cfff0aa6bcde59f1e9442777f3ab427b6d050` or `tag: v1.2.0-pre-internal-audit`<br> 

## Objectives
The audit focused on contracts related to PoAA Staking in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/contracts) 

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```
npm link sol2uml --only=production
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal4/analysis/storage
Generated png file audits/internal4/analysis/storage/Tokenomics.png
sol2uml storage contracts/ -f png -c Dispenser -o audits/internal4/analysis/storage          
Generated png file audits/internal4/analysis/storage/Dispenser.png
```
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/Tokenomics.png) <br>
[Dispenser-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/Dispenser.png) <br>
[storage_hardhat_test.md](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/storage_hardhat_test.md) <br>
current deployed: <br>
[Tokenomics-storage-current](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal2/analysis/storage/Tokenomics.png) <br>
The new slot allocation for Tokenomics (critical as proxy pattern) does not affect the previous one. 

### Security issues.
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/slither_full.txt) <br>

#### Issue
##### Dispenser
1. Bug. `olas` is never initialized, `maxNumStakingTargets` is never initialized  
```
contract Dispenser {
      address public immutable olas;
       /// @dev Dispenser constructor.
    /// @param _tokenomics Tokenomics address.
    /// @param _treasury Treasury address.
    /// @param _voteWeighting Vote Weighting address.
    constructor(address _tokenomics, address _treasury, address _voteWeighting) {}
```
[x] fixed

2. checking by possibility `epochAfterRemoved - 1` < 0 in revert message
```
contract Dispenser:
revert Overflow(firstClaimedEpoch, epochAfterRemoved - 1);
```
[x] fixed

3. checking transferAmounts > 0 before transfer
```
contract Dispenser:
in any IToken(olas).transfer(depositProcessor, transferAmounts[i]) or  IToken(olas).transfer(depositProcessor, transferAmount); check transferAmount > 0
```
[x] fixed

4. Double check calculateStakingIncentives. Let discussed.
```
Need to rewrite the code such that anybody is able to call the calculateStakingIncentives function, without a possibility to write into the storage to arbitrary caller.
```
[x] fixed

5. sync pause of Dispenser with pause of Treasury
```
The Treasury contract must be leading and if Treasury has set a pause, then it must be checked on Dispeser side and pause too.
```
[x] fixed

6. doublke check function retain() external
```
function looks like she doesn't actually do anything at the end.
        totalReturnAmount /= 1e18;
    /// action??? with totalReturnAmount
    }
```
[x] fixed

7. removeNominee issue around end-of-epoch. revert if `remove` near `end-of-epoch - 7days`. Let discussed.
[x] fixed

##### Other
1. Bug in polygon? Anybody after deploy contract can setup fxChildTunnel. Issue? + lacks a zero-check on
```
audits\internal4\analysis\contracts\PolygonDepositProcessorL1-flatten.sol
abstract contract FxBaseRootTunnel {
    using RLPReader for RLPReader.RLPItem;
    using Merkle for bytes32;
    using ExitPayloadReader for bytes;
    using ExitPayloadReader for ExitPayloadReader.ExitPayload;
    using ExitPayloadReader for ExitPayloadReader.Log;
    using ExitPayloadReader for ExitPayloadReader.LogTopics;
    using ExitPayloadReader for ExitPayloadReader.Receipt;

    // keccak256(MessageSent(bytes))
    bytes32 public constant SEND_MESSAGE_EVENT_SIG = 0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036;

    // state sender contract
    IFxStateSender public fxRoot;
    // root chain manager
    ICheckpointManager public checkpointManager;
    // child tunnel contract which receives and sends messages 
    address public fxChildTunnel;

    // storage to avoid duplicate exits
    mapping(bytes32 => bool) public processedExits;

    constructor(address _checkpointManager, address _fxRoot) {
        checkpointManager = ICheckpointManager(_checkpointManager);
        fxRoot = IFxStateSender(_fxRoot);
    }

    // set fxChildTunnel if not set already
    function setFxChildTunnel(address _fxChildTunnel) public {
        require(fxChildTunnel == address(0x0), "FxBaseRootTunnel: CHILD_TUNNEL_ALREADY_SET");
        fxChildTunnel = _fxChildTunnel;
    }
    ...

    same issue: 
    audits\internal4\analysis\contracts\PolygonTargetDispenserL2-flatten.sol
    abstract contract FxBaseChildTunnel is IFxMessageProcessor{
    // MessageTunnel on L1 will get data from this event
    event MessageSent(bytes message);

    // fx child
    address public fxChild;

    // fx root tunnel
    address public fxRootTunnel;

    constructor(address _fxChild) {
        fxChild = _fxChild;
    }

    // Sender must be fxRootTunnel in case of ERC20 tunnel
    modifier validateSender(address sender) {
        require(sender == fxRootTunnel, "FxBaseChildTunnel: INVALID_SENDER_FROM_ROOT");
        _;
    }

    // set fxRootTunnel if not set already
    function setFxRootTunnel(address _fxRootTunnel) external {
        require(fxRootTunnel == address(0x0), "FxBaseChildTunnel: ROOT_TUNNEL_ALREADY_SET");
        fxRootTunnel = _fxRootTunnel;
    }
```
[x] fixed

#### Low priority issue
1. does not emit an event
```
DefaultDepositProcessorL1.setL2TargetDispenser()
WormholeDepositProcessorL1.setL2TargetDispenser()
PolygonDepositProcessorL1.setL2TargetDispenser()
Dispenser.setPause()
Dispenser.changeStakingParams()
```
[x] fixed

2. abi.encodeWithSignature to abi.encodeCall
```
Example of more safe way:
        bytes memory data = abi.encodeCall(
            MyContract(target).foo.selector,
            abi.encode((uint256(10), uint256(20)))
        );
        (bool success, bytes memory result) = target.call(data);
ref: https://detectors.auditbase.com/abiencodecall-over-signature-solidity
```
[x] fixed

3. lacks a zero-check on
```
contract ArbitrumTargetDispenserL2 is DefaultTargetDispenserL2 {
    // Aliased L1 deposit processor address
    address public immutable l1AliasedDepositProcessor;

    /// @dev ArbitrumTargetDispenserL2 constructor.
    /// @notice _l1AliasedDepositProcessor must be correctly aliased from the address on L1.
    ///         Reference: https://docs.arbitrum.io/arbos/l1-to-l2-messaging#address-aliasing
    ///         Source: https://github.com/OffchainLabs/token-bridge-contracts/blob/b3894ecc8b6185b2d505c71c9a7851725f53df15/contracts/tokenbridge/libraries/AddressAliasHelper.sol#L21-L32
    /// @param _olas OLAS token address.
    /// @param _proxyFactory Service staking proxy factory address.
    /// @param _l2MessageRelayer L2 message relayer bridging contract address (ArbSys).
    /// @param _l1DepositProcessor L1 deposit processor address (NOT aliased).
    /// @param _l1SourceChainId L1 source chain Id.
    constructor(
        address _olas,
        address _proxyFactory,
        address _l2MessageRelayer,
        address _l1DepositProcessor,
        uint256 _l1SourceChainId
    )
        DefaultTargetDispenserL2(_olas, _proxyFactory, _l2MessageRelayer, _l1DepositProcessor, _l1SourceChainId)
    {
        // Get the l1AliasedDepositProcessor based on _l1DepositProcessor
        uint160 offset = uint160(0x1111000000000000000000000000000000001111);
        unchecked {
            l1AliasedDepositProcessor = address(uint160(_l1DepositProcessor) + offset);
        }
```
[x] already implemented in the DefaultTargetDispenserL2 constructor

4. Better add _lock for retain, Because it's impossible to write in CEI-forms 
```
Dispenser:
function retain() external {}
```
[x] fixed

5. Low probability overflow. Pay attention to all operation: a += b, type(a) => uint96
```
function refundFromStaking(uint256 amount) external {
        // Check for the dispenser access
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        uint256 eCounter = epochCounter;
        mapEpochStakingPoints[eCounter].stakingAmount += uint96(amount);
        emit StakingRefunded(eCounter, amount);
    }
to
    uint256 tmp = mapEpochStakingPoints[eCounter].stakingAmount;
    tmp += uint96(amount);
    if( tmp > type(uint96).max) {
        revert Overflow(eBond, type(uint96).max);
    }
```
[x] already implemented in a newer version

#### To Discussion
1. Mutex for _processData.
```
This is not an bug, but for greater security it makes sense to surround the code with a mutex.
function _processData(bytes memory data) internal {
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;
        ...
        _locked = 1;
}
```
[x] fixed

2. A lot of warnings - "ignores return value". 
```
TokenSender.transferTokens(address,uint256,uint16,address,bytes) (WormholeTargetDispenserL2-flatten.sol#1703-1727) ignores return value by IERC20(token).approve(address(tokenBridge),amount) (WormholeTargetDispenserL2-flatten.sol#1710)
TokenSender.sendTokenWithPayloadToEvm(uint16,address,bytes,uint256,uint256,address,uint256) (WormholeTargetDispenserL2-flatten.sol#1735-1761) ignores return value by (cost) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain,receiverValue,gasLimit) (WormholeTargetDispenserL2-flatten.sol#1747-1751)
TokenSender.sendTokenWithPayloadToEvm(uint16,address,bytes,uint256,uint256,address,uint256,uint16,address) (WormholeTargetDispenserL2-flatten.sol#1763-1793) ignores return value by (cost) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain,receiverValue,gasLimit) (WormholeTargetDispenserL2-flatten.sol#1777-1781)
TokenReceiver.receiveWormholeMessages(bytes,bytes[],bytes32,uint16,bytes32) (WormholeTargetDispenserL2-flatten.sol#1825-1879) ignores return value by tokenBridge.completeTransferWithPayload(additionalVaas[i]) (WormholeTargetDispenserL2-flatten.sol#1851)
DefaultTargetDispenserL2._processData(bytes) (WormholeTargetDispenserL2-flatten.sol#209-265) ignores return value by IToken(olas).approve(target,amount) (WormholeTargetDispenserL2-flatten.sol#245)
DefaultTargetDispenserL2.redeem(address,uint256,uint256) (WormholeTargetDispenserL2-flatten.sol#314-351) ignores return value by IToken(olas).approve(target,amount) (WormholeTargetDispenserL2-flatten.sol#338)
WormholeTargetDispenserL2._sendMessage(uint256,bytes) (WormholeTargetDispenserL2-flatten.sol#1975-2000) ignores return value by (cost) = IBridge(l2MessageRelayer).quoteEVMDeliveryPrice(uint16(l1SourceChainId),0,GAS_LIMIT) (WormholeTargetDispenserL2-flatten.sol#1988)
-
TokenReceiver.receiveWormholeMessages(bytes,bytes[],bytes32,uint16,bytes32) (WormholeDepositProcessorL1-flatten.sol#1671-1725) ignores return value by tokenBridge.completeTransferWithPayload(additionalVaas[i]) (WormholeDepositProcessorL1-flatten.sol#1697)
TokenSender.transferTokens(address,uint256,uint16,address,bytes) (WormholeDepositProcessorL1-flatten.sol#1549-1573) ignores return value by IERC20(token).approve(address(tokenBridge),amount) (WormholeDepositProcessorL1-flatten.sol#1556)
TokenSender.sendTokenWithPayloadToEvm(uint16,address,bytes,uint256,uint256,address,uint256) (WormholeDepositProcessorL1-flatten.sol#1581-1607) ignores return value by (cost) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain,receiverValue,gasLimit) (WormholeDepositProcessorL1-flatten.sol#1593-1597)
TokenSender.sendTokenWithPayloadToEvm(uint16,address,bytes,uint256,uint256,address,uint256,uint16,address) (WormholeDepositProcessorL1-flatten.sol#1609-1639) ignores return value by (cost) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain,receiverValue,gasLimit) (WormholeDepositProcessorL1-flatten.sol#1623-1627)
-
DefaultTargetDispenserL2._processData(bytes) (GnosisTargetDispenserL2-flatten.sol#209-265) ignores return value by IToken(olas).approve(target,amount) (GnosisTargetDispenserL2-flatten.sol#245)
DefaultTargetDispenserL2.redeem(address,uint256,uint256) (GnosisTargetDispenserL2-flatten.sol#314-351) ignores return value by IToken(olas).approve(target,amount) (GnosisTargetDispenserL2-flatten.sol#338)
-
GnosisDepositProcessorL1._sendMessage(address[],uint256[],bytes,uint256) (GnosisDepositProcessorL1-flatten.sol#349-392) ignores return value by IToken(olas).approve(l1TokenRelayer,transferAmount) (GnosisDepositProcessorL1-flatten.sol#363)
-
GnosisDepositProcessorL1._sendMessage(address[],uint256[],bytes,uint256) (GnosisDepositProcessorL1-flatten.sol#349-392) ignores return value by IToken(olas).approve(l1TokenRelayer,transferAmount) (GnosisDepositProcessorL1-flatten.sol#363)
-
EthereumDepositProcessor._deposit(address[],uint256[]) (EthereumDepositProcessor-flatten.sol#72-98) ignores return value by IToken(olas).approve(target,amount) (EthereumDepositProcessor-flatten.sol#91)
-
OptimismDepositProcessorL1._sendMessage(address[],uint256[],bytes,uint256) (OptimismDepositProcessorL1-flatten.sol#393-437) ignores return value by IToken(olas).approve(l1TokenRelayer,transferAmount) (OptimismDepositProcessorL1-flatten.sol#409)
-
DefaultTargetDispenserL2._processData(bytes) (OptimismTargetDispenserL2-flatten.sol#209-265) ignores return value by IToken(olas).approve(target,amount) (OptimismTargetDispenserL2-flatten.sol#245)
DefaultTargetDispenserL2.redeem(address,uint256,uint256) (OptimismTargetDispenserL2-flatten.sol#314-351) ignores return value by IToken(olas).approve(target,amount) (OptimismTargetDispenserL2-flatten.sol#338)
-
DefaultTargetDispenserL2._processData(bytes) (OptimismTargetDispenserL2-flatten.sol#209-265) ignores return value by IToken(olas).approve(target,amount) (OptimismTargetDispenserL2-flatten.sol#245)
DefaultTargetDispenserL2.redeem(address,uint256,uint256) (OptimismTargetDispenserL2-flatten.sol#314-351) ignores return value by IToken(olas).approve(target,amount) (OptimismTargetDispenserL2-flatten.sol#338)
-
ArbitrumDepositProcessorL1._sendMessage(address[],uint256[],bytes,uint256) (ArbitrumDepositProcessorL1-flatten.sol#417-485) ignores return value by IToken(olas).approve(l1ERC20Gateway,transferAmount) (ArbitrumDepositProcessorL1-flatten.sol#467)
ArbitrumDepositProcessorL1._sendMessage(address[],uint256[],bytes,uint256) (ArbitrumDepositProcessorL1-flatten.sol#417-485) ignores return value by IBridge(l1TokenRelayer).outboundTransferCustomRefund{value: cost[0]}(olas,refundAccount,l2TargetDispenser,transferAmount,TOKEN_GAS_LIMIT,gasPriceBid,submissionCostData) (ArbitrumDepositProcessorL1-flatten.sol#475-476)
-
Dispenser._distributeStakingIncentives(uint256,bytes32,uint256,bytes,uint256) (Dispenser-flatten.sol#379-401) ignores return value by IToken(olas).transfer(depositProcessor,transferAmount) (Dispenser-flatten.sol#390)
Dispenser._distributeStakingIncentivesBatch(uint256[],bytes32[][],uint256[][],bytes[],uint256[],uint256[]) (Dispenser-flatten.sol#410-464) ignores return value by IToken(olas).transfer(depositProcessor,transferAmounts[i]) (Dispenser-flatten.sol#423)
-
Dispenser.retain() (Dispenser-flatten.sol#669-699) ignores return value by (stakingWeight) = IVoteWeighting(voteWeighting).nomineeRelativeWeight(localRetainer,block.chainid,endTime) (Dispenser-flatten.sol#693-694)
Dispenser.claimStakingIncentives(uint256,uint256,bytes32,bytes) (Dispenser-flatten.sol#836-913) ignores return value by ITreasury(treasury).withdrawToAccount(address(this),0,transferAmount) (Dispenser-flatten.sol#898)
Dispenser.claimStakingIncentivesBatch(uint256,uint256[],bytes32[][],bytes[],uint256[]) (Dispenser-flatten.sol#924-1020) ignores return value by ITreasury(treasury).withdrawToAccount(address(this),0,totalAmounts[1]) (Dispenser-flatten.sol#1005)
-
PolygonDepositProcessorL1._sendMessage(address[],uint256[],bytes,uint256) (PolygonDepositProcessorL1-flatten.sol#1245-1272) ignores return value by IToken(olas).approve(predicate,transferAmount) (PolygonDepositProcessorL1-flatten.sol#1256)
-
DefaultTargetDispenserL2._processData(bytes) (PolygonTargetDispenserL2-flatten.sol#209-265) ignores return value by IToken(olas).approve(target,amount) (PolygonTargetDispenserL2-flatten.sol#245)
DefaultTargetDispenserL2.redeem(address,uint256,uint256) (PolygonTargetDispenserL2-flatten.sol#314-351) ignores return value by IToken(olas).approve(target,amount) (PolygonTargetDispenserL2-flatten.sol#338)
-
```
[x] noted

# Re-audit. 22.05.24

## Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `7f20035c543d553ed28a960152a3bae2878f374c` or `tag: v1.2.1-pre-internal-audit`<br>

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis2/contracts)

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```
npm link sol2uml --only=production
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal4/analysis2/storage
Generated png file audits/internal4/analysis2/storage/Tokenomics.png
```
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis2/storage/Tokenomics.png) <br>
Same as before (see above). No issue.

### Security issues.
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis2/slither_full.txt) <br>

#### Low issue
1. Re-calcualted retainerHash
```
    /// @dev Retains staking incentives according to the retainer address to return it back to the staking inflation.
    function retain() external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Go over epochs and retain funds to return back to the tokenomics
        bytes32 localRetainer = retainer;

        // Construct the nominee struct
        IVoteWeighting.Nominee memory nominee = IVoteWeighting.Nominee(localRetainer, block.chainid);
        // Get the nominee hash
        bytes32 nomineeHash = keccak256(abi.encode(nominee));

        but
            constructor(
        ...
        retainer = _retainer;
        retainerHash = keccak256(abi.encode(IVoteWeighting.Nominee(retainer, block.chainid)));

```
[x] fixed

2. Not overflow gasLimit.
```
        // Check the gas limit value
        if (gasLimitMessage < GAS_LIMIT) {
            gasLimitMessage = GAS_LIMIT;
        }
        Under EIP-1559 a maximum gas limit is 30 million gas. So, if gasLimitMessage > MAX_GAS_LIMIT gasLimitMessage = GAS_LIMIT;
```
[x] fixed

3. The old version remains.
```
autonolas-tokenomics$ grep -r "0.8.23" ./contracts/
./contracts/interfaces/IBridgeErrors.sol:pragma solidity ^0.8.23;
```
[x] fixed

4. Double checking comments
```
    Dispenser.sol
    // Checkpoint the vote weighting for the retainer on L1
```
[x] fixed

### To discussion. Not sure.
```
DefaultTargetDispenserL2.sol
    /// @dev Receives native network token.
    receive() external payable {
        emit FundsReceived(msg.sender, msg.value);
    }
    revert ofter migration?
    like:
    if(owner == address(0)) or _lock > 1 then revert()
```
[x] fixed


