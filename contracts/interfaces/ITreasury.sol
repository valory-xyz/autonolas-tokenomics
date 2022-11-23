// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @dev Interface for treasury management.
interface ITreasury {
    /// @dev Allows approved address to deposit an asset for OLAS.
    /// @param account Account address making a deposit of LP tokens for OLAS.
    /// @param tokenAmount Token amount to get OLAS for.
    /// @param token Token address.
    /// @param olaMintAmount Amount of OLAS token issued.
    function depositTokenForOLAS(address account, uint256 tokenAmount, address token, uint256 olaMintAmount) external;

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

    /// @dev Withdraws ETH and / or OLAS amounts for the requested account.
    /// @notice Only dispenser contract can call this function.
    /// @notice Reentrancy guard is on a dispenser side.
    /// @notice Zero account address is not possible, since the dispenser contract interacts with msg.sender.
    /// @param account Account address.
    /// @param accountRewards Amount of account rewards.
    /// @param accountTopUps Amount of account top-ups.
    /// @return success True if the function execution is successful.
    function withdrawAccount(address account, uint256 accountRewards, uint256 accountTopUps) external returns (bool success);

    /// @dev Re-balances treasury funds to account for the treasury reward for a specific epoch.
    /// @param treasuryRewards Treasury rewards.
    /// @return success True, if the function execution is successful.
    function rebalanceTreasury(uint256 treasuryRewards) external returns (bool success);
}
