// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IOLAS {
    /// @dev Mints OLA tokens.
    /// @param account Account address.
    /// @param amount OLA token amount.
    function mint(address account, uint256 amount) external;

    /// @dev Provides OLA token time launch.
    /// @return Time launch.
    function timeLaunch() external returns (uint256);

    /// @dev Gets the reminder of OLA possible for the mint.
    /// @return remainder OLA token remainder.
    function inflationRemainder() external view returns (uint256 remainder);

    /// @dev Provides the amount of decimals.
    /// @return Numebr of decimals.
    function decimals() external view returns(uint8);
}
