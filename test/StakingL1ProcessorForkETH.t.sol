// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Dispenser} from "../contracts/Dispenser.sol";
import {DispenserProxy} from "../contracts/proxies/DispenserProxy.sol";
import {EthereumDepositProcessor} from "../contracts/staking/EthereumDepositProcessor.sol";

/// @dev Ethereum-mainnet fork test of the migration's L1 leg: the NEW proxy-based Dispenser wired to a
///      freshly-deployed, REAL `EthereumDepositProcessor` (not the in-test stub used by StakingClaimForkETH).
///
///      What this uniquely proves for the redeploy (runbook §4 "hard immutable couplings" / §5 in-scope
///      processors / §6 Phase 2 & 4):
///        - `EthereumDepositProcessor.dispenser` is `immutable`, so a new Dispenser address forces a new
///          processor. This deploys the processor with `dispenser = newDispenserProxy` and shows the
///          `msg.sender == dispenser` gate authenticates the new proxy (and rejects anyone else) — the exact
///          coupling that makes the processor part of the cascade.
///        - the money-path is real end-to-end on L1: claim -> live Treasury mints real OLAS -> Dispenser
///          forwards it to the new processor -> processor `approve` + `IStaking.deposit` moves it into the
///          staking target, with the epoch cap refunded to live Tokenomics inflation and the processor-level
///          emissions cap refunded to the Timelock.
///
///      Only the registries layer below the processor is stubbed (staking factory + staking instance) — the
///      same philosophy as StakingClaimForkETH stubbing Vote Weighting / the L2 processor: every Tokenomics /
///      Treasury / OLAS movement is against live mainnet state.
///
///      The contract name avoids the "Dispenser"/"Treasury"/"Depository" substrings so CI's fork-less
///      `forge test --mc Dispenser|Treasury|Depository` allowlist does not pick it up and run it without a fork.
///
///      Run: forge test -f $FORK_ETH_NODE_URL --mc StakingL1ProcessorForkETH -vvv

interface ITokenomicsForkL1 {
    function epochLen() external view returns (uint256);
    function epochCounter() external view returns (uint32);
    function dispenser() external view returns (address);
    function checkpoint() external;
    function changeManagers(address treasury, address depository, address dispenser) external;
    function mapEpochStakingPoints(uint256 epoch) external view
        returns (uint96 stakingIncentive, uint96 maxStakingIncentive, uint16 minStakingWeight, uint8 stakingFraction);
}

interface ITreasuryForkL1 {
    function changeManagers(address tokenomics, address depository, address dispenser) external;
}

interface IOLASForkL1 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @dev Stand-in Vote Weighting (mirrors StakingClaimForkETH): decouples nominee weight from the total sum so
///      the epoch cap can be driven deterministically; mirrors the dispenser coupling (addNominee callback,
///      checkpointNominee, nomineeRelativeWeight).
contract ForkVoteWeightingL1 {
    struct Nominee {
        bytes32 account;
        uint256 chainId;
    }

    address public immutable dispenser;
    mapping(bytes32 => bool) public exists;
    mapping(bytes32 => uint256) public relativeWeights;
    mapping(bytes32 => uint256) public weightSums;

    constructor(address _dispenser) {
        dispenser = _dispenser;
    }

    function _hash(bytes32 account, uint256 chainId) internal pure returns (bytes32) {
        return keccak256(abi.encode(Nominee(account, chainId)));
    }

    function addNominee(address account, uint256 chainId) external {
        bytes32 nomineeHash = _hash(bytes32(uint256(uint160(account))), chainId);
        exists[nomineeHash] = true;
        Dispenser(dispenser).addNominee(nomineeHash);
    }

    function setWeights(address account, uint256 chainId, uint256 relativeWeight, uint256 weightSum) external {
        bytes32 nomineeHash = _hash(bytes32(uint256(uint160(account))), chainId);
        relativeWeights[nomineeHash] = relativeWeight;
        weightSums[nomineeHash] = weightSum;
    }

    function checkpointNominee(bytes32 account, uint256 chainId) external view {
        if (!exists[_hash(account, chainId)]) {
            revert();
        }
    }

    function nomineeRelativeWeight(bytes32 account, uint256 chainId, uint256) external view returns (uint256, uint256) {
        bytes32 nomineeHash = _hash(account, chainId);
        return (relativeWeights[nomineeHash], weightSums[nomineeHash]);
    }
}

