//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Gage.sol";
import "../interfaces/IGageV2.sol";

contract LoyaltyGage is Gage, IGageV2 {

    // Address of the stakeholder which pays the discount in a loyalty gage
    address private immutable distributor;
    // Address of the stakeholder which benefits from the discount in a loyalty gage
    address private immutable receiver;
    // The asset used in the condition
    IERC20 private asset;
    // The percentage change condition for the total token supply (multiplied by 10 ** 9 for decimal precision)
    uint256 private immutable percent;
    // The total supply at the time of the deposit
    uint256 private totalSupply;
    // Whether the token's supply is inflationary or deflationary
    bool private immutable inflationary;

    constructor(uint256 _id, uint256 _percent, uint32 _users, bool _inflationary, address _creator, address _buyer, address _eternal) Gage(_id, _users, _eternal, true) {
        distributor = _creator;
        receiver = _buyer;
        percent = _percent;
        inflationary = _inflationary;
    }

    /**
     * @dev Adds a stakeholder to this gage and records the initial data.
     * @param deposit The address of the asset used as deposit by this user
     * @param amount The user's chosen deposit amount 
     * @param risk The user's chosen risk percentage
     *
     * Requirements:
     *
     * - Risk must not exceed 100 percent
     * - User must not already be in the gage
     */
    function join(address deposit, uint256 amount, uint8 risk) external override {
        require(risk <= 100, "Invalid risk percentage");
        UserData storage data = userData[_msgSender()];
        require(!data.inGage, "User is already in this gage");

        data.amount = amount;
        data.asset = deposit;
        data.risk = risk;
        data.inGage = true;
        users += 1;

        if (_msgSender() == distributor) {
            asset = IERC20(deposit);
            totalSupply = asset.totalSupply();
        }

        eternal.deposit(deposit, _msgSender(), amount, id);
        emit UserAdded(id, _msgSender());
        // If contract is filled, update its status and initiate the gage
        if (users == capacity) {
            status = Status.Active;
            emit GageInitiated(id);
        }
    }

    function exit() external override {
        UserData storage data = userData[_msgSender()];
        require(data.inGage, "User is not in this gage");
        // Remove user from the gage first (prevent re-entrancy)
        data.inGage = false;
        uint256 deltaSupply = inflationary ? (asset.totalSupply() - totalSupply) : (totalSupply - asset.totalSupply());
        uint256 percentChange = deltaSupply * (10 ** 9) / totalSupply;
        bool winner = percentChange >= percent;

        eternal.withdraw(receiver, id, winner);
        eternal.withdraw(distributor, id, !winner);
    }

    /**
     * @dev View the address of the creator
     * @return The address of the creator
     */
    function viewDistributor() external view override returns (address){
        return distributor;
    }

    /**
     * @dev View the address of the buyer
     * @return The address of the buyer
     */
    function viewReceiver() external view override returns (address) {
        return receiver;
    }

    /**
     * @dev View the percent change condition for the total token supply of the deposit
     * @return The percent change condition for the total token supply
     */
    function viewPercent() external view override returns (uint256) {
        return percent;
    }

    /**
     * @dev View whether the deposited token suppply is inflationary or deflationary
     * @return True if the token is inflationary, False if it is deflationary
     */
    function viewInflationary() external view override returns (bool) {
        return inflationary;
    }
}