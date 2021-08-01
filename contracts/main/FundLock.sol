pragma solidity ^0.8.0;

import "../inheritances/OwnableEnhanced.sol";
import "../interfaces/IEternalToken.sol";

/**
 * @title FundLock contract
 * @author Nobody (me)
 * @notice The FundLock contract holds the funds earned from the (initially) 1% fee until the Eternal Fund contract is released (2.5 months)
 */
contract FundLock is OwnableEnhanced {

    // The Eternal Token interface
    IEternalToken private immutable eternal;

    // Keeps track of the time at which the funds become available
    uint256 public immutable timeOfRelease;
    // Keeps track of the total amount of time to be waited
    uint256 public immutable totalWaitingTime;

    constructor (address _eternal, uint256 _totalWaitingTime) {
        eternal = IEternalToken(_eternal);
        timeOfRelease = block.timestamp + _totalWaitingTime;
        totalWaitingTime = _totalWaitingTime;
    }

    /**
     * @dev Withraws locked funds to the Eternal Fund if the total waiting time has elapsed since deployment.
     */
    function withdrawFunds() external onlyAdminAndFund() {
        require(block.timestamp <= timeOfRelease, "Funds are still locked");

        eternal.transfer(fund(), eternal.balanceOf(address(this)));
    }
}