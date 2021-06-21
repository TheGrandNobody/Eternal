//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IEternalToken.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody (me)
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract Eternal is Context {

    constructor (address eternalToken) {
        // Initialize the ETRNL interface
        eternal = IEternalToken(eternalToken);

        // The gage with ID 0 must have status closed for this contract to function
        Gage storage gage =  gages[0];
        gage.status = Status.Closed;
    }

    // Holds all possible statuses for a gage
    enum Status {
        Open,
        Active,
        Closed
    }

    // Defines a Gage Contract
    struct Gage {
        uint256 id;            // The id of the gage
        Status status;         // The status of the gage
        uint64 amount;         // The entry deposit of ETRNL needed to participate in this gage
        uint8 users;           // The current number of users participating in this gage
        uint8 risk;            // The percentage that is being risked in this gage
    }

    // The ETRNL interface
    IEternalToken private eternal;

    // Keeps track of all gage contracts
    mapping (uint256 => Gage) gages;
    // Keeps track of whether a user is participating in a specific gage
    mapping (address => mapping(uint256 => bool)) inGage;
    // Keeps track of the latest gage contract id with a certain entry deposit and risk
    // Using entry deposit 0 and risk 0 gives the absolute latest gage id
    mapping (uint64 => mapping(uint8 => uint256)) lastGage;

    // Signals the addition of a user to a specific gage (whilst gage is still 'Open')
    event UserAdded(uint256 id, address indexed user);
    // Signals the removal of a user from a specific gage (whilst gage is still 'Open')
    event UserRemoved(uint256 id, address indexed user);
    // Signals the transition from 'Open' to 'Active for a given gage
    event GageInitiated(uint256 id, uint64 amount, uint8 risk);
    // Signals the transition from 'Active' to 'Closed' for a given gage
    event GageClosed(uint256 id, uint64 amount, uint8 risk);

/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @dev Adds a given user to an available gage contract with a given entry deposit, risk percentage and capacity
     * @param user The address of the specified user
     * @param amount The amount of ETRNL the user will initially lock in the gage
     * @param risk The percentage of the initial amount the user is willing to risk in the gage
     */
    function assignUserToGage(address user, uint64 amount, uint8 risk) external {
        // Load the last gage with said amount and risk
        uint256 id = lastGage[amount][risk];
        Gage storage gage = gages[id];
        
        // If the latest gage is unopen or user is already in it, create a new one 
        if (gage.status != Status.Open || inGage[user][id]) {
            // Update the absolute id-tracker and specific amount-risk id-tracker
            lastGage[0][0] += 1;
            id = lastGage[0][0];
            lastGage[amount][risk] = id;
            // Save the gage parameters
            gage = gages[id];
            gage.amount = amount;
            gage.risk = risk;
            gage.id = id;
        }

        // Add user to the gage
        inGage[user][id] = true;
        gage.users += 1;
        eternal.transferFrom(user, address(this), amount * 10**9);
        emit UserAdded(id, user);

        // If contract is filled, update its status and initiate the gage
        if (gage.users == 10) {
            gage.status = Status.Active;
            emit GageInitiated(id, amount, risk);
        }
    }

    /**
     * @dev Removes a given user from a given gage
     * @param id The id of the specified gage contract
     * @param user The address of the specified user
     *
     * Requirements:
     *
     * - User must be in the gage
     * - User cannot be the winner of the gage
     */
    function removeUserFromGage(uint256 id, address user) external {
        require(inGage[user][id], "User is not in this gage");
        Gage storage gage = gages[id];
        require(gage.status != Status.Closed, "Winner can't leave a closed gage");

        // Remove user from the gage first (prevent re-entrancy)
        inGage[user][id] = false;
        gage.users -= 1;

        if (gage.status == Status.Open) {
            emit UserRemoved(id, user);
        } else if (gage.status == Status.Active && gage.users == 1) {
            // If there is only one user left after this one has left, update the gage's status accordingly
            gage.status = Status.Closed;
            emit GageClosed(id, gage.amount, gage.risk);
        }

        // Compute the amount minus the loss incurred from forfeiting
        uint256 netAmount = gage.amount - (gage.amount * gage.risk / 100);
        // Users get the entire entry amount back if the gage wasn't active
        uint256 amount = gage.status == Status.Open ? gage.amount : netAmount;
        eternal.transfer(user, amount * 10**9);
    }

    /**
     * @dev Claims the reward for a given user of a given gage
     * @param id The id of the specified gage contract
     * @param user The address of the specified winner
     * @return True if the procedure goes to completion
     */
    function claimRewardFor(uint256 id, address user) external returns (bool) {
        _claimReward(id, user);
        return true;
    }

    /**
     * @dev Claims the reward of a given gage
     * @param id The id of the specified gage contract
     * @return True if the procedure goes to completion
     */
    function claimRewardSelf(uint256 id) external returns (bool) {
        _claimReward(id, _msgSender());
        return true;
    }

    /**
     * @dev Claims the reward of a given user of a given gage
     * @param id The id of the specified gage contract
     * @param user The address of the specified winner
     * 
     * Requirements:
     *
     * - Selected gage status cannot be 'Open' or 'Active'
     * - User must actually be the winner of this gage
     */
    function _claimReward(uint256 id, address user) private {
        Gage storage gage = gages[id];
        require(gage.status == Status.Closed, "Gage status is not 'Closed'");
        require(inGage[user][id], "User is not the winner");

        inGage[user][id] = false;
        uint256 reward = gage.amount + (gage.amount * 9 * gage.risk / 100);
        eternal.transfer(user, reward);
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev View the number of stakeholders in a given gage that is still forming
     * @param id The id of the specified gage contract
     * @return The number of stakeholders in the selected gage
     *
     * Requirements:
     *
     * - Gage status cannot be 'Active'
     */
    function viewGageUserCount(uint256 id) external view returns (uint8) {
        Gage storage gage = gages[id];
        require(gage.status != Status.Active, "Gage can't be active");
        return gage.users;
    }

    /**
     * @dev View the latest gage id for a given entry deposit and risk. If not specified, view the absolute latest gage contract id.
     * @param amount The specified initial deposit of the gage
     * @param risk The specified risked percentage of the gage
     * @param absolute True if we want to view the absolute latest gage. False otherwise.
     * @return The latest gage id with specified entry deposit and risk. Otherwise the last created gage.
     */
    function viewLatestGage(uint64 amount, uint8 risk, bool absolute) external view returns (uint256) {
        return absolute ? lastGage[0][0] : lastGage[amount][risk];
    }
}