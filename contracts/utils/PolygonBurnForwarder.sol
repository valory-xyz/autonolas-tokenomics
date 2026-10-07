// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Polygon PoS child token interface
interface IChildToken {
    /// @dev Burns tokens on Polygon to start a PoS bridge exit.
    /// @notice The exit releases the L1 tokens to the burning address itself, at the same address on Ethereum.
    /// @param amount Token amount.
    function withdraw(uint256 amount) external;
}

// ERC20 token interface
interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Wrong chain Id.
/// @param chainId Chain Id.
error WrongChainId(uint256 chainId);

/// @dev Token transfer failed.
/// @param token Token address.
/// @param to Address to transfer to.
/// @param amount Token amount.
error TransferFailed(address token, address to, uint256 amount);

/// @title PolygonBurnForwarder - Smart contract for routing Polygon OLAS to the L1 OLAS Burner over the Polygon PoS bridge.
/// @dev Polygon's PoS OLAS only exposes withdraw(uint256), which cannot name an L1 recipient: the exit releases the L1
///      OLAS to the address that burned on Polygon. This contract is deployed by CREATE2 at the same address on Polygon
///      and on Ethereum, with identical constructor arguments, so that address exists on both sides:
///      - on Polygon, relay() burns the contract's OLAS balance via withdraw(), starting the PoS exit;
///      - on Ethereum, once anyone has completed that exit with the burn proof (RootChainManager.exit), the released
///        OLAS sits on this contract, and relay() transfers it to the L1 OLAS Burner.
///      relay() is permissionless on both chains and reverts on any other chain. The contract holds no other state.
contract PolygonBurnForwarder {
    event Withdrawn(address indexed sender, uint256 amount);
    event Burned(address indexed sender, address indexed olasBurner, uint256 amount);

    // Version number
    string public constant VERSION = "0.1.0";

    // Polygon PoS OLAS address
    address public immutable polygonOlas;
    // L1 OLAS address
    address public immutable l1Olas;
    // L1 OLAS Burner address
    address public immutable olasBurner;
    // Polygon chain Id
    uint256 public immutable polygonChainId;
    // L1 chain Id
    uint256 public immutable l1ChainId;

    /// @dev PolygonBurnForwarder constructor.
    /// @notice The arguments must be identical on both chains, or the CREATE2 addresses differ.
    /// @param _polygonOlas Polygon PoS OLAS address.
    /// @param _l1Olas L1 OLAS address.
    /// @param _olasBurner L1 OLAS Burner address.
    /// @param _polygonChainId Polygon chain Id.
    /// @param _l1ChainId L1 chain Id.
    constructor(
        address _polygonOlas,
        address _l1Olas,
        address _olasBurner,
        uint256 _polygonChainId,
        uint256 _l1ChainId
    ) {
        // Check for zero addresses
        if (_polygonOlas == address(0) || _l1Olas == address(0) || _olasBurner == address(0)) {
            revert ZeroAddress();
        }

        // Check for zero values
        if (_polygonChainId == 0 || _l1ChainId == 0) {
            revert ZeroValue();
        }

        // The two chains must differ, so that relay() has one branch per chain
        if (_polygonChainId == _l1ChainId) {
            revert WrongChainId(_l1ChainId);
        }

        polygonOlas = _polygonOlas;
        l1Olas = _l1Olas;
        olasBurner = _olasBurner;
        polygonChainId = _polygonChainId;
        l1ChainId = _l1ChainId;
    }

    /// @dev Relays the OLAS balance towards the L1 OLAS Burner.
    /// @notice On Polygon, burns the balance to start the PoS exit to this contract's address on Ethereum.
    ///         On Ethereum, transfers the balance released by completed exits to the L1 OLAS Burner.
    /// @return amount OLAS amount relayed.
    function relay() external returns (uint256 amount) {
        if (block.chainid == polygonChainId) {
            // Get Polygon OLAS balance
            amount = IToken(polygonOlas).balanceOf(address(this));
            if (amount == 0) {
                revert ZeroValue();
            }

            // Burn on Polygon: the PoS exit releases the same amount to this contract's address on Ethereum
            IChildToken(polygonOlas).withdraw(amount);

            emit Withdrawn(msg.sender, amount);
        } else if (block.chainid == l1ChainId) {
            // Get L1 OLAS balance
            amount = IToken(l1Olas).balanceOf(address(this));
            if (amount == 0) {
                revert ZeroValue();
            }

            // Transfer to the L1 OLAS Burner
            bool success = IToken(l1Olas).transfer(olasBurner, amount);
            if (!success) {
                revert TransferFailed(l1Olas, olasBurner, amount);
            }

            emit Burned(msg.sender, olasBurner, amount);
        } else {
            revert WrongChainId(block.chainid);
        }
    }
}
