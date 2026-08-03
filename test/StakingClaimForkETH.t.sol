// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Dispenser, Unpaused} from "../contracts/Dispenser.sol";
import {DispenserProxy} from "../contracts/proxies/DispenserProxy.sol";

/// @dev Ethereum-mainnet fork test of the proxy-based Dispenser claim path against the REAL deployed
///      Tokenomics proxy and Treasury (not freshly-deployed copies, not mocks).
///
///      What the fork uniquely exercises vs the in-test suites:
///        - the new Dispenser implementation + DispenserProxy plug into the LIVE Tokenomics proxy and
///          Treasury (real storage: real inflation-curve position, real staking fraction, real owner);
///        - the migration wiring (owner-gated Treasury/Tokenomics changeManagers repointing the dispenser)
///          runs against the real Timelock-owned contracts;
///        - the claim money-path mints REAL OLAS: claim -> Treasury.withdrawToAccount -> OLAS.mint ->
///          transfer to the deposit processor, with the return/withheld portions refunded to the real
///          Tokenomics staking inflation.
///
///      Vote Weighting (gauge voting is week-boundary / veOLAS-lock bound and infeasible to drive on a fork)
///      and the L2 deposit processor (pure L1->L2 bridge plumbing) are stand-ins so the weight and the
///      bridge decimals are deterministic inputs; every OLAS movement and inflation accounting is real.
///
///      The contract name intentionally avoids the "Dispenser"/"Treasury"/"Depository" substrings so the
///      CI `forge test --mc Dispenser` allowlist does not pick it up and run it without a fork.
///
///      Run: forge test -f $FORK_ETH_NODE_URL --mc StakingClaimForkETH -vvv

interface ITokenomicsFork {
    function owner() external view returns (address);
    function epochLen() external view returns (uint256);
    function epochCounter() external view returns (uint32);
    function dispenser() external view returns (address);
    function checkpoint() external;
    function changeManagers(address treasury, address depository, address dispenser) external;
    function mapEpochStakingPoints(uint256 epoch) external view
        returns (uint96 stakingIncentive, uint96 maxStakingIncentive, uint16 minStakingWeight, uint8 stakingFraction);
}

interface ITreasuryFork {
    function dispenser() external view returns (address);
    function changeManagers(address tokenomics, address depository, address dispenser) external;
    function paused() external view returns (uint8);
}

