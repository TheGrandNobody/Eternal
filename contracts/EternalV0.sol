//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./governance/OwnableEnhanced.sol";
import "./interfaces/IEternalToken.sol";
import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody (me)
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract EternalV0 is OwnableEnhanced {

    constructor (address eternalToken) {
        eternal = IEternalToken(eternalToken);
    }

    enum Status {
        Open,
        Active,
        Closed
    }

    struct GagePool {
        uint256 id;            // The id of the pool
        uint24 amount;         // The entry deposit of ETRNL needed to participate in this pool
        uint8 users;           // The current number of users participating in this pool
        uint8 risk;            // The percentage that is being risked in this pool
        Status status;         // The status of the pool
    }

    IEternalToken private eternal;

    mapping (uint256 => GagePool) pools;
    mapping (address => mapping(uint256 => bool)) inPool;
    mapping (uint256 => mapping(uint256 => uint256)) lastPools;

    event UserAdded(uint256 id, address indexed user);
    event UserRemoved(uint256 id, address indexed user);
    event GageInitiated(uint256 id, uint256 amount, uint256 risk);
    event GageClosed(uint256 id, uint256 amount, uint256 risk);

    /**
     * @dev Add a given user to an available gage pool with given amount and risk
     * @param user The address of the specified user
     * @param amount The amount of ETRNL the user will initially lock in the gage
     * @param risk The percentage of the initial amount the user is willing to risk in the gage
     */
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
        eternal.transferFrom(user, address(this), amount);
        emit UserAdded(id, user);

        // If pool is filled, update the pool's status and initiate the gage
        if (pool.users == 10) {
            pool.status = Status.Active;
            emit GageInitiated(id, amount, risk);
        }
    }

    /**
     * @dev Removes a given user from a given pool
     * @param id The id of the specified pool
     * @param user The address of the specified user
     *
     * Requirements:
     *
     * - User must be in the pool
     * - User cannot be the winner of the gage
     */
    function removeUserFromPool(uint256 id, address user) external {
        require(inPool[user][id], "User is not in this pool");
        GagePool storage pool = pools[id];
        require(pool.status != Status.Closed, "Winner can't leave a closed gage");

        // Remove user from the pool first (prevent re-entrancy)
        inPool[user][id] = false;
        pool.users -= 1;

        if (pool.status == Status.Open) {
            emit UserRemoved(id, user);
        } else if (pool.status == Status.Active && pool.users == 1) {
            // If there is only one user left after this one has left, update pool accordingly
            pool.status = Status.Closed;
            emit GageClosed(id, pool.amount, pool.risk);
        }

        // Compute the amount minus the loss incurred from forfeiting
        uint256 netAmount = pool.amount - (pool.amount * pool.risk / 100);
        // Users get the entire entry amount back if the gage wasn't active
        uint256 amount = pool.status == Status.Open ? pool.amount : netAmount;
        eternal.transfer(user, amount);
    }

    /**
     * @dev Claims the reward for a given user of a given pool
     * @param id The id of the specified pool
     * @param user The address of the specified winner
     * @return True if the procedure goes to completion
     */
    function claimRewardFor(uint256 id, address user) external returns (bool) {
        _claimReward(id, user);
        return true;
    }

    /**
     * @dev Claims the reward of a given pool
     * @param id The id of the specified pool
     * @return True if the procedure goes to completion
     */
    function claimRewardSelf(uint256 id) external returns (bool) {
        _claimReward(id, _msgSender());
        return true;
    }

    /**
     * @dev Claims the reward of a given user of a given pool
     * @param id The id of the specified pool
     * @param user The address of the specified winner
     * 
     * Requirements:
     *
     * - Selected pool cannot be open or active
     * - User must actually be the winner in this pool
     */
    function _claimReward(uint256 id, address user) private {
        GagePool storage pool = pools[id];
        require(pool.status == Status.Closed, "Pool status is not 'Closed'");
        require(inPool[user][id], "User is not the winner");

        inPool[user][id] = false;
        uint256 reward = pool.amount + (pool.amount * 9 * pool.risk / 100);
        eternal.transfer(user, reward);
    }
}