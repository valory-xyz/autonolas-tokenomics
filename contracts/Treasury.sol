// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./GenericTokenomics.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/IServiceTokenomics.sol";
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

    event DepositTokenFromAccount(address indexed account, address indexed token, uint256 tokenAmount, uint256 olasAmount);
    event DepositETHFromServices(address indexed sender, uint256 donation);
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
    /// @notice Only depository contract can call this function.
    /// @param account Account address making a deposit of LP tokens for OLAS.
    /// @param tokenAmount Token amount to get OLAS for.
    /// @param token Token address.
    /// @param olasMintAmount Amount of OLAS token issued.
    function depositTokenForOLAS(address account, uint256 tokenAmount, address token, uint256 olasMintAmount) external
    {
        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        TokenInfo storage tokenInfo = mapTokens[token];
        // Check if the token is authorized by the registry
        if (tokenInfo.state != TokenState.Enabled) {
            revert UnauthorizedToken(token);
        }

        uint256 reserves = tokenInfo.reserves + tokenAmount;
        tokenInfo.reserves = uint224(reserves);

        // Uniswap allowance implementation does not revert with the accurate message, check before the transfer is engaged
        if (IERC20(token).allowance(account, address(this)) < tokenAmount) {
            revert InsufficientAllowance(IERC20(token).allowance((account), address(this)), tokenAmount);
        }

        // Transfer tokens from account to treasury and add to the token treasury reserves
        // We assume that LP tokens enabled in the protocol are safe as they are enabled via governance
        // UniswapV2ERC20 realization has a standard transferFrom() function that returns a boolean value
        IERC20(token).transferFrom(account, address(this), tokenAmount);

        // Mint specified number of OLAS tokens corresponding to tokens bonding deposit
        // The olasMintAmount is guaranteed by the product supply limit, which is limited by the effectiveBond
        IOLAS(olas).mint(msg.sender, olasMintAmount);

        emit DepositTokenFromAccount(account, token, tokenAmount, olasMintAmount);
    }

    /// @dev Deposits ETH from protocol-owned services in batch.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    function depositETHFromServices(uint256[] memory serviceIds, uint256[] memory amounts) external payable {
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

        // Accumulate received donation from services
        uint256 donationETH = ITokenomics(tokenomics).trackServiceDonations(serviceIds, amounts);
        donationETH += ETHFromServices;
        ETHFromServices = uint96(donationETH);

        emit DepositETHFromServices(msg.sender, donationETH);
    }

    /// @dev Allows owner to transfer tokens from reserves to a specified address.
    /// @param to Address to transfer funds to.
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token or ETH address.
    /// @return success True is the transfer is successful.
    function withdraw(address to, uint256 tokenAmount, address token) external returns (bool success) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // All the LP tokens must go under the bonding condition
        if (token == ETH_TOKEN_ADDRESS) {
            uint96 amountOwned = ETHOwned;
            // Check if treasury has enough amount of owned ETH
            if ((amountOwned + 1) > tokenAmount) {
                // This branch is used to transfer ETH to a specified address
                amountOwned -= uint96(tokenAmount);
                ETHOwned = amountOwned;
                emit Withdraw(address(0), tokenAmount);
                // Send ETH to the specified address
                (success, ) = to.call{value: tokenAmount}("");
                if (!success) {
                    revert TransferFailed(address(0), address(this), to, tokenAmount);
                }
            } else {
                // Insufficient amount of treasury owned ETH
                revert AmountLowerThan(tokenAmount, amountOwned);
            }
        } else {
            TokenInfo storage tokenInfo = mapTokens[token];
            // Only approved token reserves can be used for redemptions
            if (tokenInfo.state != TokenState.Enabled) {
                revert UnauthorizedToken(token);
            }
            // Decrease the global LP token record
            uint256 reserves = tokenInfo.reserves;
            reserves -= tokenAmount;
            tokenInfo.reserves = uint224(reserves);

            success = true;
            emit Withdraw(token, tokenAmount);
            // Transfer LP token
            // We assume that LP tokens enabled in the protocol are safe by default
            // UniswapV2ERC20 realization has a standard transfer() function
            IERC20(token).transfer(to, tokenAmount);
        }
    }

    /// @dev Withdraws ETH and / or OLAS amounts to the requested account address.
    /// @notice Only dispenser contract can call this function.
    /// @notice Reentrancy guard is on a dispenser side.
    /// @notice Zero account address is not possible, since the dispenser contract interacts with msg.sender.
    /// @param account Account address.
    /// @param accountRewards Amount of account rewards.
    /// @param accountTopUps Amount of account top-ups.
    /// @return success True if the function execution is successful.
    function withdrawToAccount(address account, uint256 accountRewards, uint256 accountTopUps) external
        returns (bool success)
    {
        // Check for the dispenser access
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }

        // TODO pause withdraws here or in dispenser?

        uint256 amountETHFromServices = ETHFromServices;
        // Send ETH rewards, if any
        if (accountRewards > 0 && amountETHFromServices >= accountRewards) {
            amountETHFromServices -= accountRewards;
            ETHFromServices = uint96(amountETHFromServices);
            (success, ) = account.call{value: accountRewards}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), treasury, accountRewards);
            }
        }

        // Send OLAS top-ups
        if (accountTopUps > 0) {
            // Tokenomics has already accounted for the account's top-up amount,
            // thus the the mint does not break the inflation schedule
            IOLAS(olas).mint(account, accountTopUps);
            success = true;
            emit TransferToDispenserOLAS(accountTopUps);
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

        TokenInfo storage tokenInfo = mapTokens[token];
        if (tokenInfo.state != TokenState.Disabled) {
            // The reserves of a token must be zero in order to disable it
            if (tokenInfo.reserves > 0) {
                revert NonZeroValue();
            }
            tokenInfo.state = TokenState.Disabled;
            emit DisableToken(token);
        }
    }

    /// @dev Gets information about token being enabled for bonding.
    /// @param token Token address.
    /// @return enabled True if token is enabled.
    function isEnabled(address token) external view returns (bool enabled) {
        enabled = (mapTokens[token].state == TokenState.Enabled);
    }

    /// @dev Re-balances treasury funds to account for the treasury reward for a specific epoch.
    /// @param treasuryRewards Treasury rewards.
    /// @return success True, if the function execution is successful.
    function rebalanceTreasury(uint256 treasuryRewards) external returns (bool success) {
        // Check for the tokenomics contract access
        if (msg.sender != tokenomics) {
            revert ManagerOnly(msg.sender, tokenomics);
        }

        // Collect treasury's own reward share
        success = true;
        if (treasuryRewards > 0) {
            uint256 amountETHFromServices = ETHFromServices;
            if (amountETHFromServices >= treasuryRewards) {
                // Update ETH from services value
                amountETHFromServices -= treasuryRewards;
                // Update treasury ETH owned values
                uint256 amountETHOwned = ETHOwned;
                amountETHOwned += treasuryRewards;
                // Assign back to state variables
                ETHOwned = uint96(amountETHOwned);
                ETHFromServices = uint96(amountETHFromServices);
            } else {
                // There is not enough amount from services to allocate to the treasury
                success = false;
            }
        }
    }

    /// @dev Receives ETH.
    receive() external payable {
        uint96 amount = ETHOwned;
        amount += uint96(msg.value);
        ETHOwned = amount;
        emit ReceivedETH(msg.sender, msg.value);
    }

    /// @dev Drains slashed funds from the service registry.
    /// @return amount Drained amount.
    function drainServiceSlashedFunds() external returns (uint256 amount) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Get the service registry contract address
        address serviceRegistry = ITokenomics(tokenomics).serviceRegistry();
        // Call the service registry drain function
        amount = IServiceTokenomics(serviceRegistry).drain();
    }
}
