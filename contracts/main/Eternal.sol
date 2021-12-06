//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/IEternalToken.sol";
import "../interfaces/IGageV2.sol";
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
    // Keeps track of the respective gage tied to any given ID
    mapping (uint256 => address) private gages;
    // Keeps track of the reflection rate for any given address and gage to recalculate rewards earned during the gage
    mapping (address => mapping (uint256 => uint256)) private reflectionRates;

    // Keeps track of the latest Gage ID
    uint256 private lastId;
    // The holding time-constant used in the percent change condition calculation (decided by the Eternal Fund) (x 10 ** 6)
    uint256 private timeConstant;
    // The (percentage) fee rate applied to any gage-reward computations not using ETRNL (x 10 ** 5)
    uint256 private feeRate;

    constructor (address _eternal) {
        // Initialize the ETRNL interface
        eternal = IEternalToken(_eternal);
        // Set initial feeRate
        feeRate = 500;
        // Set initial timeConstant
        timeConstant = 2 * (10 ** 6);
    }

/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @dev Creates an ETRNL liquid gage contract for a user
     */
    function initiateEternalLiquidGage() external override returns(uint256) {
        uint256 alpha = eternal.viewAlpha() > 0 ? eternal.viewAlpha() : 1000;
        // Compute the percent change condition
        uint256 percent = (eternal.viewBurnRate() * alpha * (10 ** 9) * timeConstant * 15) / eternal.totalSupply();

        // Incremement the lastId tracker
        lastId += 1;

        // Deploy a new Gage
        Gage newGage = new LoyaltyGage(lastId, percent, 2, true, address(this), _msgSender(), address(this));
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
    function deposit(address asset, address user, uint256 amount, uint256 id) external override {
        require(_msgSender() == gages[id], "msg.sender must be the gage");
        if (asset == address(eternal)) {
            reflectionRates[user][id] = eternal.getReflectionRate();
        }
        require(IERC20(asset).transferFrom(user, address(this), amount), "Failed to deposit asset");
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
        IGageV2 gage = IGageV2(gages[id]);
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
     * @dev Sets the time-constant value used in the percent change condition calculation for any loyalty gage
     * @param newConstant The value of the new time-constant
     */
    function setTimeConstant(uint256 newConstant) external override onlyFund() {
        uint256 oldConstant = timeConstant;
        emit TimeConstantUpdated(oldConstant, newConstant);
        timeConstant = newConstant;
    }

/////–––««« Utility functions »»»––––\\\\\

    /**
     * @dev Calculates any redistribution rewards accrued during a given gage a given user participated in.
     * @param amount The specified entry deposit
     * @param user The address of the user who we calculate rewards for
     * @param id The id of the specified gage
     */
    function computeAccruedRewards(uint256 amount, address user, uint256 id) private view returns (uint256) {
        uint256 oldRate = reflectionRates[user][id];
        uint256 currentRate = eternal.isExcludedFromReward(user) ? oldRate : eternal.getReflectionRate();

        return (amount * (oldRate / currentRate));
    }

    function viewGageAddress(uint256 id) external view returns(address) {
        return gages[id];
    }
}