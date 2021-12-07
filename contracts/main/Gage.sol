//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IEternal.sol";
import "../interfaces/IGage.sol";

abstract contract Gage is Context, IGage {

    // Holds all possible statuses for a gage
    enum Status {
        Open,
        Active,
        Closed
    }

    // Holds user-specific information with regards to the gage
    struct UserData {
        address asset;                       // The AVAX address of the asset used as deposit     
        uint256 amount;                      // The entry deposit (in tokens) needed to participate in this gage        
        uint8 risk;                          // The percentage that is being risked in this gage  
        bool inGage;                         // Keeps track of whether the user is in the gage or not
    }

    // The eternal platform
    IEternal public eternal;                

    // Holds all users' information in the gage
    mapping (address => UserData) internal userData;

    // The id of the gage
    uint256 internal immutable id;  
    // The maximum number of users in the gage
    uint32 internal immutable  capacity; 
    // Keeps track of the number of users left in the gage
    uint32 internal users;
    // The state of the gage       
    Status internal status;
    // Determines whether the gage is a loyalty gage or not       
    bool private immutable loyalty;
    

    constructor (uint256 _id, uint32 _users, address _eternal, bool _loyalty) {
        require(users > 1, "Gage needs at least two users");
        id = _id;
        capacity = _users;
        eternal = IEternal(_eternal);
        loyalty = _loyalty;
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
    function viewGageUserCount() external view override returns (uint32) {
        require(status != Status.Active, "Gage can't be active");
        return users;
    }

    /**
     * @dev View the total user capacity of the gage
     * @return The total user capacity
     */
    function viewCapacity() external view override returns(uint256) {
        return capacity;
    }

    /**
     * @dev View the status of the gage
     * @return An integer indicating the status of the gage
     */
    function viewStatus() external view override returns (uint) {
        return uint(status);
    }

    /**
     * @dev View whether the gage is a loyalty gage or not
     * @return True if the gage is a loyalty gage, else false
     */
    function viewLoyalty() external view override returns (bool) {
        return loyalty;
    }

    /**
     * @dev View a given user's gage data 
     * @param user The address of the specified user
     * @return The asset, amount and risk for this user 
     */
    function viewUserData(address user) external view override returns (address, uint256, uint256){
        UserData storage data = userData[user];
        return (data.asset, data.amount, data.risk);
    }
}