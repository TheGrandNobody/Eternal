//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IEternal.sol";
import "../interfaces/IGage.sol";

contract Gage is Context, IGage {

    // Holds all possible statuses for a gage
    enum Status {
        Open,
        Active,
        Closed
    }

    struct UserData {
        address asset;                       // The AVAX address of the asset used as deposit       
        uint256 amount;                      // The entry deposit (in tokens) needed to participate in this gage        
        uint8 risk;                          // The percentage that is being risked in this gage  
        bool inGage;                         // Keeps track of whether the user is in the gage or not
    }

    IEternal public eternal;

    mapping (address => UserData) userData;

    // The id of the gage
    uint256 public immutable id;  
    // The maximum number of users in the gage
    uint32 public immutable  capacity; 
    // Keeps track of the number of users left in the gage
    uint32 private users;
    // The state of the gage       
    Status public status;         

    constructor (uint256 _id, uint32 _users) {
        id = _id;
        capacity = _users;
    }      

    /**
     * @dev Adds a stakeholder to this gage and records the initial data
     * @param asset The address of the asset used as deposit by this user
     * @param amount The user's chosen deposit amount 
     * @param risk The user's chosen risk percentage
     */
    function join(address asset, uint256 amount, uint8 risk) external override {
        require(risk <= 100, "Invalid risk percentage");
        UserData storage data = userData[_msgSender()];
        require(!data.inGage, "User is already in this gage");
        require(amount <= IERC20(asset).balanceOf(_msgSender()), "Deposit amount exceeds balance");

        data.amount = amount;
        data.asset = asset;
        data.risk = risk;
        data.inGage = true;
        // Add user to the gage
        users += 1;

        eternal.deposit(asset, _msgSender(), amount, id);

        // If contract is filled, update its status and initiate the gage
        if (users == 10) {
            status = Status.Active;
            emit GageInitiated(id);
        }
    }

    /**
     * @dev Removes a stakeholder from this gage
     */
    function exit() external override {
        UserData storage data = userData[_msgSender()];
        require(data.inGage, "User is not in this gage");
        
        // Remove user from the gage first (prevent re-entrancy)
        data.inGage = false;

        if (status != Status.Closed) {
            users -= 1;
            emit UserRemoved(id, _msgSender());
        }

        if (status == Status.Active && users == 1) {
            // If there is only one user left after this one has left, update the gage's status accordingly
            status = Status.Closed;
            emit GageClosed(id);
        }

        eternal.withdraw(_msgSender(), id);
    }

    /////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev View the number of stakeholders in the gage (if it isn't yet active)
     * @return The number of stakeholders in the selected gage
     *
     * Requirements:
     *
     * - Gage status cannot be 'Active'
     */
    function viewGageUserCount() external view returns (uint32) {
        require(status != Status.Active, "Gage can't be active");

        return users;
    }

    /**
     * @dev View the status of the gage
     * @return An integer indicating the status of the gage
     */
    function viewStatus() external view returns (uint) {
        return uint(status);
    }
}