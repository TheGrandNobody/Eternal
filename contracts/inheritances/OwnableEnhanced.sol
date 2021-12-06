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
    address private _admin;
    address private _previousAdmin;
    address private _fund;
    
    uint256 private _lockPeriod;

    event AdminRightsTransferred(address indexed previousAdmin, address indexed newAdmin);
    event FundRightsAttributed(address indexed newFund);

    /**
     * @dev Initializes the contract setting the deployer as the initial admin.
     */
    constructor () {
        address msgSender = _msgSender();
        _admin = msgSender;
        emit AdminRightsTransferred(address(0), msgSender);
    }

/////–––««« Modifiers »»»––––\\\\\
    /**
     * @dev Throws if called by any account other than the admin.
     */
    modifier onlyAdmin() {
        require(admin() == _msgSender(), "Caller is not the admin");
        _;
    }

    /**
     * @dev Throws if called by any account other than the fund.
     */
    modifier onlyFund() {
        require(fund() == _msgSender(), "Caller is not the fund");
        _;
    }

    /**
     * @dev Throws if called by any account other than the admin or the fund.
     */
    modifier onlyAdminAndFund() {
        require((admin() == _msgSender()) || (fund() == _msgSender()), "Caller is not the admin/fund");
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

    /**
     * @dev View the amount of time (in seconds) left before the previous admin can regain admin rights
     */
    function getUnlockTime() public view returns (uint256) {
        return _lockPeriod;
    }

/////–––««« Ownable-logic functions »»»––––\\\\\

    /**
     * @dev Leaves the contract without an admin. It will not be possible to call
     * `onlyAdmin` functions anymore. Can only be called by the current admin.
     *
     * NOTE: Renouncing admin rights will leave the contract without an admin,
     * thereby removing any functionality that is only available to the admin.
     */
    function renounceAdminRights() public virtual onlyAdmin{
        emit AdminRightsTransferred(_admin, address(0));
        _admin = address(0);
    }

    /**
     * @dev Attributes fund-rights for the Eternal Fund to a given address.
     * @param newFund The address of the new fund 
     *
     * Requirements:
     *
     * - New admin cannot be the zero address
     */
    function attributeFundRights(address newFund) public virtual onlyAdminAndFund {
        require(newFund != address(0), "New fund is the zero address");
        _fund = newFund;
        emit FundRightsAttributed(newFund);
    }

    /**
     * @dev Transfers admin rights of the contract to a new account (`newAdmin`).
     * Can only be called by the current admin.
     * @param newAdmin The address of the new admin
     *
     * Requirements:
     *
     * - New admin cannot be the zero address
     */
    function transferAdminRights(address newAdmin) public virtual onlyAdmin {
        require(newAdmin != address(0), "New admin is the zero address");
        emit AdminRightsTransferred(_admin, newAdmin);
        _admin = newAdmin;
    }

    /**
     * @dev Admin gives up admin rights for a given amount of time.
     * @param time The amount of time (in seconds) that the admin rights are given up for 
     */
    function lockAdminRights(uint256 time) public onlyAdmin {
        _previousAdmin = _admin;
        _admin = address(0);
        _lockPeriod = block.timestamp + time;
        emit AdminRightsTransferred(_admin, address(0));
    }

    /**
     * @dev Used to regain admin rights of a previously locked contract.
     *
     * Requirements:
     *
     * - Message sender must be the previous admin address
     * - The locking period must have elapsed
     */
    function unlock() public {
        require(_previousAdmin == msg.sender, "Caller is not the previous admin");
        require(block.timestamp > _lockPeriod, "The contract is still locked");
        emit AdminRightsTransferred(_admin, _previousAdmin);
        _admin = _previousAdmin;
        _previousAdmin = address(0);
    }
}