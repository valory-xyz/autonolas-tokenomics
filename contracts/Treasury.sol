// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./GenericTokenomics.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/ITokenomics.sol";

/*
* In this contract we consider both ETH and OLAS tokens.
* For ETH tokens, there are currently about 121 million tokens.
* Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply.
* Lately the inflation rate was lower and could actually be deflationary.
*
* For OLAS tokens, the initial numbers will be as follows:
*  - For the first 10 years there will be the cap of 1 billion (1e27) tokens;
*  - After 10 years, the inflation rate is capped at 2% per year.
* Starting from a year 11, the maximum number of tokens that can be reached per the year x is 1e27 * (1.02)^x.
* To make sure that a unit(n) does not overflow the total supply during the year x, we have to check that
* 2^n - 1 >= 1e27 * (1.02)^x. We limit n by 96, thus it would take 220+ years to reach that total supply.
*
* We then limit each time variable to last until the value of 2^32 - 1 in seconds.
* 2^32 - 1 gives 136+ years counted in seconds starting from the year 1970.
* Thus, this counter is safe until the year 2106.
*
* The number of blocks cannot be practically bigger than the number of seconds, since there is more than one second
* in a block. Thus, it is safe to assume that uint32 for the number of blocks is also sufficient.
*
* In conclusion, this contract is only safe to use until 2106.
*/

