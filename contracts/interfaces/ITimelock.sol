//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Timelock interface
 * @author Nobody (me)
 * @notice Methods are used for all timelock-related functions
 */
interface ITimelock {
    // View the amount of time that a proposal must remain in queue
    function viewDelay() external view returns (uint256);
    // View the amount of time give to a proposal to be executed
    function viewGracePeriod() external pure returns (uint256);
    // View the address of the contract in line to be the next Eternal Fund
    function viewPendingFund() external view returns (address);
    // View the current Eternal Fund address
    function viewFund() external view returns (address);
    // View whether a given transaction hash is currently in queue
    function queuedTransaction(bytes32 hash) external view returns (bool);
    // Accepts the offer of becoming the Eternal Fund
    function acceptFund() external;
    // Queues all of a proposal's actions
    function queueTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external returns (bytes32);
    // Cancels all of a proposal's actions
    function cancelTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external;
    // Executes all of a proposal's actions
    function executeTransaction(address target, uint256 value, string calldata signature, bytes calldata data, uint256 eta) external payable returns (bytes memory);

    // Signals a transfer of admin roles
    event NewAdmin(address indexed newAdmin);
    // Signals the role of admin being offered to an individual
    event NewPendingAdmin(address indexed newPendingAdmin);
    // Signals an update of the minimum amount of time a proposal must wait before being queued
    event NewDelay(uint256 indexed newDelay);
    // Signals a proposal being canceled
    event CancelTransaction(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);
    // Signals a proposal being executed
    event ExecuteTransaction(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);
    // Signals a proposal being queued
    event QueueTransaction(bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 eta);
}