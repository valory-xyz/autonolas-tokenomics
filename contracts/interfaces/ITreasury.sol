// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Interface for treasury management.
interface ITreasury {
    /// @dev Allows approved address to deposit an asset for OLA.
    /// @param tokenAmount Token amount to get OLA for.
    /// @param token Token address.
    /// @param olaMintAmount Amount of OLA token issued.
    function depositTokenForOLAS(uint224 tokenAmount, address token, uint96 olaMintAmount) external;

    /// @dev Deposits ETH from protocol-owned service.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of amounts.
    function depositETHFromServices(uint32[] memory serviceIds, uint96[] memory amounts) external payable;

    /// @dev Gets information about token being enabled.
    /// @param token Token address.
    /// @return enabled True is token is enabled.
    function isEnabled(address token) external view returns (bool enabled);

    /// @dev Check if the token is UniswapV2Pair.
    /// @param token Address of a token.
    function checkPair(address token) external returns (bool);

    /// @dev Allocates rewards and top-ups based on the input reward values from tokenomics.
    /// @param treasuryRewards Treasury rewards.
    /// @param accountRewards Cumulative staker, component and agent rewards.
    /// @param accountTopUps Cumulative staker, component and agent top-ups.
    /// @return success True, if the function execution is successful.
    function allocateRewards(uint96 treasuryRewards, uint96 accountRewards, uint96 accountTopUps) external
        returns (bool success);
}
