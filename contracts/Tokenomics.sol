// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/IOLAS.sol";
import "./interfaces/IServiceTokenomics.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IVotingEscrow.sol";

// TODO: Optimize structs together with its variable sizes
// Structure for component / agent tokenomics-related statistics
struct PointUnits {
    // Total absolute number of components / agents
    uint256 numUnits;
    // Number of components / agents that were part of profitable services
    uint256 numProfitableUnits;
    // Allocated rewards for components / agents
    uint256 unitRewards;
    // Cumulative UCFc-s / UCFa-s
    uint256 ucfuSum;
    // Coefficient weight of units for the final UCF formula, set by the government
    uint256 ucfWeight;
    // Number of new units
    uint256 numNewUnits;
    // Number of new owners
    uint256 numNewOwners;
    // Component / agent weight for new valuable code
    uint256 unitWeight;
}

// Structure for tokenomics
struct PointEcomonics {
    // UCFc
    PointUnits ucfc;
    // UCFa
    PointUnits ucfa;
    // Discount factor
    uint256 df;
    // Profitable number of services
    uint256 numServices;
    // Treasury rewards
    uint256 treasuryRewards;
    // Staking rewards
    uint256 stakerRewards;
    // Donation in ETH
    uint256 totalDonationETH;
    // Top-ups for component / agent owners
    uint256 ownerTopUps;
    // Top-ups for stakers
    uint256 stakerTopUps;
    // Timestamp
    uint256 ts;
    // Block number
    uint256 blockNumber;
}

/// @dev Interface for contribution measures.
interface IContributionMeasures {
    /// @dev Gets tokenomics contributions.
    /// @param protocolServiceIds Set of protocol-owned services in current epoch.
    /// @param treasuryRewards Treasury rewards.
    /// @param componentRewards Component rewards.
    /// @param agentRewards Agent rewards.
    function getContributions(
        uint256[] memory protocolServiceIds,
        uint256 treasuryRewards,
        uint256 componentRewards,
        uint256 agentRewards
    ) external returns (PointUnits memory ucfc, PointUnits memory ucfa, uint256 fKD);

    /// @dev Calculates UCF of by specified epoch point parameters.
    /// @param pe Epoch point.
    /// @return ucf UCF value.
    function getUCF(PointEcomonics memory pe) external view returns (uint256  ucf);
}

