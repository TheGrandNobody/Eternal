//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./governance/OwnableEnhanced.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract EternalV0 is OwnableEnhanced {

    enum Status {
        Open,
        Active,
        Closed
    }

    struct GagePool {
        uint256 id;            // The id of the pool
        uint24 entryDeposit;   // The amount of ETRNL needed to participate in this pool
        uint8 users;           // The current number of users participating in this pool
        uint8 risk;            // The percentage that is being risked in this pool
        Status status;         // The status of the pool
    }

    mapping (uint256 => GagePool) pools;
    mapping (address => mapping(uint256 => bool)) inPool;
    mapping (uint256 => mapping(uint256 => uint256)) lastPools;

    event UserAdded(uint256 id, address indexed user);
    event UserRemoved(uint256 id, address indexed user);
    event GageInitiated(uint256 id, uint256 amount, uint256 risk);
    event GageClosed(uint256 id, uint256 amount, uint256 risk);


    function assignUserToPool(address user, uint256 amount, uint256 risk) external {

        // Load the last pool with said amount and risk
        uint256 id = lastPools[amount][risk];
        GagePool storage pool = pools[id];
        
        // If the latest pool is unopen or user is already in it, create a new one 
        if (pool.status != Status.Open || inPool[user][id]) {
            lastPools[0][0] += 1;
            id = lastPools[0][0];
            lastPools[amount][risk] = id;
            pool = pools[id];
        }

        // Add user to the pool
        pool.users += 1;
        inPool[user][id] = true;
        emit UserAdded(id, user);

        // If pool is filled, update the pool's status and initiate the gage
        if (pool.users == 10) {
            pool.status = Status.Active;
            emit GageInitiated(id, amount, risk);
        }
    }

}
