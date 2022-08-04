// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/ITokenomics.sol";

/// @title Treasury - Smart contract for managing OLAS Treasury
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Treasury is IErrorsTokenomics, Ownable, ReentrancyGuard  {
    using SafeERC20 for IERC20;
    
    event DepositLPFromDepository(address token, uint256 tokenAmount, uint256 olasMintAmount);
    event DepositETHFromServices(uint256[] amounts, uint256[] serviceIds, uint256 revenue, uint256 donation);
    event Withdraw(address token, uint256 tokenAmount);
    event TokenReserves(address token, uint256 reserves);
    event EnableToken(address token);
    event DisableToken(address token);
    event TreasuryUpdated(address treasury);
    event TokenomicsUpdated(address tokenomics);
    event DepositoryUpdated(address depository);
    event DispenserUpdated(address dispenser);
    event TransferToDispenserETH(uint256 amount);
    event TransferToDispenserOLAS(uint256 amount);
    event TransferETHFailed(address account, uint256 amount);
    event TransferOLASFailed(address account, uint256 amount);
    event ReceivedETH(address sender, uint amount);

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

    // OLAS token address
    address public immutable olas;
    // Depository address
    address public depository;
    // Dispenser contract address
    address public dispenser;
    // Tokenomics contract address
    address public tokenomics;
    // ETH received from services
    uint256 public ETHFromServices;
    // ETH owned by treasury
    uint256 public ETHOwned;
    // Set of registered tokens
    address[] public tokenRegistry;
    // Token address => token info related to bonding
    mapping(address => TokenInfo) public mapTokens;

    /// @dev Treasury constructor.
    /// @param _olas OLAS token address.
    /// @param _depository Depository address.
    /// @param _tokenomics Tokenomics address.
    /// @param _dispenser Dispenser address.
    constructor(address _olas, address _depository, address _tokenomics, address _dispenser) payable {
        olas = _olas;
        ETHOwned = msg.value;
        depository = _depository;
        dispenser = _dispenser;
        tokenomics = _tokenomics;
    }

    // Only the depository has a privilege to control some actions of a treasury
    modifier onlyDepository() {
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }
        _;
    }

    /// @dev Changes various managing contract addresses.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    /// @param _tokenomics Tokenomics address.
    function changeManagers(address _depository, address _dispenser, address _tokenomics) external onlyOwner {
        if (_depository != address(0)) {
            depository = _depository;
            emit DepositoryUpdated(_depository);
        }
        if (_dispenser != address(0)) {
            dispenser = _dispenser;
            emit DispenserUpdated(_dispenser);
        }
        if (_tokenomics != address(0)) {
            tokenomics = _tokenomics;
            emit TokenomicsUpdated(_tokenomics);
        }
    }

    /// @dev Allows the depository to deposit an asset for OLAS.
    /// @param tokenAmount Token amount to get OLAS for.
    /// @param token Token address.
    /// @param olasMintAmount Amount of OLAS token issued.
    function depositTokenForOLAS(uint256 tokenAmount, address token, uint256 olasMintAmount) external onlyDepository
    {
        // Check if the token is authorized by the registry
        if (mapTokens[token].state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        mapTokens[token].reserves += tokenAmount;
        // Mint specified number of OLAS tokens corresponding to tokens bonding deposit if the amount is possible to mint
        if (ITokenomics(tokenomics).isAllowedMint(olasMintAmount)) {
            IOLAS(olas).mint(msg.sender, olasMintAmount);
        } else {
            revert MintRejectedByInflationPolicy(olasMintAmount);
        }

        // Transfer tokens from depository to treasury and add to the token treasury reserves
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);

        emit DepositLPFromDepository(token, tokenAmount, olasMintAmount);
    }

    /// @dev Deposits ETH from protocol-owned services in batch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositETHFromServices(uint256[] memory serviceIds, uint256[] memory amounts) external payable nonReentrant {
        if (msg.value == 0) {
            revert ZeroValue();
        }

        // Check for the same length of arrays
        uint256 numServices = serviceIds.length;
        if (amounts.length != numServices) {
            revert WrongArrayLength(numServices, amounts.length);
        }

        uint256 totalAmount;
        for (uint256 i = 0; i < numServices; ++i) {
            totalAmount += amounts[i];
        }

        // Check if the total transferred amount corresponds to the sum of amounts from services
        if (msg.value != totalAmount) {
            revert WrongAmount(msg.value, totalAmount);
        }

        (uint256 revenueETH, uint256 donationETH) = ITokenomics(tokenomics).trackServicesETHRevenue(serviceIds, amounts);
        ETHFromServices += revenueETH;
        ETHOwned += donationETH;

        emit DepositETHFromServices(amounts, serviceIds, revenueETH, donationETH);
    }

    /// @dev Allows owner to transfer specified tokens from reserves to a specified address.
    /// @param to Address to transfer funds to.
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token address or ETH (zero address).
    /// @return success True is the transfer is successful.
    function withdraw(address to, uint256 tokenAmount, address token) external onlyOwner
        returns (bool success)
    {
        // All the LP tokens must go under the bonding condition
        if (token != address(0)) {
            // Only approved token reserves can be used for redemptions
            if (mapTokens[token].state != TokenState.Enabled) {
                revert UnauthorizedToken(token);
            }
            // Decrease the global LP token record
            mapTokens[token].reserves -= tokenAmount;
            success = true;
            emit Withdraw(token, tokenAmount);
            // Transfer LP token
            IERC20(token).safeTransfer(to, tokenAmount);
        } else if (ETHOwned >= tokenAmount) {
            // This branch is used to transfer ETH to a specified address
            ETHOwned -= tokenAmount;
            emit Withdraw(address(0), tokenAmount);
            // Send ETH to the specified address
            (success, ) = to.call{value: tokenAmount}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), to, tokenAmount);
            }
        }
    }

    /// @dev Enables a token to be exchanged for OLAS.
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

    /// @dev Disables a token from the ability to exchange for OLAS.
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

    /// @dev Gets information about token being enabled for bonding.
    /// @param token Token address.
    /// @return enabled True if token is enabled.
    function isEnabled(address token) external view returns (bool enabled) {
        enabled = (mapTokens[token].state == TokenState.Enabled);
    }

    /// @dev Check if the token is UniswapV2Pair.
    /// @param token Address of a token.
    /// @return True if successful.
    function checkPair(address token) external returns (bool) {
        bool success;
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("kLast()")));
        assembly {
            success := call(
            5000,           // 5k gas
            token,         // destination address
            0,              // no ether
            add(data, 32),  // input buffer (starts after the first 32 bytes in the `data` array)
            mload(data),    // input length (loaded from the first 32 bytes in the `data` array)
            0,              // output buffer
            0               // output length
            )
        }
        return success;
    }

    /// @dev Rebalances ETH funds.
    /// @param amount ETH token amount.
    function _rebalanceETH(uint256 amount) internal {
        if (ETHFromServices >= amount) {
            ETHFromServices -= amount;
            ETHOwned += amount;
        }
    }

    /// @dev Sends funds to the dispenser contract.
    /// @param amountETH Amount in ETH.
    /// @param amountOLAS Amount in OLAS.
    function _sendFundsToDispenser(uint256 amountETH, uint256 amountOLAS) internal {
        if (amountETH > 0 && ETHFromServices >= amountETH) {
            ETHFromServices -= amountETH;
            (bool success, ) = dispenser.call{value: amountETH}("");
            if (success) {
                emit TransferToDispenserETH(amountETH);
            } else {
                revert TransferFailed(address(0), address(this), dispenser, amountETH);
            }
        }
        if (amountOLAS > 0) {
            if (ITokenomics(tokenomics).isAllowedMint(amountOLAS)) {
                IOLAS(olas).mint(dispenser, amountOLAS);
            }
            emit TransferToDispenserOLAS(amountOLAS);
        }
    }

    /// @dev Starts new epoch and allocates rewards.
    function allocateRewards() external onlyOwner {
        // Process the epoch data
        ITokenomics(tokenomics).checkpoint();
        // Get the rewards data
        (uint256 treasuryRewards, uint256 accountRewards, uint256 accountTopUps) = ITokenomics(tokenomics).getRewardsData();

        // Collect treasury's own reward share
        _rebalanceETH(treasuryRewards);

        // Send cumulative funds of staker, component, agent rewards and top-ups to dispenser
        _sendFundsToDispenser(accountRewards, accountTopUps);
    }

    /// @dev Receives ETH.
    receive() external payable {
        ETHOwned += msg.value;
        emit ReceivedETH(msg.sender, msg.value);
    }
}