interface IOLASFork {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @dev Stand-in Vote Weighting: decouples the nominee relative weight from the total weight sum so both the
///      max-staking-incentive cap and the weight-sum cap can be driven deterministically. Mirrors the real
///      dispenser coupling (addNominee callback, checkpointNominee, nomineeRelativeWeight).
contract ForkVoteWeighting {
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

/// @dev Minimal L1 deposit processor: captures what the dispenser forwards to the bridge.
contract ForkDepositProcessor {
    uint256 public lastStakingIncentive;
    uint256 public lastTransferAmount;

    function getBridgingDecimals() external pure returns (uint256) {
        return 18;
    }

    function sendMessage(address, uint256 stakingIncentive, bytes memory, uint256 transferAmount) external payable {
        lastStakingIncentive = stakingIncentive;
        lastTransferAmount = transferAmount;
    }

    function updateHashMaintenance(bytes32) external {}
}

contract StakingClaimForkETH is Test {
    // Ethereum mainnet addresses
    address internal constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address internal constant TOKENOMICS = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    address internal constant TREASURY = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address internal constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    // Dispenser implementation immutable
    bytes32 internal constant RETAINER = bytes32(uint256(0xdEaD));

    // A non-L1 EVM chain Id for the staking target (must differ from block.chainid == 1)
    uint256 internal constant CHAIN_ID = 100;
    address internal constant STAKING_TARGET = address(0x57A6);

    Dispenser internal dispenser;
    ForkVoteWeighting internal vw;
    ForkDepositProcessor internal depositProcessor;
    uint256 internal epochLen;

    function setUp() public {
        epochLen = ITokenomicsFork(TOKENOMICS).epochLen();

        // Deploy the new Dispenser implementation against the LIVE Tokenomics proxy, then the proxy.
        // Vote Weighting is a placeholder here (set after the proxy exists, under the initial pause).
        Dispenser dispenserImpl = new Dispenser(OLAS, TOKENOMICS, RETAINER);
        bytes memory initData = abi.encodeWithSelector(dispenserImpl.initialize.selector,
            TREASURY, address(this), uint256(1), uint256(10));
        DispenserProxy dispenserProxy = new DispenserProxy(address(dispenserImpl), initData);
        dispenser = Dispenser(address(dispenserProxy));

        // Stand-in Vote Weighting over the live proxy; swap it in while staking incentives are paused (#8 guard)
        vw = new ForkVoteWeighting(address(dispenser));
        dispenser.changeManagers(address(0), address(vw));

        // Deposit processor for the L2 chain Id
        depositProcessor = new ForkDepositProcessor();
        address[] memory processors = new address[](1);
        processors[0] = address(depositProcessor);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = CHAIN_ID;
        dispenser.setDepositProcessorChainIds(processors, chainIds);

        // Migration wiring: repoint the LIVE Treasury and Tokenomics at the new dispenser (Timelock-owned)
        vm.startPrank(TIMELOCK);
        ITreasuryFork(TREASURY).changeManagers(address(0), address(0), address(dispenser));
        ITokenomicsFork(TOKENOMICS).changeManagers(address(0), address(0), address(dispenser));
        vm.stopPrank();

        // Go live and register a fresh nominee (records the claim cursor at the current epoch)
        dispenser.setPauseState(Dispenser.Pause.Unpaused);
        vw.addNominee(STAKING_TARGET, CHAIN_ID);
    }

    function _targetBytes32() internal pure returns (bytes32) {
        return bytes32(uint256(uint160(STAKING_TARGET)));
    }

    function _stakingIncentiveOf(uint256 epoch) internal view returns (uint256 amount) {
        (amount, , , ) = ITokenomicsFork(TOKENOMICS).mapEpochStakingPoints(epoch);
    }

    function _maxStakingIncentiveOf(uint256 epoch) internal view returns (uint256 amount) {
        (, amount, , ) = ITokenomicsFork(TOKENOMICS).mapEpochStakingPoints(epoch);
    }

    /// @dev Settles the current epoch on the live Tokenomics so it carries a staking incentive to claim.
    function _advanceEpoch() internal {
        vm.warp(block.timestamp + epochLen + 10);
        vm.roll(block.number + 1);
        ITokenomicsFork(TOKENOMICS).checkpoint();
    }

    /// @dev Full weight so the allocation binds on the epoch's max-staking-incentive cap; the weight sum is set
    ///      large enough not to cap the available amount below the epoch incentive.
    function _giveFullWeight() internal {
        vw.setWeights(STAKING_TARGET, CHAIN_ID, 1e18, 1e30);
    }

    // -----------------------------------------------------------------------
    // Migration wiring + proxy reads against the real contracts
    // -----------------------------------------------------------------------

    function test_migrationWiring_realContractsRepointed() public {
        // Proxy reads resolve against the live Tokenomics/Treasury
        assertEq(dispenser.tokenomics(), TOKENOMICS, "tokenomics immutable");
        assertEq(dispenser.treasury(), TREASURY, "treasury set at initialize");
        assertEq(dispenser.owner(), address(this), "deployer owns the proxy");

        // The live contracts now route to the new dispenser
        assertEq(ITreasuryFork(TREASURY).dispenser(), address(dispenser), "treasury repointed");
        assertEq(ITokenomicsFork(TOKENOMICS).dispenser(), address(dispenser), "tokenomics repointed");

        // changeImplementation stays owner-gated on the live proxy
        vm.prank(address(0xBAD));
        vm.expectRevert();
        dispenser.changeImplementation(address(0x1234));
    }

    // -----------------------------------------------------------------------
    // Claim money-path: real Treasury mint + real Tokenomics refund
    // -----------------------------------------------------------------------

    function test_proxiedClaim_realTreasuryMint_realInflationRefund() public {
        _giveFullWeight();
        _advanceEpoch();

        uint256 claimableEpoch = ITokenomicsFork(TOKENOMICS).epochCounter() - 1;
        uint256 epochIncentive = _stakingIncentiveOf(claimableEpoch);
        uint256 maxInc = _maxStakingIncentiveOf(claimableEpoch);
        assertGt(epochIncentive, 0, "settled epoch must carry a staking incentive");

        // At current mainnet inflation a full epoch incentive exceeds the per-epoch cap, so the cap binds
        uint256 expectedStaking = epochIncentive < maxInc ? epochIncentive : maxInc;
        uint256 expectedReturn = epochIncentive - expectedStaking;

        uint256 currentEpoch = ITokenomicsFork(TOKENOMICS).epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);
        uint256 supplyBefore = IOLASFork(OLAS).totalSupply();

        dispenser.claimStakingIncentives(1, CHAIN_ID, _targetBytes32(), "");

        // Real OLAS was minted by the live Treasury and forwarded to the deposit processor
        assertEq(IOLASFork(OLAS).balanceOf(address(depositProcessor)), expectedStaking, "OLAS delivered to processor");
        assertEq(depositProcessor.lastStakingIncentive(), expectedStaking, "incentive communicated to L2");
        assertEq(depositProcessor.lastTransferAmount(), expectedStaking, "no withheld: transfer == incentive");
        assertEq(IOLASFork(OLAS).totalSupply() - supplyBefore, expectedStaking, "totalSupply grew by the mint");

        // The capped-off remainder is refunded to the live staking inflation of the current epoch
        uint256 potAfter = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfter - potBefore, expectedReturn, "capped remainder refunded to inflation");
    }