/// @title Tokenomics - Smart contract for key tokenomics parameters
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Tokenomics is IErrorsTokenomics, Ownable {
    using FixedPoint for *;

    event TreasuryUpdated(address treasury);
    event DepositoryUpdated(address depository);
    event DispenserUpdated(address dispenser);
    event VotingEscrowUpdated(address ve);
    event EpochLengthUpdated(uint256 epochLength);

    // OLAS token address
    address public immutable olas;
    // Treasury contract address
    address public treasury;
    // Depository contract address
    address public depository;
    // Dispenser contract address
    address public dispenser;
    // Voting Escrow address
    address public ve;

    // Epoch length in block numbers
    uint256 public epochLen;
    // Global epoch counter
    uint256 public epochCounter = 1;
    // ETH average block time
    uint256 public blockTimeETH = 14;
    // source: https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27 
    // 2^(112 - log2(1e18))
    uint256 public constant MAGIC_DENOMINATOR =  5192296858534816;
    // ~120k of OLAS tokens per epoch (the max cap is 20 million during 1st year, and the bonding fraction is 40%)
    uint256 public maxBond = 120_000 * 1e18;
    // TODO Decide which rate has to be put by default
    // Default epsilon rate that contributes to the interest rate: 50% or 0.5
    uint256 public epsilonRate = 5 * 1e17;

    // Total service revenue per epoch: sum(r(s))
    uint256 public epochServiceRevenueETH;
    // Donation balance
    uint256 public donationBalanceETH;

    // Staking parameters with multiplying by 100
    // treasuryFraction (implicit, zero by default) + componentFraction + agentFraction + stakerFraction = 100%
    uint256 public stakerFraction = 50;
    uint256 public componentFraction = 33;
    uint256 public agentFraction = 17;
    // Top-up of OLAS and bonding parameters with multiplying by 100
    uint256 public topUpOwnerFraction = 40;
    uint256 public topUpStakerFraction = 20;

    // Bond per epoch
    uint256 public bondPerEpoch;
    // MaxBond(e) - sum(BondingProgram) over all epochs: accumulates leftovers from previous epochs
    uint256 public effectiveBond = maxBond;
    // Manual or auto control of max bond
    bool public bondAutoControl;

    // Service Registry address
    // TODO: Debate if this must be mutable for cases when serviceRegistry changes
    address public immutable serviceRegistry;
    // Contribution Measures address
    address public contributionMeasures;

    // Inflation caps for the first ten years
    uint256[] public inflationCaps;
    // Set of protocol-owned services in current epoch
    uint256[] public protocolServiceIds;
    // Mapping of epoch => point
    mapping(uint256 => PointEcomonics) public mapEpochEconomics;
    // Map of component Ids that contribute to protocol owned services
    mapping(uint256 => bool) public mapComponents;
    // Map of agent Ids that contribute to protocol owned services
    mapping(uint256 => bool) public mapAgents;
    // Mapping of owner of component / agent addresses that create them
    mapping(address => bool) public mapOwners;
    // Map of service Ids and their amounts in current epoch
    mapping(uint256 => uint256) public mapServiceAmounts;
    // Mapping of owner of component / agent address => reward amount (in ETH)
    mapping(address => uint256) public mapOwnerRewards;
    // Mapping of owner of component / agent address => top-up amount (in OLAS)
    mapping(address => uint256) public mapOwnerTopUps;
    // Map of protocol-owned service Ids
    mapping(uint256 => bool) public mapProtocolServices;

    /// @dev Tokenomics constructor.
    /// @param _olas OLAS token address.
    /// @param _treasury Treasury address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    /// @param _ve Voting Escrow address.
    /// @param _epochLen Epoch length.
    /// @param _serviceRegistry Service Registry address.
    /// @param _contributionMeasures Contribution Measures address.
    constructor(address _olas, address _treasury, address _depository, address _dispenser, address _ve, uint256 _epochLen,
        address _serviceRegistry, address _contributionMeasures)
    {
        olas = _olas;
        treasury = _treasury;
        depository = _depository;
        dispenser = _dispenser;
        ve = _ve;
        epochLen = _epochLen;
        serviceRegistry = _serviceRegistry;
        contributionMeasures = _contributionMeasures;

        inflationCaps = new uint256[](10);
        inflationCaps[0] = 520_000_000e18;
        inflationCaps[1] = 590_000_000e18;
        inflationCaps[2] = 660_000_000e18;
        inflationCaps[3] = 730_000_000e18;
        inflationCaps[4] = 790_000_000e18;
        inflationCaps[5] = 840_000_000e18;
        inflationCaps[6] = 890_000_000e18;
        inflationCaps[7] = 930_000_000e18;
        inflationCaps[8] = 970_000_000e18;
        inflationCaps[9] = 1_000_000_000e18;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyTreasury() {
        if (treasury != msg.sender) {
            revert ManagerOnly(msg.sender, treasury);
        }
        _;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyDepository() {
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }
        _;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyDispenser() {
        if (dispenser != msg.sender) {
            revert ManagerOnly(msg.sender, dispenser);
        }
        _;
    }

    /// @dev Changes various managing contract addresses.
    /// @param _treasury Treasury address.
    /// @param _depository Depository address.
    /// @param _dispenser Dispenser address.
    /// @param _ve Voting Escrow address.
    /// @param _contributionMeasures Contribution Measures address.
    function changeManagers(address _treasury, address _depository, address _dispenser, address _ve,
        address _contributionMeasures) external onlyOwner
    {
        if (_treasury != address(0)) {
            treasury = _treasury;
            emit TreasuryUpdated(_treasury);
        }
        if (_depository != address(0)) {
            depository = _depository;
            emit DepositoryUpdated(_depository);
        }
        if (_dispenser != address(0)) {
            dispenser = _dispenser;
            emit DispenserUpdated(_dispenser);
        }
        if (_ve != address(0)) {
            ve = _ve;
            emit VotingEscrowUpdated(_ve);
        }
        if (_contributionMeasures != address(0)) {
            contributionMeasures = _contributionMeasures;
        }
    }

    /// @dev Changes tokenomics parameters.
    /// @param _epsilonRate Epsilon rate that contributes to the interest rate value.
    /// @param _maxBond MaxBond OLAS, 18 decimals.
    /// @param _epochLen New epoch length.
    /// @param _blockTimeETH Time between blocks for ETH.
    /// @param _bondAutoControl True to enable auto-tuning of max bonding value depending on the OLAS remainder
    function changeTokenomicsParameters(
        uint256 _epsilonRate,
        uint256 _maxBond,
        uint256 _epochLen,
        uint256 _blockTimeETH,
        bool _bondAutoControl
    ) external onlyOwner {
        epsilonRate = _epsilonRate;
        // take into account the change during the epoch
        _adjustMaxBond(_maxBond);
        epochLen = _epochLen;
        blockTimeETH = _blockTimeETH;
        bondAutoControl = _bondAutoControl;
    }

    /// @dev Sets staking parameters in fractions of distributed rewards.
    /// @param _stakerFraction Fraction for stakers.
    /// @param _componentFraction Fraction for component owners.
    /// @param _agentFraction Fraction for agent owners.
    /// @param _topUpOwnerFraction Fraction for OLAS top-up for component / agent owners.
    /// @param _topUpStakerFraction Fraction for OLAS top-up for stakers.
    function changeRewardFraction(
        uint256 _stakerFraction,
        uint256 _componentFraction,
        uint256 _agentFraction,
        uint256 _topUpOwnerFraction,
        uint256 _topUpStakerFraction
    ) external onlyOwner {
        // Check that the sum of fractions is 100%
        if (_stakerFraction + _componentFraction + _agentFraction > 100) {
            revert WrongAmount(_stakerFraction + _componentFraction + _agentFraction, 100);
        }

        // Same check for OLAS-related fractions
        if (_topUpOwnerFraction + _topUpStakerFraction > 100) {
            revert WrongAmount(_topUpOwnerFraction + _topUpStakerFraction, 100);
        }

        stakerFraction = _stakerFraction;
        componentFraction = _componentFraction;
        agentFraction = _agentFraction;

        topUpOwnerFraction = _topUpOwnerFraction;
        topUpStakerFraction = _topUpStakerFraction;
    }

    // TODO Think of a possibility to have a round-up map like Gnosis Safe stores owners. Otherwise it would be difficult to track the list of whitelisted service Ids
    /// @dev (De-)whitelists protocol-owned services.
    /// @param serviceIds Set of service Ids.
    /// @param permissions Set of corresponding permissions for each account address.
    function changeProtocolServicesWhiteList(uint256[] memory serviceIds, bool[] memory permissions) external onlyOwner {
        uint256 numServices = serviceIds.length;
        // Check the array size
        if (permissions.length != numServices) {
            revert WrongArrayLength(numServices, permissions.length);
        }
        for (uint256 i = 0; i < numServices; ++i) {
            if (!IServiceTokenomics(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }
            mapProtocolServices[serviceIds[i]] = permissions[i];
        }
    }

    /// @dev Checks for the OLAS minting ability WRT the inflation schedule.
    /// @param amount Amount of requested OLAS tokens to mint.
    /// @return allowed True if the mint is allowed.
    function isAllowedMint(uint256 amount) external returns (bool allowed) {
        uint256 remainder = _getInflationRemainderForYear();
        // For the first 10 years we check the inflation cap that is pre-defined
        if (amount < (remainder + 1)) {
            allowed = true;
        }
    }

    /// @dev Gets remainder of possible OLAS allocation for the current year.
    /// @return remainder OLAS amount possible to mint.
    function _getInflationRemainderForYear() internal returns (uint256 remainder) {
        // OLAS token time launch
        uint256 timeLaunch = IOLAS(olas).timeLaunch();
        // One year of time
        uint256 oneYear = 1 days * 365;
        // Current year
        uint256 numYears = (block.timestamp - timeLaunch) / oneYear;
        // For the first 10 years we check the inflation cap that is pre-defined
        if (numYears < 10) {
            // OLAS token supply to-date
            uint256 supply = IToken(olas).totalSupply();
            remainder = inflationCaps[numYears] - supply;
        } else {
            remainder = IOLAS(olas).inflationRemainder();
        }
    }

    /// @dev Checks if the the effective bond value per current epoch is enough to allocate the specific amount.
    /// @notice Programs exceeding the limit in the epoch are not allowed.
    /// @param amount Requested amount for the bond program.
    /// @return True if effective bond threshold is not reached.
    function allowedNewBond(uint256 amount) external onlyDepository returns (bool)  {
        uint256 remainder = _getInflationRemainderForYear();
        if (effectiveBond >= amount && amount < (remainder + 1)) {
            effectiveBond -= amount;
            return true;
        }
        return false;
    }

    /// @dev Increases the bond per epoch with the OLAS payout for a Depository program
    /// @param payout Payout amount for the LP pair.
    function usedBond(uint256 payout) external onlyDepository {
        bondPerEpoch += payout;
    }

    /// @dev Tracks the deposited ETH amounts from services during the current epoch.
    /// @notice This function is only called by the treasury where the validity of arrays and values has been performed.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) external onlyTreasury
        returns (uint256 revenueETH, uint256 donationETH)
    {
        // Loop over service Ids and track their amounts
        uint256 numServices = serviceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            // Check for the service Id existence
            if (!IServiceTokenomics(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }
            // Check for the whitelisted services
            if (mapProtocolServices[serviceIds[i]]) {
                // If this is a protocol-owned service, accept funds as revenue
                // Add a new service Id to the set of Ids if one was not currently in it
                if (mapServiceAmounts[serviceIds[i]] == 0) {
                    protocolServiceIds.push(serviceIds[i]);
                }
                mapServiceAmounts[serviceIds[i]] += amounts[i];
                revenueETH += amounts[i];
            } else {
                // If the service is not a protocol-owned one, accept funds as donation
                donationETH += amounts[i];
            }
        }
        // Increase the total service revenue per epoch and donation balance
        epochServiceRevenueETH += revenueETH;
        donationBalanceETH += donationETH;
    }

    /// @dev Clears necessary data structures for the next epoch.
    function _clearEpochData() internal {
        uint256 numServices = protocolServiceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            delete mapServiceAmounts[protocolServiceIds[i]];
        }
        delete protocolServiceIds;
        epochServiceRevenueETH = 0;
    }

    /// @dev Record global data to the checkpoint
    function checkpoint() external onlyTreasury {
        PointEcomonics memory lastPoint = mapEpochEconomics[epochCounter - 1];
        // New point can be calculated only if we passed the number of blocks equal to the epoch length
        if (block.number > lastPoint.blockNumber) {
            uint256 diffNumBlocks = block.number - lastPoint.blockNumber;
            if (diffNumBlocks >= epochLen) {
                _checkpoint();
            }
        }
    }

    /// @dev Adjusts max bond every epoch if max bond is contract-controlled.
    function _adjustMaxBond(uint256 _maxBond) internal {
        // take into account the change during the epoch
        if(_maxBond > maxBond) {
            uint256 delta = _maxBond - maxBond;
            effectiveBond += delta;
        }
        if(_maxBond < maxBond) {
            uint256 delta = maxBond - _maxBond;
            if(delta < effectiveBond) {
                effectiveBond -= delta;
            } else {
                effectiveBond = 0;
            }
        }
        maxBond = _maxBond;
    }

    /// @dev Gets top-up value for epoch.
    /// @return topUp Top-up value.
    function getTopUpPerEpoch() external view returns (uint256 topUp) {
        topUp = (IOLAS(olas).inflationRemainder() * epochLen * blockTimeETH) / (1 days * 365);
    }

    /// @dev Record global data to new checkpoint
    function _checkpoint() internal {
        // TODO Need to check for the condition of epochServiceRevenueETH == 0?
        // Get total amount of OLAS as profits for rewards, and all the rewards categories
        // 0: total rewards, 1: treasuryRewards, 2: stakerRewards, 3: componentRewards, 4: agentRewards
        // 5: topUpOwnerFraction, 6: topUpStakerFraction, 7: bondFraction
        uint256[] memory rewards = new uint256[](8);
        rewards[0] = epochServiceRevenueETH;
        rewards[2] = rewards[0] * stakerFraction / 100;
        rewards[3] = rewards[0] * componentFraction / 100;
        rewards[4] = rewards[0] * agentFraction / 100;
        rewards[1] = rewards[0] - rewards[2] - rewards[3] - rewards[4];

        // Top-ups and bonding possibility in OLAS are recalculated based on the inflation schedule per epoch
        uint256 totalTopUps = (IOLAS(olas).inflationRemainder() * epochLen * blockTimeETH) / (1 days * 365);
        rewards[5] = totalTopUps * topUpOwnerFraction / 100;
        rewards[6] = totalTopUps * topUpStakerFraction / 100;
        rewards[7] = totalTopUps - rewards[5] - rewards[6];

        // Effective bond accumulates leftovers from previous epochs (with last max bond value set)
        if (maxBond > bondPerEpoch) {
            effectiveBond += maxBond - bondPerEpoch;
        }
        // Bond per epoch starts from zero every epoch
        bondPerEpoch = 0;
        // Adjust max bond and effective bond if contract-controlled max bond is enabled
        if (bondAutoControl) {
            _adjustMaxBond(rewards[7]);
        }

        // df = 1/(1 + interest_rate) by documentation, reverse_df = 1/df >= 1.0.
        uint256 df;
        // Calculate UCFc, UCFa, rewards allocated from them and DF
        PointUnits memory ucfc;
        PointUnits memory ucfa;
        if (rewards[0] > 0) {
            // fKD in the state that is comparable with epsilon rate
            uint256 fKD;
            (ucfc, ucfa, fKD) = IContributionMeasures(contributionMeasures).getContributions(protocolServiceIds,
                rewards[1], rewards[4], rewards[5]);

            // Compare with epsilon rate and choose the smallest one
            if (fKD > epsilonRate) {
                fKD = epsilonRate;
            }
            // 1 + fKD in the system where 1e18 is equal to a whole unit (18 decimals)
            df = 1e18 + fKD;
        }

        uint256 numServices = protocolServiceIds.length;
        // TODO Double check parameters we need to put into the struct. Do we need devsPerCapital?
        PointEcomonics memory newPoint = PointEcomonics(ucfc, ucfa, df, numServices, rewards[1], rewards[2],
            donationBalanceETH, rewards[5], rewards[6], block.timestamp, block.number);
        mapEpochEconomics[epochCounter] = newPoint;
        epochCounter++;

        _clearEpochData();
    }

    // TODO: Specify the doc mentioned below
    /// @dev Calculates the amount of OLAS tokens based on LP (see the doc for explanation of price computation).
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutFromLP(uint256 tokenAmount, uint256 priceLP) external view
        returns (uint256 amountOLAS)
    {
        PointEcomonics memory pe = mapEpochEconomics[epochCounter - 1];
        if(pe.df > 0) {
            amountOLAS = (tokenAmount * priceLP * pe.df) / 1e18;
        } else {
            // if df is undefined
            amountOLAS = (tokenAmount * priceLP * (1e18 + epsilonRate)) / 1e18;
        }
    }

    /// @dev Get reserve OLAS / totalSupply.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX/totalSupply ratio with 18 decimals
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply > 0) {
            address token0 = pair.token0();
            address token1 = pair.token1();
            uint112 reserve0;
            uint112 reserve1;
            // requires low gas
            (reserve0, reserve1, ) = pair.getReserves();
            // token0 != olas && token1 != olas, this should never happen
            if (token0 == olas || token1 == olas) {
                priceLP = (token0 == olas) ? reserve0 / totalSupply : reserve1 / totalSupply;
            }
        }
    }

    /// @dev Calculates staking rewards.
    /// @param account Account address.
    /// @param startEpochNumber Epoch number at which the reward starts being calculated.
    /// @return reward Reward amount up to the last possible epoch.
    /// @return topUp Top-up amount up to the last possible epoch.
    /// @return endEpochNumber Epoch number where the reward calculation will start the next time.
    function calculateStakingRewards(address account, uint256 startEpochNumber) external view
        returns (uint256 reward, uint256 topUp, uint256 endEpochNumber)
    {
        // There is no reward in the first epoch yet
        if (startEpochNumber < 2) {
            startEpochNumber = 2;
        }

        for (endEpochNumber = startEpochNumber; endEpochNumber < epochCounter; ++endEpochNumber) {
            // Epoch point where the current epoch info is recorded
            PointEcomonics memory pe = mapEpochEconomics[endEpochNumber];
            // Last block number of a previous epoch
            uint256 iBlock = mapEpochEconomics[endEpochNumber - 1].blockNumber - 1;
            // Get account's balance at the end of epoch
            uint256 balance = IVotingEscrow(ve).balanceOfAt(account, iBlock);

            // If there was no locking / staking, we skip the reward computation
            if (balance > 0) {
                // Get the total supply at the last block of the epoch
                uint256 supply = IVotingEscrow(ve).totalSupplyAt(iBlock);

                // Add to the reward depending on the staker reward
                if (supply > 0) {
                    reward += balance * pe.stakerRewards / supply;
                    topUp += balance * pe.stakerTopUps / supply;
                }
            }
        }
    }

    /// @dev get Point by epoch
    /// @param epoch number of a epoch
    /// @return pe raw point
    function getPoint(uint256 epoch) external view returns (PointEcomonics memory pe) {
        pe = mapEpochEconomics[epoch];
    }

    /// @dev Gets last epoch Point.
    function getLastPoint() external view returns (PointEcomonics memory pe) {
        pe = mapEpochEconomics[epochCounter - 1];
    }

    /// @dev Gets rewards data of the last epoch.
    /// @return treasuryRewards Treasury rewards.
    /// @return accountRewards Cumulative staker, component and agent rewards.
    /// @return accountTopUps Cumulative staker, component and agent top-ups.
    function getRewardsData() external view
        returns (uint256 treasuryRewards, uint256 accountRewards, uint256 accountTopUps)
    {
        PointEcomonics memory pe = mapEpochEconomics[epochCounter - 1];
        treasuryRewards = pe.treasuryRewards;
        accountRewards = pe.stakerRewards + pe.ucfc.unitRewards + pe.ucfa.unitRewards;
        accountTopUps = pe.ownerTopUps + pe.stakerTopUps;
    }

    /// @dev Gets discount factor.
    /// @param epoch Epoch number.
    /// @return df Discount factor.
    function getDF(uint256 epoch) external view returns (uint256 df)
    {
        PointEcomonics memory pe = mapEpochEconomics[epoch];
        if (pe.df > 0) {
            df = pe.df;
        } else {
            df = 1e18 + epsilonRate;
        }
    }

    /// @dev Calculates UCF of a specified epoch.
    /// @param epoch Epoch number.
    /// @return ucf UCF value.
    function getUCF(uint256 epoch) external view returns (uint256 ucf) {
        PointEcomonics memory pe = mapEpochEconomics[epoch];
        ucf = IContributionMeasures(contributionMeasures).getUCF(pe);
    }

    /// @dev Gets the component / agent owner reward.
    /// @param account Account address.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function getOwnerRewards(address account) external view returns (uint256 reward, uint256 topUp) {
        reward = mapOwnerRewards[account];
        topUp = mapOwnerTopUps[account];
    }

    /// @dev Gets the component / agent owner reward and zeros the record of it being written off.
    /// @param account Account address.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerRewards(address account) external onlyDispenser returns (uint256 reward, uint256 topUp) {
        reward = mapOwnerRewards[account];
        topUp = mapOwnerTopUps[account];
        mapOwnerRewards[account] = 0;
        mapOwnerTopUps[account] = 0;
    }
}    
