// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./interfaces/IOLA.sol";
import "./interfaces/IServiceTokenomics.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IErrorsTokenomics.sol";
import "./interfaces/IStructsTokenomics.sol";
import "./interfaces/IVotingEscrow.sol";

/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract Tokenomics is IErrorsTokenomics, IStructsTokenomics, Ownable {
    using FixedPoint for *;

    event TreasuryUpdated(address treasury);
    event DepositoryUpdated(address depository);
    event DispenserUpdated(address dispenser);
    event VotingEscrowUpdated(address ve);
    event EpochLengthUpdated(uint256 epochLength);

    // OLA token address
    address public immutable ola;
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
    // ~120k of OLA tokens per epoch (the max cap is 20 million during 1st year, and the bonding fraction is 40%)
    uint256 public maxBond = 120_000 * 1e18;
    // TODO Decide which rate has to be put by default
    // Default epsilon rate that contributes to the interest rate: 50% or 0.5
    uint256 public epsilonRate = 5 * 1e17;

    // UCFc / UCFa weights for the UCF contribution
    uint256 public ucfcWeight = 1;
    uint256 public ucfaWeight = 1;
    // Component / agent weights for new valuable code
    uint256 public componentWeight = 1;
    uint256 public agentWeight = 1;
    // Number of valuable devs can be paid per units of capital per epoch
    uint256 public devsPerCapital = 1;
    // 10^(OLA decimals) that represent a whole unit in OLA token
    uint256 public immutable decimalsUnit;

    // Total service revenue per epoch: sum(r(s))
    uint256 public epochServiceRevenueETH;
    // Donation balance
    uint256 public donationBalanceETH;

    // Staking parameters with multiplying by 100
    // treasuryFraction (implicit, zero by default) + componentFraction + agentFraction + stakerFraction = 100%
    uint256 public stakerFraction = 50;
    uint256 public componentFraction = 33;
    uint256 public agentFraction = 17;
    // Top-up of OLA and bonding parameters with multiplying by 100
    uint256 public topUpOwnerFraction = 40;
    uint256 public topUpStakerFraction = 20;

    // Bond per epoch
    uint256 public bondPerEpoch;
    // MaxBond(e) - sum(BondingProgram) over all epochs: accumulates leftovers from previous epochs
    uint256 public effectiveBond = maxBond;
    // Manual or auto control of max bond
    bool public bondAutoControl;

    // Component Registry
    address public immutable componentRegistry;
    // Agent Registry
    address public immutable agentRegistry;
    // Service Registry
    address payable public immutable serviceRegistry;

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
    // Mapping of owner of component / agent address => top-up amount (in OLA)
    mapping(address => uint256) public mapOwnerTopUps;
    // Map of whitelisted service owners
    mapping(address => bool) private _mapServiceOwners;

    // TODO sync address constants with other contracts
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Max slippage 10000 = 100%
    uint256 public constant MAXSLIPPAGE = 10_000;

    constructor(address _ola, address _treasury, address _depository, address _dispenser, address _ve, uint256 _epochLen,
        address _componentRegistry, address _agentRegistry, address payable _serviceRegistry)
    {
        ola = _ola;
        treasury = _treasury;
        depository = _depository;
        dispenser = _dispenser;
        ve = _ve;
        epochLen = _epochLen;
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        serviceRegistry = _serviceRegistry;
        decimalsUnit = 10 ** IOLA(_ola).decimals();

        inflationCaps = new uint[](10);
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
    function changeManagers(address _treasury, address _depository, address _dispenser, address _ve) external onlyOwner {
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
    }

    /// @dev Gets the current epoch number.
    /// @return Current epoch number.
    function getCurrentEpoch() external view returns (uint256) {
        return epochCounter;
    }

    /// @dev Changes tokenomics parameters.
    /// @param _ucfcWeight UCFc weighs for the UCF contribution.
    /// @param _ucfaWeight UCFa weight for the UCF contribution.
    /// @param _componentWeight Component weight for new valuable code.
    /// @param _agentWeight Agent weight for new valuable code.
    /// @param _devsPerCapital Number of valuable devs can be paid per units of capital per epoch.
    /// @param _epsilonRate Epsilon rate that contributes to the interest rate value.
    /// @param _maxBond MaxBond OLA, 18 decimals.
    /// @param _epochLen New epoch length.
    /// @param _blockTimeETH Time between blocks for ETH.
    /// @param _bondAutoControl True to enable auto-tuning of max bonding value depending on the OLA remainder
    function changeTokenomicsParameters(
        uint256 _ucfcWeight,
        uint256 _ucfaWeight,
        uint256 _componentWeight,
        uint256 _agentWeight,
        uint256 _devsPerCapital,
        uint256 _epsilonRate,
        uint256 _maxBond,
        uint256 _epochLen,
        uint256 _blockTimeETH,
        bool _bondAutoControl
    ) external onlyOwner {
        ucfcWeight = _ucfcWeight;
        ucfaWeight = _ucfaWeight;
        componentWeight = _componentWeight;
        agentWeight = _agentWeight;
        devsPerCapital = _devsPerCapital;
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
    /// @param _topUpOwnerFraction Fraction for OLA top-up for component / agent owners.
    /// @param _topUpStakerFraction Fraction for OLA top-up for stakers.
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

        // Same check for OLA-related fractions
        if (_topUpOwnerFraction + _topUpStakerFraction > 100) {
            revert WrongAmount(_topUpOwnerFraction + _topUpStakerFraction, 100);
        }

        stakerFraction = _stakerFraction;
        componentFraction = _componentFraction;
        agentFraction = _agentFraction;

        topUpOwnerFraction = _topUpOwnerFraction;
        topUpStakerFraction = _topUpStakerFraction;
    }

    function changeServiceOwnerWhiteList(address[] memory accounts, bool[] memory permissions) external onlyOwner {
        uint256 numAccounts = accounts.length;
        // Check the array size
        if (permissions.length != numAccounts) {
            revert WrongArrayLength(numAccounts, permissions.length);
        }
        for (uint256 i = 0; i < numAccounts; ++i) {
            _mapServiceOwners[accounts[i]] = permissions[i];
        }
    }

    /// @dev Checks for the OLA minting ability WRT the inflation schedule.
    /// @param amount Amount of requested OLA tokens to mint.
    /// @return True if the mint is allowed.
    function isAllowedMint(uint256 amount) public returns (bool) {
        uint256 remainder = _getInflationRemainderForYear();
        // For the first 10 years we check the inflation cap that is pre-defined
        if (amount > remainder) {
            return false;
        }
        return true;
    }

    /// @dev Gets remainder of possible OLA allocation for the current year.
    /// @return remainder OLA amount possible to mint.
    function _getInflationRemainderForYear() public returns (uint256 remainder) {
        // OLA token time launch
        uint256 timeLaunch = IOLA(ola).timeLaunch();
        // One year of time
        uint256 oneYear = 1 days * 365;
        // Current year
        uint256 numYears = (block.timestamp - timeLaunch) / oneYear;
        // For the first 10 years we check the inflation cap that is pre-defined
        if (numYears < 10) {
            // OLA token supply to-date
            uint256 supply = IERC20(ola).totalSupply();
            remainder = inflationCaps[numYears] - supply;
        } else {
            remainder = IOLA(ola).inflationRemainder();
        }
    }

    /// @dev take into account the bonding program in this epoch. 
    /// @dev programs exceeding the limit in the epoch are not allowed
    function allowedNewBond(uint256 amount) external onlyDepository returns (bool)  {
        if(effectiveBond >= amount && isAllowedMint(amount)) {
            effectiveBond -= amount;
            return true;
        }
        return false;
    }

    /// @dev take into account materialization OLA per Depository.deposit() for currents program
    function usedBond(uint256 payout) external onlyDepository {
        bondPerEpoch += payout;
    }

    /// @dev Tracks the deposit token amount during the epoch.
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts) public onlyTreasury
        returns (uint256 revenueETH, uint256 donationETH)
    {
        // Loop over service Ids and track their amounts
        uint256 numServices = serviceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            // Check for the service Id existence
            if (!IServiceTokenomics(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }
            // Check for the whitelisted service owner
            address owner = IERC721Enumerable(serviceRegistry).ownerOf(serviceIds[i]);
            // If not, accept it as donation
            if (!_mapServiceOwners[owner]) {
                donationETH += amounts[i];
            } else {
                // Add a new service Id to the set of Ids if one was not currently in it
                if (mapServiceAmounts[serviceIds[i]] == 0) {
                    protocolServiceIds.push(serviceIds[i]);
                }
                mapServiceAmounts[serviceIds[i]] += amounts[i];
                revenueETH += amounts[i];
            }
        }
        // Increase the total service revenue per epoch and donation balance
        epochServiceRevenueETH += revenueETH;
        donationBalanceETH += donationETH;
    }

    /// @dev Calculates tokenomics for components / agents of protocol-owned services.
    /// @param registry Address of a component / agent registry contract.
    /// @param unitRewards Component / agent allocated rewards.
    /// @param unitTopUps Component / agent allocated top-ups.
    /// @return ucfu Calculated UCFc / UCFa.
    function _calculateUnitTokenomics(address registry, uint256 unitRewards, uint256 unitTopUps) private
        returns (PointUnits memory ucfu)
    {
        uint256 numServices = protocolServiceIds.length;

        // TODO Possible optimization is to store a set of componets / agents and the map of those used in protocol-owned services
        ucfu.numUnits = IERC721Enumerable(registry).totalSupply();
        // Set of agent revenues UCFu-s. Agent / component Ids start from "1", so the index can be equal to the set size
        uint256[] memory ucfuRevs = new uint256[](ucfu.numUnits + 1);
        // Set of agent revenues UCFu-s divided by the cardinality of agent Ids in each service
        uint256[] memory ucfus = new uint256[](numServices);
        // Overall profits of UCFu-s
        uint256 sumProfits = 0;

        // Loop over profitable service Ids to calculate initial UCFu-s
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = protocolServiceIds[i];
            uint256 numServiceUnits;
            uint256[] memory unitIds;
            if (registry == componentRegistry) {
                (numServiceUnits, unitIds) = IServiceTokenomics(serviceRegistry).getComponentIdsOfServiceId(serviceId);
            } else {
                (numServiceUnits, unitIds) = IServiceTokenomics(serviceRegistry).getAgentIdsOfServiceId(serviceId);
            }
            // Add to UCFa part for each agent Id
            uint256 amount = mapServiceAmounts[serviceId];
            for (uint256 j = 0; j < numServiceUnits; ++j) {
                // Sum the amounts for the corresponding components / agents
                ucfuRevs[unitIds[j]] += amount;
                sumProfits += amount;
            }
        }

        // Calculate all complete UCFu-s divided by the cardinality of agent Ids in each service
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = protocolServiceIds[i];
            uint256 numServiceUnits;
            uint256[] memory unitIds;
            if (registry == componentRegistry) {
                (numServiceUnits, unitIds) = IServiceTokenomics(serviceRegistry).getComponentIdsOfServiceId(serviceId);
            } else {
                (numServiceUnits, unitIds) = IServiceTokenomics(serviceRegistry).getAgentIdsOfServiceId(serviceId);
            }
            for (uint256 j = 0; j < numServiceUnits; ++j) {
                // Sum(UCFa[i]) / |As(epoch)|
                ucfus[i] += ucfuRevs[unitIds[j]];
            }
            ucfus[i] /= numServiceUnits;
        }

        // Calculate component / agent related values
        for (uint256 i = 0; i < ucfu.numUnits; ++i) {
            // Get the agent Id from the index list
            uint256 unitId = IERC721Enumerable(registry).tokenByIndex(i);
            if (ucfuRevs[unitId] > 0) {
                // Add address of a profitable component owner
                address owner = IERC721Enumerable(registry).ownerOf(unitId);
                // Increase a profitable agent number
                ++ucfu.numProfitableUnits;
                // Calculate agent rewards in ETH
                mapOwnerRewards[owner] += (unitRewards * ucfuRevs[unitId]) / sumProfits;
                // Calculate OLA top-ups
                uint256 amountOLA = (unitTopUps * ucfuRevs[unitId]) / sumProfits;
                if (registry == componentRegistry) {
                    amountOLA = (amountOLA * componentWeight) / (componentWeight + agentWeight);
                } else {
                    amountOLA = (amountOLA * agentWeight)  / (componentWeight + agentWeight);
                }
                mapOwnerTopUps[owner] += amountOLA;

                // Check if the component / agent is used for the first time
                if (registry == componentRegistry && !mapComponents[unitId]) {
                    ucfu.numNewUnits++;
                    mapComponents[unitId] = true;
                } else if (registry == agentRegistry && !mapAgents[unitId]){
                    ucfu.numNewUnits++;
                    mapAgents[unitId] = true;
                }
                // Check if the owner has introduced component / agent for the first time 
                if (!mapOwners[owner]) {
                    mapOwners[owner] = true;
                    ucfu.numNewOwners++;
                }
            }
        }

        // Calculate total UCFu
        for (uint256 i = 0; i < numServices; ++i) {
            ucfu.ucfuSum += ucfus[i];
        }
        // Record unit rewards
        ucfu.unitRewards = unitRewards;
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
        // New point can be calculated only if we passed number of blocks equal to the epoch length
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
    function getTopUpPerEpoch() public view returns (uint256 topUp) {
        topUp = (IOLA(ola).inflationRemainder() * epochLen * blockTimeETH) / (1 days * 365);
    }

    /// @dev Record global data to new checkpoint
    function _checkpoint() internal {
        // Get total amount of OLA as profits for rewards, and all the rewards categories
        // 0: total rewards, 1: treasuryRewards, 2: stakerRewards, 3: componentRewards, 4: agentRewards
        // 5: topUpOwnerFraction, 6: topUpStakerFraction, 7: bondFraction
        uint256[] memory rewards = new uint256[](8);
        rewards[0] = epochServiceRevenueETH;
        rewards[2] = rewards[0] * stakerFraction / 100;
        rewards[3] = rewards[0] * componentFraction / 100;
        rewards[4] = rewards[0] * agentFraction / 100;
        rewards[1] = rewards[0] - rewards[2] - rewards[3] - rewards[4];

        // Top-ups and bonding possibility in OLA are recalculated based on the inflation schedule per epoch
        uint256 totalTopUps = getTopUpPerEpoch();
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

        // df = 1/(1 + iterest_rate) by documantation, reverse_df = 1/df >= 1.0.
        uint256 df;
        // Calculate UCFc, UCFa, rewards allocated from them and DF
        PointUnits memory ucfc;
        PointUnits memory ucfa;
        if (rewards[0] > 0) {
            // Calculate total UCFc
            uint256 numComponents = IERC721Enumerable(componentRegistry).totalSupply();
            // TODO If there are no components, all their part of rewards go to treasury
            if (numComponents == 0) {
                rewards[1] += rewards[3];
            } else {
                ucfc = _calculateUnitTokenomics(componentRegistry, rewards[3], rewards[5]);
            }
            ucfc.ucfWeight = ucfcWeight;
            ucfc.unitWeight = componentWeight;

            // Calculate total UCFa
            ucfa = _calculateUnitTokenomics(agentRegistry, rewards[4], rewards[5]);
            ucfa.ucfWeight = ucfaWeight;
            ucfa.unitWeight = agentWeight;

            // Calculate DF from epsilon rate and f(K,D)
            uint256 codeUnits = componentWeight * ucfc.numNewUnits + agentWeight * ucfa.numNewUnits;
            uint256 newOwners = ucfc.numNewOwners + ucfa.numNewOwners;
            //  f(K(e), D(e)) = d * k * K(e) + d * D(e)
            // fKD = codeUnits * devsPerCapital * rewards[1] + codeUnits * newOwners;
            //  Convert amount of tokens with OLA decimals (18 by default) to fixed point x.x
            FixedPoint.uq112x112 memory fp1 = FixedPoint.fraction(rewards[1], decimalsUnit);
            // For consistency multiplication with fp1
            FixedPoint.uq112x112 memory fp2 = FixedPoint.fraction(codeUnits * devsPerCapital, 1);
            // fp1 == codeUnits * devsPerCapital * rewards[1]
            fp1 = fp1.muluq(fp2);
            // fp2 = codeUnits * newOwners
            fp2 = FixedPoint.fraction(codeUnits * newOwners, 1);
            // fp = codeUnits * devsPerCapital * rewards[1] + codeUnits * newOwners;
            FixedPoint.uq112x112 memory fp = _add(fp1, fp2);
            // 1/100 rational number
            FixedPoint.uq112x112 memory fp3 = FixedPoint.fraction(1, 100);
            // fp = fp/100 - calculate the final value in fixed point
            fp = fp.muluq(fp3);
            // fKD in the state that is comparable with epsilon rate
            uint256 fKD = fp._x / MAGIC_DENOMINATOR;

            // Compare with epsilon rate and choose the smallest one
            if (fKD > epsilonRate) {
                fKD = epsilonRate;
            }
            // 1 + fKD in the system where 1e18 is equal to a whole unit (18 decimals)
            df = 1e18 + fKD;
        }

        uint256 numServices = protocolServiceIds.length;
        PointEcomonics memory newPoint = PointEcomonics(ucfc, ucfa, df, numServices, rewards[1], rewards[2],
            donationBalanceETH, rewards[5], rewards[6], devsPerCapital, block.timestamp, block.number);
        mapEpochEconomics[epochCounter] = newPoint;
        epochCounter++;

        _clearEpochData();
    }

    /// @dev Calculates the amount of OLA tokens based on LP (see the doc for explanation of price computation). Any can do it
    /// @param token Token address.
    /// @param tokenAmount Token amount.
    /// @return amountOLA Resulting amount of OLA tokens.
    function calculatePayoutFromLP(address token, uint256 tokenAmount) external view returns (uint256 amountOLA)
    {
        PointEcomonics memory pe = mapEpochEconomics[epochCounter - 1];
        if(pe.df > 0) {
            amountOLA = _calculatePayoutFromLP(token, tokenAmount, pe.df);
        } else {
            // if df is undefined
            amountOLA = _calculatePayoutFromLP(token, tokenAmount, 1e18 + epsilonRate);
        }
    }

    /// @dev Get reserve OLA/totalSupply
    /// @param token Token address.
    /// @return priceLP Resulting reserveX/totalSupply ratio with 18 decimals
    function getCreatePrice(address token) public view
        returns (uint256 priceLP)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint112 reserve0;
        uint112 reserve1;
        // requires low gas
        (reserve0, reserve1,) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();
        // token0 != ola &&  token1 != ola, this should never happen
        if(token0 == ola ||  token1 == ola) {
            // if OLAS == token0 in pair then price0 = reserve0/totalSupply else price1 = reserve1/totalSupply
            FixedPoint.uq112x112 memory fp0 = (token0 == ola) ? FixedPoint.fraction(reserve0, totalSupply) : FixedPoint.fraction(reserve1, totalSupply);
            // for optimization - this number does not exceed type(uint224).max
            priceLP = fp0._x / MAGIC_DENOMINATOR;
        }
    }

    /// @dev reserve ratio in slippage range?
    /// @param token Token address.
    /// @param priceLP Reserve ration by create.
    /// @param slippage tolerance in reserve ratio %
    /// @return True if ok
    function slippageIsOK(address token, uint256 priceLP, uint256 slippage) external view returns (bool)
    {
        uint256 priceLPnow = getCreatePrice(token);
        uint256 delta = priceLP * slippage / 10000;
        // this should never happen
        if(priceLPnow == 0 || delta > priceLP) {
            return false;
        }
        uint256 maxRange = priceLP + delta;
        // always priceLP >= delta 
        uint256 minRange = priceLP - delta;
        if(priceLPnow > maxRange || priceLPnow < minRange) {
            return false;
        }
        return true;
    } 

    /// @dev Calculates the amount of OLA tokens based on LP (see the doc for explanation of price computation).
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param df Discount
    /// @return resAmount Resulting amount of OLA tokens.
    function _calculatePayoutFromLP(address token, uint256 amount, uint256 df) internal view
        returns (uint256 resAmount)
    {
        // Calculation of removeLiquidity
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint256 balance0 = IERC20(token0).balanceOf(address(pair));
        uint256 balance1 = IERC20(token1).balanceOf(address(pair));
        uint256 totalSupply = pair.totalSupply();

        // Using balances ensures pro-rate distribution
        uint256 amount0 = (amount * balance0) / totalSupply;
        uint256 amount1 = (amount * balance1) / totalSupply;

        require(balance0 > amount0, "UniswapV2: INSUFFICIENT_LIQUIDITY token0");
        require(balance1 > amount1, "UniswapV2: INSUFFICIENT_LIQUIDITY token1");

        // Get the initial OLA token amounts
        uint256 amountOLA = (token0 == ola) ? amount0 : amount1;
        uint256 amountPairForOLA = (token0 == ola) ? amount1 : amount0;

        // Calculate swap tokens from the LP back to the OLA token
        balance0 -= amount0;
        balance1 -= amount1;
        uint256 reserveIn = (token0 == ola) ? balance1 : balance0;
        uint256 reserveOut = (token0 == ola) ? balance0 : balance1;
        
        amountOLA = amountOLA + getAmountOut(amountPairForOLA, reserveIn, reserveOut);

        // Get the resulting amount in OLA tokens
        resAmount = (amountOLA * df) / 1e18; // df with decimals 18

        // The discounted amount cannot be smaller than the actual one
        if (resAmount < amountOLA) {
            revert AmountLowerThan(resAmount, amountOLA);
        }
    }

    // UniswapV2 https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // No license in file
    // forked for Solidity 8.x
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset

    /// @dev Gets the additional OLA amount from the LP pair token by swapping.
    /// @param amountIn Initial OLA token amount.
    /// @param reserveIn Token amount that is not OLA.
    /// @param reserveOut Token amount in OLA wit fees.
    /// @return amountOut Resulting OLA amount.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee / reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
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
    function getPoint(uint256 epoch) public view returns (PointEcomonics memory pe) {
        pe = mapEpochEconomics[epoch];
    }

    /// @dev Get last epoch Point.
    function getLastPoint() external view returns (PointEcomonics memory pe) {
        pe = mapEpochEconomics[epochCounter - 1];
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

    /// @dev Sums two fixed points.
    function _add(FixedPoint.uq112x112 memory x, FixedPoint.uq112x112 memory y) private pure
        returns (FixedPoint.uq112x112 memory r)
    {
        uint224 z = x._x + y._x;
        if(x._x > 0 && y._x > 0) assert(z > x._x && z > y._x);
        return FixedPoint.uq112x112(uint224(z));
    }

    /// @dev Calculated UCF of a specified epoch.
    /// @param epoch Epoch number.
    /// @return ucf UCF value.
    function getUCF(uint256 epoch) external view returns (FixedPoint.uq112x112 memory ucf) {
        PointEcomonics memory pe = mapEpochEconomics[epoch];

        // Total rewards per epoch
        uint256 totalRewards = pe.treasuryRewards + pe.stakerRewards + pe.ucfc.unitRewards + pe.ucfa.unitRewards;

        // Calculate UCFc
        uint256 denominator = totalRewards * pe.numServices * pe.ucfc.numUnits;
        FixedPoint.uq112x112 memory ucfc;
        // Number of components can be equal to zero for all the services, so the UCFc is just zero by default
        if (denominator > 0) {
            ucfc = FixedPoint.fraction(pe.ucfc.numProfitableUnits * pe.ucfc.ucfuSum, denominator);
        }

        // Calculate UCFa
        denominator = totalRewards * pe.numServices * pe.ucfa.numUnits;
        // Number of agents must always be greater than zero, since at least one agent is used by a service
        if (denominator == 0) {
            revert ZeroValue();
        }
        FixedPoint.uq112x112 memory ucfa = FixedPoint.fraction(pe.ucfa.numProfitableUnits * pe.ucfa.ucfuSum, denominator);

        // Calculate UCF
        denominator = pe.ucfc.ucfWeight + pe.ucfa.ucfWeight;
        if (denominator == 0) {
            revert ZeroValue();
        }
        FixedPoint.uq112x112 memory weightedUCFc = FixedPoint.fraction(pe.ucfc.ucfWeight, 1);
        FixedPoint.uq112x112 memory weightedUCFa = FixedPoint.fraction(pe.ucfa.ucfWeight, 1);
        weightedUCFc = ucfc.muluq(weightedUCFc);
        weightedUCFa = ucfa.muluq(weightedUCFa);
        ucf = _add(weightedUCFc, weightedUCFa);
        FixedPoint.uq112x112 memory fraction = FixedPoint.fraction(1, denominator);
        ucf = ucf.muluq(fraction);
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
