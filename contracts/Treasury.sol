// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IOLA.sol";

/// @title Treasury - Smart contract for managing OLA Treasury
/// @author AL
contract Treasury is IErrors, Ownable {
    using SafeERC20 for IERC20;
    
    event Deposit(address token, uint256 tokenAmount, uint256 olaMintAmount);
    event Withdrawal(address token, uint256 tokenAmount);
    event TokenReserves(address token, uint256 reserves);
    event EnableToken(address token);
    event DisableToken(address token);
    event TreasuryManagerUpdated(address manager);
    event TreasuryDepositoryUpdated(address depository);

    enum TokenState {
        NonExistent,
        Enabled,
        Disabled
    }
    
    struct TokenInfo {
        // State of a token in this treasury
        TokenState state;
        // Reserves of a token
        uint256 reserves;
    }

    // OLA interface
    IOLA public immutable ola;
    // Treasury manager
    address public manager;
    // Depository address
    address public depository;
    // Set of registered tokens
    address[] public tokenRegistry;
    // Token address => token info
    mapping(address => TokenInfo) public mapTokens;

    constructor(address olaToken, address initManager) {
        if (olaToken == address(0)) {
            revert ZeroAddress();
        }

        ola = IOLA(olaToken);
        manager = initManager;
        depository = initManager;
    }

    // Only the manager has a privilege to manipulate a treasury
    modifier onlyManager() {
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }
        _;
    }

    // Only the depository has a privilege to control some actions of a treasury
    modifier onlyDepository() {
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }
        _;
    }

    /// @dev Changes the treasury manager.
    /// @param newManager Address of a new treasury manager.
    function changeManager(address newManager) external onlyOwner {
        manager = newManager;
        emit TreasuryManagerUpdated(newManager);
    }

    /// @dev Changes the depository address.
    /// @param newDepository Address of a new depository.
    function changeDepository(address newDepository) external onlyManager {
        depository = newDepository;
        emit TreasuryDepositoryUpdated(newDepository);
    }

    /// @dev Allows approved address to deposit an asset for OLA.
    /// @param tokenAmount Token amount to get OLA for.
    /// @param token Token address.
    /// @param olaMintAmount Amount of OLA token issued.
    function deposit(uint256 tokenAmount, address token, uint256 olaMintAmount) external onlyDepository {
        // Check if the token is authorized by the registry
        if (mapTokens[token].state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        // Transfer tokens from depository to treasury and add to the token treasury reserves
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        mapTokens[token].reserves += tokenAmount;
        // Mint specified number of OLA tokens corresponding to tokens bonding deposit
        ola.mint(msg.sender, olaMintAmount);

        emit Deposit(token, tokenAmount, olaMintAmount);
    }


    /// @dev Allows manager to withdraw specified tokens from reserves
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token address.
    function withdraw(uint256 tokenAmount, address token) external onlyManager {
        // Only approved token reserves can be used for redemptions
        if (mapTokens[token].state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        // Transfer tokens from reserves to the manager
        IERC20(token).safeTransfer(msg.sender, tokenAmount);
        mapTokens[token].reserves -= tokenAmount;

        emit Withdrawal(token, tokenAmount);
    }

    /// @dev Enables a token to be exchanged for OLA.
    /// @param token Token address.
    function enableToken(address token) external onlyManager {
        TokenState state = mapTokens[token].state;
        if (state != TokenState.Enabled) {
            if (state == TokenState.NonExistent) {
                tokenRegistry.push(token);
            }
            mapTokens[token].state = TokenState.Enabled;
            emit EnableToken(token);
        }
    }

    /// @dev Disables a token from the ability to exchange for OLA.
    /// @param token Token address.
    function disableToken(address token) external onlyManager {
        TokenState state = mapTokens[token].state;
        if (state != TokenState.Disabled) {
            // The reserves of a token must be zero in order to disable it
            if (mapTokens[token].reserves > 0) {
                revert NonZeroValue();
            }
            mapTokens[token].state = TokenState.Disabled;
            emit DisableToken(token);
        }
    }

    /// @dev Gets the token registry set.
    /// @return Set of token registry.
    function getTokenRegistry() public view returns (address[] memory) {
        return tokenRegistry;
    }

    /// @dev Gets information about token being enabled.
    /// @param token Token address.
    /// @return enabled True is token is enabled.
    function isEnabled(address token) public view returns (bool enabled) {
        enabled = (mapTokens[token].state == TokenState.Enabled);
    }
}
