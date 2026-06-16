// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

interface IVoteWeighting {
    function nomineeRelativeWeight(bytes32 account, uint256 chainId, uint256 time)
        external view returns (uint256 relativeWeight, uint256 totalSum);
}

/// @title LivenessWeightInvariant
/// @notice Verifies the invariant that makes Dispenser.retain() and the
///         calculateStakingIncentives zero-total-weight branch mutually exclusive on a given epoch:
///         on the live VoteWeighting, a zero total vote weight implies a zero relative weight for
///         EVERY nominee (relative weight is assigned only inside `if (totalSum > 0)`). Therefore
///         retain()'s `stakingIncentive * relativeWeight` term is zero for exactly the epochs the
///         `totalWeightSum == 0` refund branch handles, so the same epoch's incentive cannot be
///         refunded by both paths.
///
///         Run: forge test --match-path 'audits/internal17/test/*' --fork-url <mainnet> -vv
contract LivenessWeightInvariant is Test {
    // Live VoteWeighting wired into the production Dispenser (0x5650300fCBab43A0D7D02F8Cb5d0f039402593f0)
    address constant VOTE_WEIGHTING = 0x95418b46d5566D3d1ea62C12Aea91227E566c5c1;

    function test_zeroTotalSum_implies_zeroWeight() public {
        IVoteWeighting vw = IVoteWeighting(VOTE_WEIGHTING);

        // A time bucket far in the future has no checkpointed votes => pointsSum[t].bias == 0.
        uint256 futureTime = block.timestamp + 520 weeks;
        // Any nominee works: the `if (totalSum > 0)` guard short-circuits before nominee lookup.
        bytes32 nominee = bytes32(uint256(0xdead));

        (uint256 weight, uint256 totalSum) = vw.nomineeRelativeWeight(nominee, 1, futureTime);

        emit log_named_uint("totalSum (no-vote bucket)", totalSum);
        emit log_named_uint("relativeWeight", weight);

        assertEq(totalSum, 0, "precondition: no votes => totalSum == 0");
        assertEq(weight, 0, "zero total weight must yield zero relative weight for every nominee");
    }
}
