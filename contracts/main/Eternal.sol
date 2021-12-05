//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

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

    constructor (address _eternal) {
        // Initialize the ETRNL interface
        eternal = IEternalToken(_eternal);
        // Set initial feeRate
        feeRate = 500;
    }

    // The ETRNL interface
    IEternalToken private immutable eternal;

    // Keeps track of the respective gage tied to any given ID
    mapping (uint256 => address) private gages;
    // Keeps track of the reflection rate for any given address and gage to recalculate rewards earned during the gage
    mapping (address => mapping (uint256 => uint256)) private reflectionRates;

    // Keeps track of the latest Gage ID
    uint256 public lastId;
    // The (percentage) fee rate applied to any gage-reward computations not using ETRNL
    uint16 public feeRate;

/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @dev Creates a liquid gage contract for a user
     * @param user The address of the user entering
     * @param percent The percent change condition of the liquid gage
     * @param inflationary Whether the gage is inflationary or deflationary
     */
    function initiateLiquidGage(address user, bool inflationary) external override returns(uint256) {
        uint256 percent; 
        lastId += 1;
        Gage newGage = new LoyaltyGage(lastId, percent, 2, inflationary, address(this), user, address(this));
        gages[lastId] = address(newGage);
        emit NewGage(lastId, address(newGage));

        return lastId;
    }

    /**
     * @dev Transfers a given user's gage funds to storage or further processing depending on the type of the gage
     */
    function deposit(address asset, address user, uint256 amount, uint256 id) external override {
        if (asset == address(eternal)) {
            reflectionRates[user][id] = eternal.getReflectionRate();
        }
        IERC20(asset).transferFrom(user, address(this), amount);
    }

    /**
     * @dev Withdraws a given user's gage return
     * @param id The id of the specified gage contract
     * @param user The address of the specified user
     * @param winner Whether the gage closed in favor of this user
     */
    function withdraw(address user, uint256 id, bool winner) external override {
        require(_msgSender() == gages[id], "msg.sender must be the gage");
        IGageV2 gage = IGageV2(gages[id]);
        (address asset, uint256 amount, uint256 risk) = gage.viewUserData(user);

        // Compute the amount minus the fee rate if using ETRNL
        uint256 netAmount;
        if (asset == address(eternal)) {
            netAmount = amount - (amount * eternal.viewTotalRate() / 100000);
        } else {
            netAmount = amount - (amount * feeRate / 100000);
            IERC20(asset).transfer(fund(), (amount * feeRate / 100000));
        }
        // Compute any rewards accrued during the gage
        uint256 finalAmount = computeAccruedRewards(netAmount, user, id);
        /** Users get the entire entry amount back if the gage wasn't active at the time of departure.
            If the user forfeited, the system substracts the loss incurred. 
            Otherwise, the gage return is awarded to the winner. */
        if (!winner) {
            finalAmount -= (finalAmount * risk / 100);
            if (gage.viewLoyalty()) {
                if (user == gage.viewReceiver()) {
                    (,uint256 otherAmount, uint256 otherRisk) = gage.viewUserData(gage.viewDistributor());

                }
            }
        } else {
            finalAmount += (gage.viewCapacity() - 1) * finalAmount * risk / 100;
            if (gage.viewLoyalty()) {
            
            }
        }
        IERC20(asset).transfer(user, finalAmount);
    }

/////–––««« Fund-only functions »»»––––\\\\\

    /**
     * @dev Sets the fee rate value that is applied to assets other than ETRNL.
     * @param newRate The new specified fee rate
     */
    function setFeeRate(uint16 newRate) external override onlyFund() {
        uint16 oldRate = feeRate;
        feeRate  = newRate;
        emit FeeRateChanged(oldRate, newRate);
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