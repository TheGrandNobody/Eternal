//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IEternalToken.sol";
import "./Gage.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody (me)
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract Eternal is Context, IEternal {

    constructor (address _eternal) {
        // Initialize the ETRNL interface
        eternal = IEternalToken(_eternal);
    }

    // The ETRNL interface
    IEternalToken private immutable eternal;

    // Keeps track of the respective gage tied to any given ID
    mapping (uint256 => Gage) gages;
    // Keeps track of the reflection rate for a given address and gage to recalculate rewards earned during the gage
    mapping (address => mapping (uint256 => uint256)) reflectionRates;

    // Keeps track of the latest Gage ID
    uint256 lastId;

/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @dev Creates a standard n-holder gage contract with n users
     * @param users The desired number of users in the gage
     */
    function initiateStandardGage(uint32 users) external {
        lastId += 1;
        Gage newGage = new Gage(lastId, users);
        gages[lastId] = newGage;
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
     *
     */
    function withdraw(uint256 id, address user) external {
        Gage gage = gages[id];
        (address asset, uint256 amount, uint256 risk) = gage.viewUserData(user);

        // Compute any rewards accrued during the gage
        uint256 finalAmount = computeAccruedRewards(amount, user, id);
        // Users get the entire entry amount back if the gage wasn't active
        // Otherwise the systems substracts the loss incurred from forfeiting
        finalAmount = gage.viewStatus() == 0 ? finalAmount : (gage.viewStatus() == 1 ? (finalAmount - (amount * risk / 100)) : (finalAmount + ((gage.viewCapacity()-1) * amount * risk / 100)));
        IERC20(asset).transfer(user, finalAmount);
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

        return (amount * (currentRate / oldRate));
    }
}