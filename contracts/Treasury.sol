// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IOLA.sol";
import "./interfaces/ITokenomics.sol";

/// @title Treasury - Smart contract for managing OLA Treasury
/// @author AL
contract Treasury is IErrors, Ownable, ReentrancyGuard  {
    using SafeERC20 for IERC20;
    
    event DepositFromDepository(address token, uint256 tokenAmount, uint256 olaMintAmount);
    event DepositFromServices(address token, uint256[] amounts, uint256[] serviceIds);
    event Withdrawal(address token, uint256 tokenAmount);
    event TokenReserves(address token, uint256 reserves);
    event EnableToken(address token);
    event DisableToken(address token);
    event TreasuryManagerUpdated(address manager);
    event DepositoryUpdated(address depository);

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

    // OLA token address
    address public immutable ola;
    // Tokenomics contract address
    address public tokenomics;
    // Depository address
    address public depository;
    // Set of registered tokens
    address[] public tokenRegistry;
    // Token address => token info
    mapping(address => TokenInfo) public mapTokens;

    // https://developer.kyber.network/docs/DappsGuide#contract-example
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE); // well-know representation ETH as address

    constructor(address _ola, address _depository, address _tokenomics) {
        if (_ola == address(0)) {
            revert ZeroAddress();
        }
        ola = _ola;
        mapTokens[ETH_TOKEN_ADDRESS].state = TokenState.Enabled;
        tokenomics = _tokenomics;
        depository = _depository;
    }

    // Only the depository has a privilege to control some actions of a treasury
    modifier onlyDepository() {
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }
        _;
    }

    /// @dev Changes the depository address.
    /// @param newDepository Address of a new depository.
    function changeDepository(address newDepository) external onlyOwner {
        depository = newDepository;
        emit DepositoryUpdated(newDepository);
    }

    /// @dev Allows approved address to deposit an asset for OLA.
    /// @param tokenAmount Token amount to get OLA for.
    /// @param token Token address.
    /// @param olaMintAmount Amount of OLA token issued.
    function depositTokenForOLA(uint256 tokenAmount, address token, uint256 olaMintAmount) external onlyDepository {
        // Check if the token is authorized by the registry
        if (mapTokens[token].state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        // Transfer tokens from depository to treasury and add to the token treasury reserves
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        mapTokens[token].reserves += tokenAmount;
        // Mint specified number of OLA tokens corresponding to tokens bonding deposit
        IOLA(ola).mint(msg.sender, olaMintAmount);

        emit DepositFromDepository(token, tokenAmount, olaMintAmount);
    }

    /// @dev Deposits ETH from protocol-owned services in batch.
    function depositETHFromServiceBatch(uint256[] memory serviceIds, uint256[] memory amounts) external payable nonReentrant {
        // Check for the same length of arrays
        uint256 numServices = serviceIds.length;
        if (amounts.length != numServices) {
            // TODO correct the revert
            revert WrongAgentsData(numServices, amounts.length);
        }

        uint256 totalAmount;
        for (uint256 i = 0; i < numServices; ++i) {
            totalAmount += amounts[i];
        }

        // Check if the total transferred amount corresponds to the sum of amounts from services
        if (msg.value != totalAmount) { // not sure 
            // TODO correct the revert
            revert AmountLowerThan(msg.value, totalAmount);
        }

        ITokenomics(tokenomics).trackServicesETHRevenue(serviceIds, amounts);
        emit DepositFromServices(ETH_TOKEN_ADDRESS, amounts, serviceIds);
    }

    /// @dev Deposits ETH from protocol-owned service.
    function depositETHFromService(uint256 serviceId) external payable nonReentrant {
        if (msg.value == 0) {
            revert ZeroValue();
        }
        uint256[] memory serviceIds = new uint256[](1);
        serviceIds[0] = serviceId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = msg.value;
        ITokenomics(tokenomics).trackServicesETHRevenue(serviceIds, amounts);
        emit DepositFromServices(ETH_TOKEN_ADDRESS, amounts, serviceIds);
    }

    /// @dev Allows owner to transfer specified tokens from reserves to a specified address.
    /// @param to Address to transfer funds to.
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token address.
    function withdraw(address to, uint256 tokenAmount, address token) external onlyOwner {
        // Only approved token reserves can be used for redemptions
        if (mapTokens[token].state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        // Transfer tokens from reserves to the manager
        if (token == ETH_TOKEN_ADDRESS) {
            (bool success, ) = to.call{value: tokenAmount}("");
            if (!success) {
                revert TransferFailed(token, address(this), to, tokenAmount);
            }
        } else {
            IERC20(token).safeTransfer(to, tokenAmount);
        }
        mapTokens[token].reserves -= tokenAmount;

        emit Withdrawal(token, tokenAmount);
    }

    /// @dev Enables a token to be exchanged for OLA.
    /// @param token Token address.
    function enableToken(address token) external onlyOwner {
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
    function disableToken(address token) external onlyOwner {
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
