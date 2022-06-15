// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOLA is IERC20 {
    /// @dev Mints OLA tokens.
    /// @param account Account address.
    /// @param amount OLA token amount.
    function mint(address account, uint256 amount) external;

    /// @dev Provides OLA token time launch.
    /// @return Time launch.
    function timeLaunch() external returns (uint256);

    /// @dev Provides various checks for the inflation control.
    /// @param amount Amount of OLA to mint.
    /// @return True if the amount request is within inflation boundaries.
    function inflationControl(uint256 amount) external view returns (bool);

    /// @dev Gets the reminder of OLA possible for the mint.
    /// @return remainder OLA token remainder.
    function inflationRemainder() external view returns (uint256 remainder);

    /// @dev Provides the amount of decimals.
    /// @return Numebr of decimals.
    function decimals() external view returns(uint8);
}
