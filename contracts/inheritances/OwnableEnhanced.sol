//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an admin) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the admin account will be the one that deploys the contract. This
 * can later be changed with {transferAdminRights}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyAdmin`, which can be applied to your functions to restrict their use to
 * the admin.
 *
 * @notice This is a modified version of Openzeppelin's Ownable.sol, made to add certain functionalities
 * such as different modifiers (onlyFund and onlyAdminAndFund) and locking/unlocking
 */
abstract contract OwnableEnhanced is Context {

/////–––««« Variables: Addresses, Events and Locking »»»––––\\\\\

    address private _admin;
    address private _fund;

    event FundRightsAttributed(address indexed newFund);

    uint256 private _lockPeriod;

    // Used in preventing the admin from using functions a maximum of 2 weeks and 1 day after contract creation
    uint256 public immutable ownershipDeadline;

/////–––««« Constructor »»»––––\\\\\

    /**
     * @dev Initializes the contract setting the deployer as the initial admin.
     */
    constructor () {
        address msgSender = _msgSender();
        _admin = msgSender;
        _fund = msgSender;
        ownershipDeadline = block.timestamp + 3 days;
    }

/////–––««« Modifiers »»»––––\\\\\
    /**
     * @dev Throws if called by any account other than the admin.
     */
    modifier onlyAdmin() {
        require(admin() == _msgSender(), "Caller is not the admin");
        require(ownershipDeadline > block.timestamp, "Admin's rights are over");
        _;
    }

    /**
     * @dev Throws if called by any account other than the fund.
     */
    modifier onlyFund() {
        require(_msgSender() == fund(), "Caller is not the fund");
        _;
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @dev Returns the address of the current admin.
     */
    function admin() public view virtual returns (address) {
        return _admin;
    }

    /**
     * @dev Returns the address of the current fund.
     */
    function fund() public view virtual returns (address) {
        return _fund;
    }

/////–––««« Ownable-logic functions »»»––––\\\\\

    /**
     * @dev Attributes fund-rights for the Eternal Fund to a given address.
     * @param newFund The address of the new fund 
     *
     * Requirements:
     *
     * - New admin cannot be the zero address
     */
    function attributeFundRights(address newFund) public virtual onlyFund {
        require(newFund != address(0), "New fund is the zero address");
        _fund = newFund;
        emit FundRightsAttributed(newFund);
    }
}