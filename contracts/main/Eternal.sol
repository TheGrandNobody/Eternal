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
    function deposit(address asset, address user, uint256 amount, uint256 id) external {
        if (asset == address(eternal)) {
            reflectionRates[user][id] = eternal.getReflectionRate();
        }
        IERC20(asset).transferFrom(user, address(this), amount);
    }

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