/// @dev Stand-in staking proxy factory: the emissions limit the processor caps a deposit at. Deterministic so
///      both the "under cap" (full deposit) and "over cap" (processor refunds to Timelock) branches are testable.
contract MockStakingFactoryL1 {
    uint256 public emissionsLimit;

    function setEmissionsLimit(uint256 limit) external {
        emissionsLimit = limit;
    }

    function verifyInstanceAndGetEmissionsAmount(address) external view returns (uint256) {
        return emissionsLimit;
    }
}

/// @dev Stand-in staking instance: pulls the approved OLAS in on deposit, exactly as a real staking contract does.
contract MockStakingInstanceL1 {
    address public immutable olas;
    uint256 public deposited;

    constructor(address _olas) {
        olas = _olas;
    }

    function deposit(uint256 amount) external {
        (bool success, ) = olas.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount));
        require(success, "transferFrom failed");
        deposited += amount;
    }
}

contract StakingL1ProcessorForkETH is Test {
    // Ethereum mainnet addresses
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant TOKENOMICS = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    address internal constant TREASURY = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    // Dispenser implementation immutable
    bytes32 internal constant RETAINER = bytes32(uint256(0xdEaD));

    // Ethereum L1 staking rides on chain Id == 1 in production (EthereumDepositProcessor is the L1-only leg)
    uint256 internal constant CHAIN_ID = 1;

    Dispenser internal dispenser;
    ForkVoteWeightingL1 internal vw;
    EthereumDepositProcessor internal processor;
    MockStakingFactoryL1 internal stakingFactory;
    MockStakingInstanceL1 internal stakingInstance;
    uint256 internal epochLen;

    function setUp() public {
        epochLen = ITokenomicsForkL1(TOKENOMICS).epochLen();

        // New Dispenser implementation against the LIVE Tokenomics proxy, then the proxy (Vote Weighting is a
        // placeholder set after the proxy exists, under the initial pause).
        Dispenser dispenserImpl = new Dispenser(OLAS, TOKENOMICS, RETAINER);
        bytes memory initData = abi.encodeWithSelector(dispenserImpl.initialize.selector,
            TREASURY, address(this), uint256(1), uint256(10));
        DispenserProxy dispenserProxy = new DispenserProxy(address(dispenserImpl), initData);
        dispenser = Dispenser(address(dispenserProxy));

        // Stand-in Vote Weighting over the new proxy; swap it in while paused (#8 guard)
        vw = new ForkVoteWeightingL1(address(dispenser));
        dispenser.changeManagers(address(0), address(vw));

        // Registries layer below the processor (stubbed): factory returns the emissions cap, instance pulls OLAS
        stakingFactory = new MockStakingFactoryL1();
        stakingInstance = new MockStakingInstanceL1(OLAS);

        // The REAL L1 deposit processor, deployed against the NEW dispenser proxy (the immutable coupling)
        processor = new EthereumDepositProcessor(OLAS, address(dispenser), address(stakingFactory), TIMELOCK);

        address[] memory processors = new address[](1);
        processors[0] = address(processor);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = CHAIN_ID;
        dispenser.setDepositProcessorChainIds(processors, chainIds);

        // Migration wiring: repoint the LIVE Treasury and Tokenomics at the new dispenser (Timelock-owned)
        vm.startPrank(TIMELOCK);
        ITreasuryForkL1(TREASURY).changeManagers(address(0), address(0), address(dispenser));
        ITokenomicsForkL1(TOKENOMICS).changeManagers(address(0), address(0), address(dispenser));
        vm.stopPrank();

        // Go live and register the staking instance as a fresh nominee (records the claim cursor)
        dispenser.setPauseState(Dispenser.Pause.Unpaused);
        vw.addNominee(address(stakingInstance), CHAIN_ID);
        vw.setWeights(address(stakingInstance), CHAIN_ID, 1e18, 1e30);
    }

    function _targetBytes32() internal view returns (bytes32) {
        return bytes32(uint256(uint160(address(stakingInstance))));
    }

    function _stakingIncentiveOf(uint256 epoch) internal view returns (uint256 amount) {
        (amount, , , ) = ITokenomicsForkL1(TOKENOMICS).mapEpochStakingPoints(epoch);
    }

    function _maxStakingIncentiveOf(uint256 epoch) internal view returns (uint256 amount) {
        (, amount, , ) = ITokenomicsForkL1(TOKENOMICS).mapEpochStakingPoints(epoch);
    }

    /// @dev Settles the current epoch on the live Tokenomics so it carries a staking incentive to claim.
    function _advanceEpoch() internal {
        vm.warp(block.timestamp + epochLen + 10);
        vm.roll(block.number + 1);
        ITokenomicsForkL1(TOKENOMICS).checkpoint();
    }

    /// @dev Returns the amount the Dispenser mints & forwards to the processor for the last settled epoch
    ///      (the epoch incentive capped by the per-epoch max).
    function _expectedForwarded() internal view returns (uint256 forwarded, uint256 epochReturn) {
        uint256 claimableEpoch = ITokenomicsForkL1(TOKENOMICS).epochCounter() - 1;
        uint256 epochIncentive = _stakingIncentiveOf(claimableEpoch);
        uint256 maxInc = _maxStakingIncentiveOf(claimableEpoch);
        require(epochIncentive > 0, "settled epoch must carry an incentive");
        forwarded = epochIncentive < maxInc ? epochIncentive : maxInc;
        epochReturn = epochIncentive - forwarded;
    }

    // -----------------------------------------------------------------------
    // The new-processor <-> new-dispenser coupling
    // -----------------------------------------------------------------------

    function test_processorBoundToNewDispenser_authGate() public {
        // The immutable that forces the processor redeploy points at the new proxy
        assertEq(processor.dispenser(), address(dispenser), "processor.dispenser == new proxy");

        // Only the wired dispenser can drive it
        vm.prank(address(0xBAD));
        vm.expectRevert();
        processor.sendMessage(address(stakingInstance), 1 ether, "", 0);
    }

    // -----------------------------------------------------------------------
    // Full distribution: live mint -> new processor -> real deposit (under the emissions cap)
    // -----------------------------------------------------------------------

    function test_claimThroughRealProcessor_depositsIntoTarget() public {
        _advanceEpoch();
        (uint256 forwarded, uint256 epochReturn) = _expectedForwarded();

        // Emissions cap comfortably above the forwarded amount -> the processor deposits all of it, no refund
        stakingFactory.setEmissionsLimit(forwarded + 1 ether);

        uint256 currentEpoch = ITokenomicsForkL1(TOKENOMICS).epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);
        uint256 supplyBefore = IOLASForkL1(OLAS).totalSupply();
        uint256 timelockBefore = IOLASForkL1(OLAS).balanceOf(TIMELOCK);

        dispenser.claimStakingIncentives(1, CHAIN_ID, _targetBytes32(), "");

        // Real OLAS was minted by the live Treasury and ended up staked in the target via the processor
        assertEq(IOLASForkL1(OLAS).totalSupply() - supplyBefore, forwarded, "totalSupply grew by the mint");
        assertEq(stakingInstance.deposited(), forwarded, "full forwarded amount deposited into the target");
        assertEq(IOLASForkL1(OLAS).balanceOf(address(processor)), 0, "processor holds no residual OLAS");
        assertEq(IOLASForkL1(OLAS).balanceOf(TIMELOCK), timelockBefore, "no processor-level refund under the cap");

        // The per-epoch cap remainder is refunded to the live staking inflation
        assertEq(_stakingIncentiveOf(currentEpoch) - potBefore, epochReturn, "capped remainder refunded to inflation");
    }

    // -----------------------------------------------------------------------
    // Processor-level emissions cap: excess above the target's limit refunds to the Timelock
    // -----------------------------------------------------------------------

    function test_claimThroughRealProcessor_emissionsCapRefundsToTimelock() public {
        _advanceEpoch();
        (uint256 forwarded, ) = _expectedForwarded();

        // Emissions cap below the forwarded amount -> the processor deposits the cap and refunds the excess
        uint256 limit = forwarded / 2;
        require(limit > 0, "limit must be positive");
        stakingFactory.setEmissionsLimit(limit);

        uint256 supplyBefore = IOLASForkL1(OLAS).totalSupply();
        uint256 timelockBefore = IOLASForkL1(OLAS).balanceOf(TIMELOCK);

        dispenser.claimStakingIncentives(1, CHAIN_ID, _targetBytes32(), "");

        // Same amount minted, but split: cap staked, remainder refunded to the DAO Timelock
        assertEq(IOLASForkL1(OLAS).totalSupply() - supplyBefore, forwarded, "totalSupply grew by the mint");
        assertEq(stakingInstance.deposited(), limit, "only the emissions cap deposited into the target");
        assertEq(IOLASForkL1(OLAS).balanceOf(TIMELOCK) - timelockBefore, forwarded - limit, "excess refunded to Timelock");
        assertEq(IOLASForkL1(OLAS).balanceOf(address(processor)), 0, "processor holds no residual OLAS");
    }
}
