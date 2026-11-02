// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Staking instance interface
interface IStaking {
    /// @dev Gets rewards per second.
    /// @return Rewards per second.
    function rewardsPerSecond() external view returns (uint256);

    /// @dev Gets maximum number of services.
    /// @return Maximum number of services.
    function maxNumServices() external view returns (uint256);

    /// @dev Gets time for emissions.
    /// @return Time for emissions.
    function timeForEmissions() external view returns (uint256);

    /// @dev Gets emissions amount.
    /// @return Emissions amount.
    function emissionsAmount() external view returns (uint256);

    /// @dev Gets service staking token.
    /// @return Service staking token address.
    function stakingToken() external view returns (address);

    /// @dev Gets service registry address.
    /// @return Service registry address.
    function serviceRegistry() external view returns(address);

    /// @dev Gets service registry token utility address.
    /// @return Service registry token utility address.
    function serviceRegistryTokenUtility() external view returns(address);

    /// @dev Minimum service staking deposit value required for staking.
    /// @return Minimum service staking deposit.
    function minStakingDeposit() external view returns(uint256);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev The deployed implementation must be a contract.
/// @param implementation Implementation address.
error ContractOnly(address implementation);

/// @title StakingVerifier - Smart contract for service staking contracts verification
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract StakingVerifier {
    event OwnerUpdated(address indexed owner);
    event SetImplementationsCheck(bool setCheck);
    event ImplementationsWhitelistUpdated(address[] implementations, bool[] statuses, bool setCheck);
    event StakingLimitsUpdated(uint256 minStakingDepositLimit, uint256 timeForEmissionsLimit, uint256 numServicesLimit,
        uint256 apyLimit);

    // One year constant
    uint256 public constant ONE_YEAR = 1 days * 365;
    // OLAS token address
    address public immutable olas;
    // Service registry address
    address public immutable serviceRegistry;
    // Service registry token utility
    address public immutable serviceRegistryTokenUtility;

    // Minimum staking deposit limit
    uint256 public minStakingDepositLimit;
    // Time for emissions limit
    uint256 public timeForEmissionsLimit;
    // Limit for the number of services
    uint256 public numServicesLimit;
    // APY limit in 1e18 format
    uint256 public apyLimit;
    // Contract owner address
    address public owner;
    // Flag to check for the implementation address whitelisting status
    bool public implementationsCheck;
    
    // Mapping implementation address => whitelisting status
    mapping(address => bool) public mapImplementations;

    /// @dev StakingVerifier constructor.
    /// @param _olas OLAS token address.
    /// @param _serviceRegistry Service registry address.
    /// @param _serviceRegistryTokenUtility Service registry token utility address.
    /// @param _minStakingDepositLimit Minimum staking deposit limit.
    /// @param _timeForEmissionsLimit Time for emissions limit.
    /// @param _numServicesLimit Limit for the number of services.
    /// @param _apyLimit APY limit in 1e18 format.
    constructor(
        address _olas,
        address _serviceRegistry,
        address _serviceRegistryTokenUtility,
        uint256 _minStakingDepositLimit,
        uint256 _timeForEmissionsLimit,
        uint256 _numServicesLimit,
        uint256 _apyLimit
    ) {
        // Zero address check
        if (_olas == address(0) || _serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        // Zero values check
        if (_minStakingDepositLimit == 0 || _timeForEmissionsLimit == 0 || _numServicesLimit == 0 || _apyLimit == 0) {
            revert ZeroValue();
        }

        owner = msg.sender;
        olas = _olas;
        serviceRegistry = _serviceRegistry;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
        minStakingDepositLimit = _minStakingDepositLimit;
        timeForEmissionsLimit = _timeForEmissionsLimit;
        numServicesLimit = _numServicesLimit;
        apyLimit = _apyLimit;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        // Check for the ownership
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

    /// @dev Controls the necessity of checking implementation whitelisting statuses.
    /// @param setCheck True if the whitelisting check is needed, and false otherwise.
    function setImplementationsCheck(bool setCheck) external {
        // Check the contract ownership
        if (owner != msg.sender) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Set the implementations check requirement
        implementationsCheck = setCheck;
        emit SetImplementationsCheck(setCheck);
    }

    /// @dev Controls implementations whitelisting statuses.
    /// @notice Implementation is considered whitelisted if the global status is set to true.
    /// @notice Implementations check could be set to false even though (some) implementations are set to true.
    ///         This is the owner responsibility how to manage the whitelisting logic.
    /// @param implementations Set of implementation addresses.
    /// @param statuses Set of whitelisting statuses.
    /// @param setCheck True if the whitelisting check is needed, and false otherwise.
    function setImplementationsStatuses(
        address[] memory implementations,
        bool[] memory statuses,
        bool setCheck
    ) external {
        // Check the contract ownership
        if (owner != msg.sender) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Check for the array length and that they are not empty
        if (implementations.length == 0 || implementations.length != statuses.length) {
            revert WrongArrayLength(implementations.length, statuses.length);
        }

        // Set the implementations address check requirement
        implementationsCheck = setCheck;

        // Set implementations whitelisting status
        for (uint256 i = 0; i < implementations.length; ++i) {
            // Check for the zero address
            if (implementations[i] == address(0)) {
                revert ZeroAddress();
            }
            
            // Set the operator whitelisting status
            mapImplementations[implementations[i]] = statuses[i];
        }

        emit ImplementationsWhitelistUpdated(implementations, statuses, setCheck);
    }

    /// @dev Verifies a service staking implementation contract.
    /// @param implementation Service staking implementation contract address.
    /// @return True, if verification is successful.
    function verifyImplementation(address implementation) external view returns (bool){
        // Check the operator whitelisting status, if the whitelisting check is set
        if (implementationsCheck) {
            return mapImplementations[implementation];
        }

        return true;
    }

    /// @dev Verifies a service staking proxy instance.
    /// @param instance Service staking proxy instance.
    /// @param implementation Service staking implementation.
    /// @return True, if verification is successful.
    function verifyInstance(address instance, address implementation) external view returns (bool) {
        // If the implementations check is true, and the implementation is not whitelisted, the verification is failed
        if (implementationsCheck && !mapImplementations[implementation]) {
            return false;
        }

        // Check that instance is the contract when it is not checked against the implementation
        if (instance.code.length == 0) {
            return false;
        }

        // Check service registry
        // This is a mandatory check since all the services were created by a service registry contract
        bytes memory registryData = abi.encodeCall(IStaking.serviceRegistry, ());
        (bool success, bytes memory returnData) = instance.staticcall(registryData);

        // Check the returnData if the call was successful
        // The returned size must be 32 to fit one address
        if (success && returnData.length == 32) {
            address registry = abi.decode(returnData, (address));
            if (registry != serviceRegistry) {
                return false;
            }
        } else {
            return false;
        }

        // Check for minimum staking deposit
        // This lets the verifier limit the max stake per slot for risk mitigation
        uint256 minStakingDeposit = IStaking(instance).minStakingDeposit();
        if (minStakingDeposit > minStakingDepositLimit) {
            return false;
        }

        // Calculate rewards per year
        uint256 rewardsPerYear = IStaking(instance).rewardsPerSecond() * ONE_YEAR;
        // Calculate current APY in 1e18 format
        uint256 apy = (rewardsPerYear * 1e18) / minStakingDeposit;

        // Check for APY
        // This lets the verifier limit the max APY a staking contract offers
        // The DAO can this way express an upper bound on the APY staking contracts can offer
        if (apy > apyLimit) {
            return false;
        }

        // Check for time for emissions
        // This lets the verifier enforce an upper bound on the emissions length for risk mitigation
        uint256 timeForEmissions = IStaking(instance).timeForEmissions();
        if (timeForEmissions > timeForEmissionsLimit) {
            return false;
        }

        // Check for the number of services
        // This is a must have parameter for all staking contracts
        uint256 numServices = IStaking(instance).maxNumServices();
        if (numServices > numServicesLimit) {
            return false;
        }

        address token;
        // Check staking token
        // This is an optional check since there could be staking contracts with native tokens
        bytes memory tokenData = abi.encodeCall(IStaking.stakingToken, ());
        (success, returnData) = instance.staticcall(tokenData);

        // Check the returnData is the call was successful
        if (success) {
            // The returned size must be 32 to fit one address
            if (returnData.length == 32) {
                token = abi.decode(returnData, (address));
                if (token != olas) {
                    return false;
                }
            } else {
                return false;
            }
        }

        // Check service registry token utility if the staking token non zero
        if (token != address(0) && serviceRegistryTokenUtility != address(0)) {
            registryData = abi.encodeCall(IStaking.serviceRegistryTokenUtility, ());
            (success, returnData) = instance.staticcall(registryData);

            // Check the returnData if the call was successful
            // The returned size must be 32 to fit one address
            if (success && returnData.length == 32) {
                address registry = abi.decode(returnData, (address));
                if (registry != serviceRegistryTokenUtility) {
                    return false;
                }
            } else {
                return false;
            }
        }

        return true;
    }

    /// @dev Changes staking parameter limits.
    /// @param _minStakingDepositLimit Minimum staking deposit limit.
    /// @param _timeForEmissionsLimit Time for emissions limit.
    /// @param _numServicesLimit Limit for the number of services.
    /// @param _apyLimit APY limit in 1e18 format.
    function changeStakingLimits(
        uint256 _minStakingDepositLimit,
        uint256 _timeForEmissionsLimit,
        uint256 _numServicesLimit,
        uint256 _apyLimit
    ) external {
        // Check the contract ownership
        if (owner != msg.sender) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Zero values check
        if (_minStakingDepositLimit == 0 || _timeForEmissionsLimit == 0 || _numServicesLimit == 0 || _apyLimit == 0) {
            revert ZeroValue();
        }

        minStakingDepositLimit = _minStakingDepositLimit;
        timeForEmissionsLimit = _timeForEmissionsLimit;
        numServicesLimit = _numServicesLimit;
        apyLimit = _apyLimit;

        emit StakingLimitsUpdated(_minStakingDepositLimit, _timeForEmissionsLimit, _numServicesLimit, _apyLimit);
    }

    /// @dev Gets emissions amount limit for a specific staking proxy instance.
    /// @param instance Staking proxy instance.
    /// @return amount Emissions amount limit.
    function getEmissionsAmountLimit(address instance) external view returns (uint256 amount) {
        // Get calculated emissions amount from the instance
        amount = IStaking(instance).emissionsAmount();
    }
}