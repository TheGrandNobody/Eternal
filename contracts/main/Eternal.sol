//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalTreasury.sol";
import "../interfaces/ILoyaltyGage.sol";
import "./LoyaltyGage.sol";
import "../inheritances/OwnableEnhanced.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody (me)
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract Eternal is IEternal, OwnableEnhanced {

    // The ETRNL interface
    IEternalToken private immutable eternal;
    // The Treasury interface
    IEternalTreasury private immutable treasury;
    // Keeps track of the respective gage tied to any given ID
    mapping (uint256 => address) private gages;
    // Keeps track of the reflection rate for any given address and gage to recalculate rewards earned during the gage
    mapping (uint256 => uint256) private reflectionRates;
    mapping (address => mapping (address => bool)) private inLiquidGage;

    // Keeps track of the latest Gage ID
    uint256 private lastId;
    // The holding time constant used in the percent change condition calculation (decided by the Eternal Fund) (x 10 ** 6)
    uint256 private timeConstant;
    // The risk constant used in the calculation of the treasury's risk (x 10 ** 4)
    uint256 private riskConstant;
    // The minimum token value estimate of transactions in 24h, used in case the alpha value is not determined yet
    uint256 private baseline;
    // The (percentage) fee rate applied to any gage-reward computations not using ETRNL (x 10 ** 5)
    uint256 private feeRate;
    // The total number of active liquid gages
    uint256 private totalLiquidGages;
    // The number of liquid gages that can possibly be active at a time
    uint256 private liquidGageLimit;

    constructor (address _eternal, address _treasury) {
        // Initialize the interfaces
        eternal = IEternalToken(_eternal);
        treasury = IEternalTreasury(_treasury);
        // Set initial feeRate
        feeRate = 500;
        // Set initial constants
        timeConstant = 2 * (10 ** 6);
        riskConstant = 100;
        // Set initial baseline
        baseline = 10 ** 6;
    }
/////–––««« Variable state-inspection functions »»»––––\\\\\
    
    /**
     * @dev View the corresponding address for a given gage id
     * @param id The id of the specified gage
     * @return The address of the specified gage
     */
    function viewGageAddress(uint256 id) external view override returns(address) {
        return gages[id];
    }

    /**
     * @dev Returns the address of the Eternal token
     * @return The address of ETRNL
     */
    function viewETRNL() external view override returns (address) {
        return address(eternal);
    }
/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @dev Creates an ETRNL liquid gage contract for a user
     */
    function initiateEternalLiquidGage(address asset) external override returns(uint256) {
        require(totalLiquidGages < liquidGageLimit, "Liquid gage limit is reached");
        require(!inLiquidGage[_msgSender()][asset], "Per-asset gaging limit reached");
        // Compute the percent change condition
        uint256 alpha = eternal.viewAlpha() > 0 ? eternal.viewAlpha() : baseline;
        uint256 percent = eternal.viewBurnRate() * alpha * (10 ** 9) * timeConstant * 15 / eternal.totalSupply();

        // Incremement the lastId tracker and the number of active liquid gages
        lastId += 1;
        totalLiquidGages += 1;

        // Deploy a new Gage
        Gage newGage = new LoyaltyGage(lastId, percent, 2, false, address(treasury), _msgSender(), address(this));
        emit NewGage(lastId, address(newGage));
        gages[lastId] = address(newGage);

        return lastId;
    }

    /**
     * @dev Transfers a given user's gage funds to storage or further processing depending on the type of the gage
     * @param asset The address of the user's asset being deposited
     * @param user The address of the user
     * @param amount The quantity of the deposited asset
     * @param id The id of the gage
     *
     * Requirements:
     * - Only callable by a gage contract
     */
    function deposit(address asset, address user, uint256 amount, uint256 id, uint256 risk) external override {
        require(_msgSender() == gages[id], "msg.sender must be the gage");
        reflectionRates[id] = eternal.getReflectionRate();
        require(IERC20(asset).transferFrom(user, address(treasury), amount), "Failed to deposit asset");
        uint256 treasuryRisk = risk + riskConstant;
        treasury.fundGage(gages[id], user, asset, amount, treasuryRisk, risk);
    }

    /**
     * @dev Withdraws a given user's gage return
     * @param id The id of the specified gage contract
     * @param user The address of the specified user
     * @param winner Whether the gage closed in favor of this user
     *
     * Requirements:
     * - Only callable by a gage contract
     */
    function withdraw(address user, uint256 id, bool winner) external override {
        require(_msgSender() == gages[id], "msg.sender must be the gage");
        ILoyaltyGage gage = ILoyaltyGage(gages[id]);
        (address asset, uint256 amount, uint256 risk) = gage.viewUserData(user);

        // Compute the amount minus the fee rate if using ETRNL
        uint256 netAmount;
        uint256 rewards;

        if (asset == address(eternal)) {
            netAmount = amount - (amount * eternal.viewTotalRate() / 100000);
            netAmount = computeAccruedRewards(amount, user, id);
        } else {
            netAmount = amount - (amount * feeRate / 100000);
            require(IERC20(asset).transfer(fund(), (amount * feeRate / 100000)), "Failed to take gaging fee");
        }

        /** Users get the entire entry amount back if the gage wasn't active at the time of departure.
            If the user forfeited, the system substracts the loss incurred. 
            Otherwise, the gage return is awarded to the winner. */
        if (!winner) {
            netAmount -= (netAmount * risk / 100);
            if (gage.viewLoyalty()) {
            }
        } else {
            netAmount += (gage.viewCapacity() - 1) * netAmount * risk / 100;
            if (gage.viewLoyalty()) {
            
            }
        }
        require(IERC20(asset).transfer(user, netAmount), "Failed to withdraw deposit");
    }

/////–––««« Fund-only functions »»»––––\\\\\

    /**
     * @dev Sets the fee rate value that is applied to assets other than ETRNL.
     * @param newRate The new specified fee rate
     */
    function setFeeRate(uint256 newRate) external override onlyFund() {
        uint256 oldRate = feeRate;
        emit FeeRateUpdated(oldRate, newRate);
        feeRate  = newRate;
    }

    /**
     * @dev Sets the time constant value used in the percent change condition calculation for any loyalty gage
     * @param newConstant The value of the new time constant
     *
     * Requirements:
     * - Time constant must be greater than 0
     */
    function setTimeConstant(uint256 newConstant) external override onlyFund() {
        require(timeConstant > 0, "Time constant must be positive");
        uint256 oldConstant = timeConstant;
        emit TimeConstantUpdated(oldConstant, newConstant);
        timeConstant = newConstant;
    }

    /**
     * @dev Sets the risk constant used in the calculation of the treasury's risk
     * @param newConstant The value of the new risk constant
     *
     * Requirements:
     * - Risk constant must be greater than 0
     * - Risk constant must be less than or equal to 1 (x 10 ** 4) (equivalent to < 100%)
     */
    function setRiskConstant(uint256 newConstant) external override onlyFund() {
        require(riskConstant > 0 && riskConstant <= 10 ** 4, "Invalid risk constant value");
        uint256 oldConstant = riskConstant;
        emit RiskConstantUpdated(oldConstant, newConstant);
        riskConstant = newConstant;
    }

    /**
     * @dev Sets the minimum estimate of tokens transacted in a span of 24h
     * @param newBaseline The value of the new baseline
     * 
     * Requirements:
     * - Baseline must be greater than or equal to 1000
     */
    function setBaseline(uint256 newBaseline) external override onlyFund() {
        require(baseline >= 10 ** 3, "Baseline is below threshold");
        uint256 oldBaseline = baseline;
        emit BaselineUpdated(oldBaseline, newBaseline);
        baseline = newBaseline;
    }

    function 

/////–––««« Utility functions »»»––––\\\\\

    /**
     * @dev Calculates any redistribution rewards accrued during a given gage a given user participated in.
     * @param amount The specified entry deposit
     * @param user The address of the user who we calculate rewards for
     * @param id The id of the specified gage
     */
    function computeAccruedRewards(uint256 amount, address user, uint256 id) private view returns (uint256) {
        uint256 oldRate = reflectionRates[id];
        uint256 currentRate = eternal.isExcludedFromReward(user) ? oldRate : eternal.getReflectionRate();

        return (amount * (oldRate / currentRate));
    }
}