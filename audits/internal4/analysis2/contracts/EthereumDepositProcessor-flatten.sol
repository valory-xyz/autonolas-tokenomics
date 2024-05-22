// Sources flattened with hardhat v2.17.1 https://hardhat.org
// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.25;

interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IStaking {
    /// @dev Deposits OLAS tokens to the staking contract.
    /// @param amount OLAS amount.
    function deposit(uint256 amount) external;
}

interface IStakingFactory {
    /// @dev Verifies staking proxy instance and gets emissions amount.
    /// @param instance Staking proxy instance.
    /// @return amount Emissions amount.
    function verifyInstanceAndGetEmissionsAmount(address instance) external view returns (uint256 amount);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Target address returned zero emissions amount.
/// @param target Target address.
error TargetEmissionsZero(address target);

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @title EthereumDepositProcessor - Smart contract for processing tokens and data on L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract EthereumDepositProcessor {
    event AmountRefunded(address indexed target, uint256 refundAmount);
    event StakingTargetDeposited(address indexed target, uint256 amount);

    // OLAS address
    address public immutable olas;
    // Tokenomics dispenser address
    address public immutable dispenser;
    // Staking proxy factory address
    address public immutable stakingFactory;
    // OLAS address
    address public immutable timelock;
    // Reentrancy lock
    uint8 internal _locked;

    /// @dev EthereumDepositProcessor constructor.
    /// @param _olas OLAS token address.
    /// @param _dispenser Tokenomics dispenser address.
    /// @param _stakingFactory Service staking proxy factory address.
    /// @param _timelock DAO timelock address.
    constructor(address _olas, address _dispenser, address _stakingFactory, address _timelock) {
        // Check for zero addresses
        if (_olas == address(0) || _dispenser == address(0) || _stakingFactory == address(0) || _timelock == address(0)) {
            revert ZeroAddress();
        }

        olas = _olas;
        dispenser = _dispenser;
        stakingFactory = _stakingFactory;
        timelock = _timelock;
        _locked = 1;
    }

    /// @dev Deposits staking incentives for corresponding targets.
    /// @param targets Set of staking target addresses.
    /// @param stakingIncentives Corresponding set of staking incentives.
    function _deposit(address[] memory targets, uint256[] memory stakingIncentives) internal {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Traverse all the targets
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 amount = stakingIncentives[i];

            // Check the target validity address and staking parameters, and get emissions amount
            uint256 limitAmount = IStakingFactory(stakingFactory).verifyInstanceAndGetEmissionsAmount(target);

            // If the limit amount is zero, something is wrong with the target
            if (limitAmount == 0) {
                revert TargetEmissionsZero(target);
            }

            // Check the amount limit and adjust, if necessary
            if (amount > limitAmount) {
                uint256 refundAmount = amount - limitAmount;
                amount = limitAmount;

                // Send refund amount to the DAO address (timelock)
                IToken(olas).transfer(timelock, refundAmount);

                emit AmountRefunded(target, refundAmount);
            }

            // Approve the OLAS amount for the staking target
            IToken(olas).approve(target, amount);
            IStaking(target).deposit(amount);

            emit StakingTargetDeposited(target, amount);
        }

        _locked = 1;
    }

    /// @dev Deposits a single staking incentive for a corresponding target.
    /// @param target Staking target addresses.
    /// @param stakingIncentive Corresponding staking incentive.
    function sendMessage(
        address target,
        uint256 stakingIncentive,
        bytes memory,
        uint256
    ) external {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != dispenser) {
            revert ManagerOnly(dispenser, msg.sender);
        }

        // Construct one-element arrays from targets and amounts
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory stakingIncentives = new uint256[](1);
        stakingIncentives[0] = stakingIncentive;

        // Deposit OLAS to staking contracts
        _deposit(targets, stakingIncentives);
    }


    /// @dev Deposits a batch of staking incentives for corresponding targets.
    /// @param targets Set of staking target addresses.
    /// @param stakingIncentives Corresponding set of staking incentives.
    function sendMessageBatch(
        address[] memory targets,
        uint256[] memory stakingIncentives,
        bytes memory,
        uint256
    ) external {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != dispenser) {
            revert ManagerOnly(dispenser, msg.sender);
        }

        // Send the message to L2
        _deposit(targets, stakingIncentives);
    }

    /// @dev Gets the maximum number of token decimals able to be transferred across the bridge.
    /// @notice This function is implemented for the compatibility purposes only, as no cross-bridge is happening on L1.
    /// @return Number of supported decimals.
    function getBridgingDecimals() external pure returns (uint256) {
        return 18;
    }
}
