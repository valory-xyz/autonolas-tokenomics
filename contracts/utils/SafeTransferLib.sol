// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Failure of a token transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param value Value.
error TokenTransferFailed(address token, address from, address to, uint256 value);

/// @dev The implementation is fully copied from the audited MIT-licensed solmate code repository:
///      https://github.com/transmissions11/solmate/blob/v7/src/utils/SafeTransferLib.sol
///      The original library imports the `ERC20` abstract token contract, and thus embeds all that contract
///      related code that is not needed. In this version, `ERC20` is swapped with the `address` representation.
///      Also, the final `require` statement is modified with this contract own `revert` statement.
library SafeTransferLib {
    /// @dev Safe token transferFrom implementation.
    /// @param token Token address.
    /// @param from Address to transfer tokens from.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        bool success;

        // solhint-disable-next-line no-inline-assembly
        assembly {
        // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

        // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(4, from) // Append the "from" argument.
            mstore(36, to) // Append the "to" argument.
            mstore(68, amount) // Append the "amount" argument.

            success := and(
            // Set success to whether the call reverted, if not we check it either
            // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
            // We use 100 because that's the total length of our calldata (4 + 32 * 3)
            // Counterintuitively, this call() must be positioned after the or() in the
            // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, 0, 100, 0, 32)
            )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }

        if (!success) {
            revert TokenTransferFailed(token, from, to, amount);
        }
    }

    /// @dev Safe token transfer implementation.
    /// @notice The implementation is fully copied from the audited MIT-licensed solmate code repository:
    ///         https://github.com/transmissions11/solmate/blob/v7/src/utils/SafeTransferLib.sol
    ///         The original library imports the `ERC20` abstract token contract, and thus embeds all that contract
    ///         related code that is not needed. In this version, `ERC20` is swapped with the `address` representation.
    ///         Also, the final `require` statement is modified with this contract own `revert` statement.
    /// @param token Token address.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function safeTransfer(address token, address to, uint256 amount) internal {
        bool success;

        // solhint-disable-next-line no-inline-assembly
        assembly {
        // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

        // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(4, to) // Append the "to" argument.
            mstore(36, amount) // Append the "amount" argument.

            success := and(
            // Set success to whether the call reverted, if not we check it either
            // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
            // We use 68 because that's the total length of our calldata (4 + 32 * 2)
            // Counterintuitively, this call() must be positioned after the or() in the
            // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, 0, 68, 0, 32)
            )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }

        if (!success) {
            revert TokenTransferFailed(token, address(this), to, amount);
        }
    }
}