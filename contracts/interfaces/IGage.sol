//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * @dev Gage interface
 * @author Nobody (me)
 * @notice Methods are used for all gage contracts
 */
interface IGage {
    // Signals the addition of a user to a specific gage (whilst gage is still 'Open')
    event UserAdded(uint256 id, address indexed user);
    // Signals the removal of a user from a specific gage (whilst gage is still 'Open')
    event UserRemoved(uint256 id, address indexed user);
    // Signals the transition from 'Open' to 'Active for a given gage
    event GageInitiated(uint256 id);
    // Signals the transition from 'Active' to 'Closed' for a given gage
    event GageClosed(uint256 id); 

    // Adds a user to the gage
    function join(address asset, uint256 amount, uint8 risk) external;
    // Removes a user from the gage
    function exit() external;
    // View the user count in the gage whilst it is not Active
    function viewGageUserCount() external view returns (uint32);
    // View the total user capacity of the gage
    function viewCapacity() external view returns (uint256);
    // View the gage's status
    function viewStatus() external view returns (uint);
    // View whether the gage is a loyalty gage or not
    function viewLoyalty() external view returns (bool);
    // View a given user's gage data
    function viewUserData(address user) external view returns (address, uint256, uint256);
}