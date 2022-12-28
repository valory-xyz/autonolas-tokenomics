// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IErrorsTokenomics.sol";
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
/// TODO check for invariant to be not broken in the original version
///#invariant {:msg "broken conservation law"} address(this).balance == ETHFromServices+ETHOwned;
contract Treasury is IErrorsTokenomics {
    event OwnerUpdated(address indexed owner);
    event TokenomicsUpdated(address indexed tokenomics);
    event DepositoryUpdated(address indexed depository);
    event DispenserUpdated(address indexed dispenser);
    event DepositTokenFromAccount(address indexed account, address indexed token, uint256 tokenAmount, uint256 olasAmount);
    event DonateToServicesETH(address indexed sender, uint256 donation);
    event Withdraw(address indexed token, uint256 tokenAmount);
    event EnableToken(address indexed token);
    event DisableToken(address indexed token);
    event TransferToDispenserOLAS(uint256 amount);
    event ReceiveETH(address indexed sender, uint256 amount);
    event UpdateTreasuryBalances(uint256 ETHOwned, uint256 ETHFromServices);
    event PauseTreasury();
    event UnpauseTreasury();

    // A well-known representation of an ETH as address
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    // Minimum accepted donation value
    uint256 public constant MIN_ACCEPTED_AMOUNT = 5e16;

    // Owner address
    address public owner;
    // ETH received from services
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public ETHFromServices;

    // OLAS token address
    address public olas;
    // ETH owned by treasury
    // Even if the ETH inflation rate is 5% per year, it would take 130+ years to reach 2^96 - 1 of ETH total supply
    uint96 public ETHOwned;

    // Tkenomics contract address
    address public tokenomics;
    // Contract pausing
    uint8 public paused = 1;
    // Reentrancy lock
    uint8 internal _locked;

    // Depository contract address
    address public depository;
    // Dispenser contract address
    address public dispenser;

    // Token address => token reserves
    mapping(address => uint256) public mapTokenReserves;
    // Token address => enabled / disabled status
    mapping(address => bool) public mapEnabledTokens;

    /// @dev Treasury constructor.
    /// @param _olas OLAS token address.
    /// @param _tokenomics Tokenomics address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    constructor(address _olas, address _tokenomics, address _depository, address _dispenser) payable {
        owner = msg.sender;
        _locked = 1;
        olas = _olas;
        tokenomics = _tokenomics;
        depository = _depository;
        dispenser = _dispenser;
        ETHOwned = uint96(msg.value);
    }

    /// @dev Receives ETH.
    ///#if_succeeds {:msg "we do not touch the balance of developers" } old(ETHFromServices) == ETHFromServices;
    ///#if_succeeds {:msg "conservation law"} address(this).balance == ETHFromServices+ETHOwned;
    ///#if_succeeds {:msg "any paused"} paused == 1 || paused == 2;
    receive() external payable {
        // TODO shall the contract continue receiving ETH when paused?
        if (msg.value < MIN_ACCEPTED_AMOUNT) {
            revert AmountLowerThan(msg.value, MIN_ACCEPTED_AMOUNT);
        }

        uint96 amount = ETHOwned;
        amount += uint96(msg.value);
        ETHOwned = amount;
        emit ReceiveETH(msg.sender, msg.value);
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes various managing contract addresses.
    /// @param _tokenomics Tokenomics address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    function changeManagers(address _tokenomics, address _depository, address _dispenser) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Change Tokenomics contract address
        if (_tokenomics != address(0)) {
            tokenomics = _tokenomics;
            emit TokenomicsUpdated(_tokenomics);
        }
        // Change Depository contract address
        if (_depository != address(0)) {
            depository = _depository;
            emit DepositoryUpdated(_depository);
        }
        // Change Dispenser contract address
        if (_dispenser != address(0)) {
            dispenser = _dispenser;
            emit DispenserUpdated(_dispenser);
        }
    }

    /// @dev Allows the depository to deposit an asset for OLAS.
    /// @notice Only depository contract can call this function.
    /// @param account Account address making a deposit of LP tokens for OLAS.
    /// @param tokenAmount Token amount to get OLAS for.
    /// @param token Token address.
    /// @param olasMintAmount Amount of OLAS token issued.
    ///#if_succeeds {:msg "we do not touch the total eth balance" } old(address(this).balance) == address(this).balance;
    ///#if_succeeds {:msg "any paused"} paused == 1 || paused == 2;
    function depositTokenForOLAS(address account, uint256 tokenAmount, address token, uint256 olasMintAmount) external {
        // TODO shall the contract continue receiving LP / minting OLAS when paused?

        // Check for the depository access
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }

        // Check if the token is authorized by the registry
        if (!mapEnabledTokens[token]) {
            revert UnauthorizedToken(token);
        }

        // Increase the amount of LP token reserves
        uint256 reserves = mapTokenReserves[token] + tokenAmount;
        mapTokenReserves[token] = reserves;

        // Uniswap allowance implementation does not revert with the accurate message, check before the transfer is engaged
        if (IERC20(token).allowance(account, address(this)) < tokenAmount) {
            revert InsufficientAllowance(IERC20(token).allowance((account), address(this)), tokenAmount);
        }

        // Transfer tokens from account to treasury and add to the token treasury reserves
        // We assume that LP tokens enabled in the protocol are safe as they are enabled via governance
        // UniswapV2ERC20 realization has a standard transferFrom() function that returns a boolean value
        bool success = IERC20(token).transferFrom(account, address(this), tokenAmount);
        if (!success) {
            revert TransferFailed(token, account, address(this), tokenAmount);
        }

        // Mint specified number of OLAS tokens corresponding to tokens bonding deposit
        // The olasMintAmount is guaranteed by the product supply limit, which is limited by the effectiveBond
        IOLAS(olas).mint(msg.sender, olasMintAmount);

        emit DepositTokenFromAccount(account, token, tokenAmount, olasMintAmount);
    }

    /// @dev Deposits service donations in ETH.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Set of corresponding amounts deposited on behalf of each service Id.
    ///#if_succeeds {:msg "we do not touch the owners balance" } old(ETHOwned) == ETHOwned;
    ///if_succeeds {:msg "updated ETHFromServices"} ETHFromServices == old(ETHFromServices) + msg.value; ! rule is off, broken in original version
    ///#if_succeeds {:msg "any paused"} paused == 1 || paused == 2;
    function depositServiceDonationsETH(uint256[] memory serviceIds, uint256[] memory amounts) external payable {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check that the amount donated has at least a practical minimal value
        // TODO Decide on the final minimal value
        if (msg.value < MIN_ACCEPTED_AMOUNT) {
            revert AmountLowerThan(msg.value, MIN_ACCEPTED_AMOUNT);
        }

        // Check for the same length of arrays
        uint256 numServices = serviceIds.length;
        if (amounts.length != numServices) {
            revert WrongArrayLength(numServices, amounts.length);
        }

        uint256 totalAmount;
        for (uint256 i = 0; i < numServices; ++i) {
            if (amounts[i] == 0) {
                revert ZeroValue();
            }
            totalAmount += amounts[i];
        }

        // Check if the total transferred amount corresponds to the sum of amounts from services
        if (msg.value != totalAmount) {
            revert WrongAmount(msg.value, totalAmount);
        }

        // TODO shall the contract continue receiving ETH when paused?
        // Accumulate received donation from services
        uint256 donationETH = ETHFromServices + msg.value;
        ETHFromServices = uint96(donationETH);
        emit DonateToServicesETH(msg.sender, msg.value);

        // Track service donations on the Tokenomics side
        ITokenomics(tokenomics).trackServiceDonations(msg.sender, serviceIds, amounts, msg.value);

        _locked = 1;
    }

    /// @dev Allows owner to transfer tokens from reserves to a specified address.
    /// @param to Address to transfer funds to.
    /// @param tokenAmount Token amount to get reserves from.
    /// @param token Token or ETH address.
    /// @return success True is the transfer is successful.
    ///#if_succeeds {:msg "we do not touch the balance of developers" } old(ETHFromServices) == ETHFromServices;
    ///#if_succeeds {:msg "updated ETHOwned"} token == ETH_TOKEN_ADDRESS ==> ETHOwned == old(ETHOwned) - tokenAmount;
    ///#if_succeeds {:msg "any paused"} paused == 1 || paused == 2; 
    function withdraw(address to, uint256 tokenAmount, address token) external returns (bool success) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (tokenAmount == 0) {
            revert ZeroValue();
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
            // Only approved token reserves can be used for redemptions
            if (!mapEnabledTokens[token]) {
                revert UnauthorizedToken(token);
            }
            // Decrease the global LP token record
            uint256 reserves = mapTokenReserves[token];
            if ((reserves + 1) > tokenAmount) {
                reserves -= tokenAmount;
                mapTokenReserves[token] = reserves;

                emit Withdraw(token, tokenAmount);
                // Transfer LP token
                // We assume that LP tokens enabled in the protocol are safe by default
                // UniswapV2ERC20 realization has a standard transfer() function
                success = IERC20(token).transfer(to, tokenAmount);
                if (!success) {
                    revert TransferFailed(token, address(this), to, tokenAmount);
                }
            }  else {
                // Insufficient amount of LP tokens
                revert AmountLowerThan(tokenAmount, reserves);
            }
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
    ///#if_succeeds {:msg "we do not touch the owners balance" } old(ETHOwned) == ETHOwned;
    ///#if_succeeds {:msg "updated ETHFromServices"} accountRewards > 0 && ETHFromServices >= accountRewards ==> ETHFromServices == old(ETHFromServices) - accountRewards;
    ///#if_succeeds {:msg "unpaused"} paused == 1; 
    function withdrawToAccount(address account, uint256 accountRewards, uint256 accountTopUps) external
        returns (bool success)
    {
        // Check if the contract is paused
        if (paused == 2) {
            revert Paused();
        }

        // Check for the dispenser access
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }

        uint256 amountETHFromServices = ETHFromServices;
        // Send ETH rewards, if any
        if (accountRewards > 0 && (amountETHFromServices + 1) > accountRewards) {
            amountETHFromServices -= accountRewards;
            ETHFromServices = uint96(amountETHFromServices);
            (success, ) = account.call{value: accountRewards}("");
            if (!success) {
                revert TransferFailed(address(0), address(this), account, accountRewards);
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

        if (!mapEnabledTokens[token]) {
            mapEnabledTokens[token] = true;
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

        if (mapEnabledTokens[token]) {
            // The reserves of a token must be zero in order to disable it
            if (mapTokenReserves[token] > 0) {
                revert NonZeroValue();
            }
            mapEnabledTokens[token] = false;
            emit DisableToken(token);
        }
    }

    /// @dev Gets information about token being enabled for bonding.
    /// @param token Token address.
    /// @return enabled True if token is enabled.
    function isEnabled(address token) external view returns (bool enabled) {
        enabled = mapEnabledTokens[token];
    }

    /// @dev Re-balances treasury funds to account for the treasury reward for a specific epoch.
    /// @param treasuryRewards Treasury rewards.
    /// @return success True, if the function execution is successful.
    ///#if_succeeds {:msg "we do not touch the total eth balance" } old(address(this).balance) == address(this).balance;
    ///#if_succeeds {:msg "conservation law"} old(ETHFromServices+ETHOwned) == ETHFromServices+ETHOwned;
    ///#if_succeeds {:msg "unpaused"} paused == 1;
    function rebalanceTreasury(uint256 treasuryRewards) external returns (bool success) {
        // Check if the contract is paused
        if (paused == 2) {
            revert Paused();
        }

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
                emit UpdateTreasuryBalances(amountETHOwned, amountETHFromServices);
            } else {
                // There is not enough amount from services to allocate to the treasury
                success = false;
            }
        }
    }

    /// @dev Drains slashed funds from the service registry.
    /// @return amount Drained amount.
    ///#if_succeeds {:msg "correct update total eth balance" } old(address(this).balance) == address(this).balance-amount;
    ///#if_succeeds {:msg "conservation law"} old(ETHFromServices+ETHOwned) == ETHFromServices+ETHOwned-amount;
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

    /// @dev Pauses the contract.
    function pause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 2;
        emit PauseTreasury();
    }

    /// @dev Unpauses the contract.
    function unpause() external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = 1;
        emit UnpauseTreasury();
    }
}
