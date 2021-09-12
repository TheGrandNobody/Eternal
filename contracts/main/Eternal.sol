//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternal.sol";
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

    mapping ()
    // Keeps track of the reflection rate for a given address and gage to recalculate rewards earned during the gage
    mapping (address => mapping (uint256 => uint256)) reflectionRates;
    // Keeps track of the latest gage contract id with a certain entry deposit and risk
    // Using entry deposit 0 and risk 0 gives the absolute latest gage id
    mapping (uint256 => mapping(uint256 => uint256)) lastGage;

/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @dev Creates a standard n-holder gage contract with n users and adds the creator to it
     * @param users The desired number of users in the gage
     * @param asset The address of the asset deposited by the creator
     * @param amount The amount of ETRNL the creator will initially lock in the gage
     * @param risk The percentage of the initial amount the creator is willing to risk in the gage
     */
    function initiateStandardGage(uint256 users, address asset, uint256 amount, uint8 risk) external {
        
    }

    /**
        // Load the last gage with said amount and risk
        uint256 id = lastGage[amount][risk];

        // If the latest gage is unopen or user is already in it, create a new one 
        if (gage.status != Status.Open || inGage[user][id]) {
            // Update the absolute id counter and the specific amount-risk id counter
            lastGage[0][0] += 1;
            id = lastGage[0][0];
            lastGage[amount][risk] = id;
        }
        reflectionRates[user][id] = eternal.getReflectionRate();
     */

    /**
     * @dev Removes a given user from a given gage.
     * @param id The id of the specified gage contract
     * @param user The address of the specified user
     *
     * Requirements:
     *
     * - User must be in the gage
     * - User cannot be the winner of the gage
     */
    function removeUserFromGage(uint256 id, address user) external {
        // Compute any rewards accrued during the gage
        uint256 amount = computeAccruedRewards(gage.amount, user, id);
        // Users get the entire entry amount back if the gage wasn't active
        // Otherwise the systems substracts the loss incurred from forfeiting
        amount = (gage.status == Status.Open) ? amount : (amount - (gage.amount * gage.risk / 100));
        eternal.transfer(user, amount);
    }

    /**
     * @dev Claims the reward of a given user of a given gage.
     * @param id The id of the specified gage contract
     * @param user The address of the specified winner
     *
     * Requirements:
     *
     * - Selected gage status cannot be 'Open' or 'Active'
     * - Specified user must actually be the winning address of this gage
     */
    function claimReward(uint256 id, address user) external {
        Gage storage gage = gages[id];
        require(gage.status == Status.Closed, "Gage status is not 'Closed'");
        require(inGage[user][id], "User is not the winner");

        inGage[user][id] = false;

        // Compute any rewards accrued during the gage
        uint256 rewards = computeAccruedRewards(gage.amount, user, id);
        // Calculate the gage reward and add it to the redistribution reward (total reward)
        uint256 totalReward = rewards + (9 * gage.amount * gage.risk / 100);
        eternal.transfer(user, totalReward);

        emit UserRemoved(id, user);
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev View the latest gage id for a given entry deposit and risk. If not specified, view the absolute latest gage contract id.
     * @param amount The specified initial deposit of the gage
     * @param risk The specified risked percentage of the gage
     * @param absolute True if we want to view the absolute latest gage. False otherwise.
     * @return The latest gage id with specified entry deposit and risk. Otherwise the last created gage.
     */
    function viewLatestGage(uint256 amount, uint256 risk, bool absolute) external view returns (uint256) {
        return absolute ? lastGage[0][0] : lastGage[amount][risk];
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