/// @title Treasury - Smart contract for managing OLAS Treasury
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Treasury is GenericTokenomics {

    event DepositTokenFromDepository(address indexed token, uint256 tokenAmount, uint256 olasMintAmount);
    event DepositETHFromServices(address indexed sender, uint256 revenue, uint256 donation);
    event Withdraw(address indexed token, uint256 tokenAmount);
    event TokenReserves(address indexed token, uint256 reserves);
    event EnableToken(address indexed token);
    event DisableToken(address indexed token);
    event TransferToDispenserOLAS(uint256 amount);
    event ReceivedETH(address indexed sender, uint256 amount);

    enum TokenState {
        NonExistent,
        Enabled,
        Disabled
    }
    
    struct TokenInfo {
        // State of a token in this treasury
        TokenState state;
        // Reserves of a token
        // Reserves are 112 bits in size, we assume that their calculations will be limited by reserves0 x reserves1
        uint224 reserves;
    }

    // ETH received from services
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public ETHFromServices;
    // ETH owned by treasury
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public ETHOwned;
    // Token address => token info related to bonding
    mapping(address => TokenInfo) public mapTokens;
    // Set of registered tokens
    address[] public tokenRegistry;

    // A well-known representation of an ETH as address
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @dev Treasury constructor.
    /// @param _olas OLAS token address.
    /// @param _depository Depository address.
    /// @param _tokenomics Tokenomics address.
    /// @param _dispenser Dispenser address.
    constructor(address _olas, address _depository, address _tokenomics, address _dispenser) payable
        GenericTokenomics(_olas, _tokenomics, address(this), _depository, _dispenser, TokenomicsRole.Treasury)
    {
        ETHOwned = uint96(msg.value);
    }

    /// @dev Allows the depository to deposit an asset for OLAS.
    /// @param tokenAmount Token amount to get OLAS for.
    /// @param token Token address.
    /// @param olasMintAmount Amount of OLAS token issued.
    function depositTokenForOLAS(uint224 tokenAmount, address token, uint96 olasMintAmount) external
    {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        // Check if the token is authorized by the registry
        if (mapTokens[token].state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        uint224 reserves = mapTokens[token].reserves;
        reserves += tokenAmount;
        mapTokens[token].reserves = reserves;
        // Mint specified number of OLAS tokens corresponding to tokens bonding deposit if the amount is possible to mint
        if (ITokenomics(tokenomics).isAllowedMint(olasMintAmount)) {
            IOLAS(olas).mint(msg.sender, olasMintAmount);
        } else {
            revert MintRejectedByInflationPolicy(olasMintAmount);
        }

        // Transfer tokens from depository to treasury and add to the token treasury reserves
        // We assume that LP tokens enabled in the protocol are safe as they are enabled via governance
        // UniswapV2ERC20 realization has a standard transferFrom() function that returns a boolean value
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);

        emit DepositTokenFromDepository(token, tokenAmount, olasMintAmount);
    }

    /// @dev Deposits ETH from protocol-owned services in batch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositETHFromServices(uint32[] memory serviceIds, uint96[] memory amounts) external payable {
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

        (uint96 revenueETH, uint96 donationETH) = ITokenomics(tokenomics).trackServicesETHRevenue(serviceIds, amounts);
        ETHFromServices += revenueETH;
        ETHOwned += donationETH;

        emit DepositETHFromServices(msg.sender, revenueETH, donationETH);
    }

    /// @dev Allows owner to transfer tokens from reserves to a specified address.
    /// @param to Address to transfer funds to.
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token or ETH address.
    /// @return success True is the transfer is successful.
    function withdraw(address to, uint224 tokenAmount, address token) external returns (bool success) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // All the LP tokens must go under the bonding condition
        if (token == ETH_TOKEN_ADDRESS && (ETHOwned + 1) > tokenAmount) {
            // This branch is used to transfer ETH to a specified address
            ETHOwned -= uint96(tokenAmount);
            emit Withdraw(address(0), tokenAmount);
            // Send ETH to the specified address
            (success, ) = to.call{value: tokenAmount}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), to, tokenAmount);
            }
        } else {
            // Only approved token reserves can be used for redemptions
            if (mapTokens[token].state != TokenState.Enabled) {
                revert UnauthorizedToken(token);
            }
            // Decrease the global LP token record
            mapTokens[token].reserves -= tokenAmount;
            success = true;
            emit Withdraw(token, tokenAmount);
            // Transfer LP token
            // We assume that LP tokens enabled in the protocol are safe by default
            // UniswapV2ERC20 realization has a standard transfer() function
            IERC20(token).transfer(to, tokenAmount);
        }
    }

    /// @dev Enables a token to be exchanged for OLAS.
    /// @param token Token address.
    function enableToken(address token) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

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
    function disableToken(address token) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        TokenInfo memory tokenInfo = mapTokens[token];
        if (tokenInfo.state != TokenState.Disabled) {
            // The reserves of a token must be zero in order to disable it
            if (tokenInfo.reserves > 0) {
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

    /// @dev Rebalances ETH funds.
    /// @param amount ETH token amount.
    function _rebalanceETH(uint96 amount) internal {
        if (ETHFromServices >= amount) {
            ETHFromServices -= amount;
            ETHOwned += amount;
        }
    }

    /// @dev Sends funds to the dispenser contract.
    /// @param amountETH Amount in ETH.
    /// @param amountOLAS Amount in OLAS.
    function _sendFundsToDispenser(uint96 amountETH, uint96 amountOLAS) internal {
        if (amountETH > 0 && ETHFromServices >= amountETH) {
            ETHFromServices -= amountETH;
            (bool success, ) = dispenser.call{value: amountETH}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), dispenser, amountETH);
            }
        }
        if (amountOLAS > 0) {
            // TODO This check is not needed if the calculations in Tokenomics are done correctly.
            // TODO if amountOLAS os greater than zero at this point of time, we definitely can mint that amount.
            // TODO Otherwise amountOLAS will be equal to zero.
            if (ITokenomics(tokenomics).isAllowedMint(amountOLAS)) {
                IOLAS(olas).mint(dispenser, amountOLAS);
                emit TransferToDispenserOLAS(amountOLAS);
            }
        }
    }

    /// @dev Starts new epoch and allocates rewards.
    function allocateRewards() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // TODO Get rewards inside the checkpoint function
        // Process the epoch data
        ITokenomics(tokenomics).checkpoint();
        // TODO Only if the new epoch started we need to get the rewards calculation
        // Get the rewards data
        (uint96 treasuryRewards, uint96 accountRewards, uint96 accountTopUps) = ITokenomics(tokenomics).getRewardsData();

        // TODO Unroll those two functions here
        // Collect treasury's own reward share
        _rebalanceETH(treasuryRewards);

        // Send cumulative funds of staker, component, agent rewards and top-ups to dispenser
        _sendFundsToDispenser(accountRewards, accountTopUps);
    }

    /// @dev Receives ETH.
    receive() external payable {
        ETHOwned += uint96(msg.value);
        emit ReceivedETH(msg.sender, msg.value);
    }
}
