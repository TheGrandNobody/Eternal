//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IEternalStorage.sol";

/**
 * @title Contract for Eternal's shared eternal storage
 * @author Nobody (me)
 * @notice The Eternal Storage contract holds all variables of all other Eternal contracts
 */
contract EternalStorage is IEternalStorage, Context {

    // Scalars
    mapping (bytes32 => mapping (bytes32 => uint256)) private uints;
    mapping (bytes32 => mapping (bytes32 => address)) private addresses;
    mapping (bytes32 => mapping (bytes32 => bool)) private bools;
    mapping (bytes32 => mapping (bytes32 => bytes32)) private bytes32s;

    // Multi-value variables
    mapping(bytes32 => uint256[]) private manyUints;
    mapping(bytes32 => address[]) private manyAddresses;
    mapping(bytes32 => bool[]) private manyBools;
    mapping(bytes32 => bytes32[]) private manyBytes;

constructor () {
    bytes32 eternalStorage = keccak256(abi.encodePacked(address(this)));    
    bytes32 nobody = keccak256(abi.encodePacked(_msgSender()));
    addresses[eternalStorage][nobody] = _msgSender();
}

/////–––««« Modifiers »»»––––\\\\\

    /**
     * @notice Ensures that only the latest contracts can modify variables' states
     */
    modifier onlyLatestVersion() {
        bytes32 eternalStorage = keccak256(abi.encodePacked(address(this)));
        bytes32 entity = keccak256(abi.encodePacked(_msgSender()));
        require(_msgSender() == addresses[eternalStorage][entity], "Old contract can't edit storage");
        _;
    }

/////–––««« Setters »»»––––\\\\\

    /**
     * @notice Sets a uint256 value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified uint256 value
     */
    function setUint(bytes32 entity, bytes32 key, uint256 value) external override onlyLatestVersion() {
        uints[entity][key] = value;
    }

    /**
     * @notice Sets an address value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified address value
     */
    function setAddress(bytes32 entity, bytes32 key, address value) external override onlyLatestVersion() {
        addresses[entity][key] = value;
    }

    /**
     * @notice Sets a boolean value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified boolean value
     */
    function setBool(bytes32 entity, bytes32 key, bool value) external override onlyLatestVersion() {
        bools[entity][key] = value;
    }    

    /**
     * @notice Sets a bytes32 value for a given contract and key
     * @param entity The keccak256 hash of the contract's address
     * @param key The specified mapping key
     * @param value The specified bytes32 value
     */
    function setBytes(bytes32 entity, bytes32 key, bytes32 value) external override onlyLatestVersion() {
        bytes32s[entity][key] = value;
    }    

    /**
     * @notice Sets or pushes a uin256 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified uint256 value
     */
    function setUintArrayValue(bytes32 key, uint256 index, uint256 value) external override onlyLatestVersion() {
        if (index == 0) {
            manyUints[key].push(value);
        } else {
            manyUints[key][index] = value;
        }
    }

    /**
     * @notice Sets or pushes an address array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified address value
     */
    function setAddressArrayValue(bytes32 key, uint256 index, address value) external override onlyLatestVersion() {
        if (index == 0) {
            manyAddresses[key].push(value);
        } else {
            manyAddresses[key][index] = value;
        }
    }   

    /**
     * @notice Sets or pushes a boolean array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified boolean value
     */
    function setBoolArrayValue(bytes32 key, uint256 index, bool value) external override onlyLatestVersion() {
        if (index == 0) {
            manyBools[key].push(value);
        } else {
            manyBools[key][index] = value;
        }
    }    

    /**
     * @notice Sets or pushes a bytes32 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the array's element being modified
     * @param value The specified bytes32value
     */
    function setBytesArrayValue(bytes32 key, uint256 index, bytes32 value) external override onlyLatestVersion() {
        if (index == 0) {
            manyBytes[key].push(value);
        } else {
            manyBytes[key][index] = value;
        }
    }   

/////–––««« Getters »»»––––\\\\\
    /**
     * @notice Returns a uint256 value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The uint256 value mapped to the key
     */
    function getUint(bytes32 entity, bytes32 key) external view override returns (uint256) {
        return uints[entity][key];
    }

    /**
     * @notice Returns an address value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The address value mapped to the key
     */
    function getAddress(bytes32 entity, bytes32 key) external view override returns (address) {
        return addresses[entity][key];
    }

    /**
     * @notice Returns a boolean value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The boolean value mapped to the key
     */    
    function getBool(bytes32 entity, bytes32 key) external view override returns (bool) {
        return bools[entity][key];
    }

    /**
     * @notice Returns a bytes32 value for a given contract and key
     * @param entity The keccak256 hash of the specified contract
     * @param key The specified mapping key
     * @return The bytes32 value mapped to the key
     */
    function getBytes(bytes32 entity, bytes32 key) external view override returns (bytes32) {
        return bytes32s[entity][key];
    }  

    /**
     * @notice Returns a uint256 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The uint256 value at the specified index for the specified array
     */
    function getUintArrayValue(bytes32 key, uint256 index) external view override returns (uint256) {
        return manyUints[key][index];
    }

    /**
     * @notice Returns an address array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The address value at the specified index for the specified array
     */
    function getAddressArrayValue(bytes32 key, uint256 index) external view override returns (address) {
        return manyAddresses[key][index];
    }

    /**
     * @notice Returns a boolean array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The boolean value at the specified index for the specified array
     */
    function getBoolArrayValue(bytes32 key, uint256 index) external view override returns (bool) {
        return manyBools[key][index];
    }

    /**
     * @notice Returns a bytes32 array's element's value for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     * @return The bytes32 value at the specified index for the specified array
     */
    function getBytesArrayValue(bytes32 key, uint256 index) external view override returns (bytes32) {
        return manyBytes[key][index];
    }

/////–––««« Array Deleters »»»––––\\\\\

    /** 
     * @notice Deletes a uint256 array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteUint(bytes32 key, uint256 index) external override onlyLatestVersion() {
        uint256 length = manyUints[key].length;
        manyUints[key][index] = manyUints[key][length - 1];
        manyUints[key].pop();
    }

    /** 
     * @notice Deletes an address array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteAddress(bytes32 key, uint256 index) external override onlyLatestVersion() {
        uint256 length = manyAddresses[key].length;
        manyAddresses[key][index] = manyAddresses[key][length - 1];
        manyAddresses[key].pop();
    }

    /** 
     * @notice Deletes a boolean array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteBool(bytes32 key, uint256 index) external override onlyLatestVersion() {
        uint256 length = manyBools[key].length;
        manyBools[key][index] = manyBools[key][length - 1];
        manyBools[key].pop();
    }

    /** 
     * @notice Deletes a bytes32 array's element for a given key and index
     * @param key The specified mapping key
     * @param index The specified index of the desired element
     */
    function deleteBytes(bytes32 key, uint256 index) external override onlyLatestVersion() {
        uint256 length = manyBytes[key].length;
        manyBytes[key][index] = manyBytes[key][length - 1];
        manyBytes[key].pop();
    }

/////–––««« Array Length »»»––––\\\\\

    /**
     * @notice Returns the length of a uint256 array for a given key
     * @param key The specified mapping key
     * @return The length of the array mapped to the key
     */
    function lengthUint(bytes32 key) external view override returns (uint256) {
        return manyUints[key].length;
    }

    /**
     * @notice Returns the length of an address array for a given key
     * @param key The specified mapping key
     * @return The length of the array mapped to the key
     */
    function lengthAddress(bytes32 key) external view override returns (uint256) {
        return manyAddresses[key].length;
    }

    /**
     * @notice Returns the length of a boolean array for a given key
     * @param key The specified mapping key
     * @return The length of the array mapped to the key
     */
    function lengthBool(bytes32 key) external view override returns (uint256) {
        return manyBools[key].length;
    }

    /**
     * @notice Returns the length of a bytes32 array for a given key
     * @param key The specified mapping key
     * @return The length of the array mapped to the key
     */
    function lengthBytes(bytes32 key) external view override returns (uint256) {
        return manyBytes[key].length;
    }
}