    function test_proxiedClaim_withheldNetting_refundsReusedInflation() public {
        _giveFullWeight();

        // Seed a withheld amount (as the DAO would after an undelivered L2 batch) below the capped incentive
        uint256 withheld = 10_000 ether;
        dispenser.syncWithheldAmountMaintenance(CHAIN_ID, withheld, bytes32(uint256(1)));
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), withheld, "withheld seeded");

        _advanceEpoch();

        uint256 claimableEpoch = ITokenomicsFork(TOKENOMICS).epochCounter() - 1;
        uint256 epochIncentive = _stakingIncentiveOf(claimableEpoch);
        uint256 maxInc = _maxStakingIncentiveOf(claimableEpoch);
        uint256 expectedStaking = epochIncentive < maxInc ? epochIncentive : maxInc;
        assertGt(expectedStaking, withheld, "withheld must be below the incentive to exercise both branches");
        uint256 standardReturn = epochIncentive - expectedStaking;

        uint256 currentEpoch = ITokenomicsFork(TOKENOMICS).epochCounter();
        uint256 potBefore = _stakingIncentiveOf(currentEpoch);
        uint256 supplyBefore = IOLASFork(OLAS).totalSupply();

        dispenser.claimStakingIncentives(1, CHAIN_ID, _targetBytes32(), "");

        // Withheld fully consumed; only the non-covered part is actually minted and transferred
        assertEq(dispenser.mapChainIdWithheldAmounts(CHAIN_ID), 0, "withheld consumed");
        assertEq(depositProcessor.lastStakingIncentive(), expectedStaking, "full incentive communicated to L2");
        assertEq(depositProcessor.lastTransferAmount(), expectedStaking - withheld, "transfer netted by withheld");
        assertEq(IOLASFork(OLAS).totalSupply() - supplyBefore, expectedStaking - withheld, "only netted OLAS minted");

        // Standard return plus the withheld-covered portion are both returned to the live staking inflation
        uint256 potAfter = _stakingIncentiveOf(currentEpoch);
        assertEq(potAfter - potBefore, standardReturn + withheld, "standard return + reused withheld refunded");
    }
}
