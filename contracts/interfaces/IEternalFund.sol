//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev Eternal Fund interface
 * @author Nobody (me)
 * @notice Methods are used for all of Eternal's governance functions
 */
interface IEternalFund {
    // Delegates the message sender's vote balance to a given user
    function delegate(address delegatee) external;
    // Determine the number of votes of a given account prior to a given block
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256);
    // Gets the current votes balance for a given account
    function getCurrentVotes(address account) external view returns(uint256);
    // Transfer part of a given delegates' voting balance to another new delegate
    function moveDelegates(address srcRep, address dstRep, uint256 amount) external;

    // Signals a change of a given user's delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    // Signals a change of a given delegate's vote balance
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
}