//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/IEternalToken.sol";
import "../interfaces/IEternalFactory.sol";
import "../interfaces/IEternalStorage.sol";
import "../interfaces/IEternalTreasury.sol";
import "../interfaces/ILoyaltyGage.sol";
import "../gages/LoyaltyGage.sol";
import "../inheritances/OwnableEnhanced.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody (me)
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract EternalFactory is IEternalFactory, OwnableEnhanced {

/////–––««« Interfaces, Addresses and Hashes »»»––––\\\\\

    // The Eternal shared storage interface
    IEternalStorage public immutable eternalStorage;
    // The Eternal token interface
    IEternalToken private eternal;
    // The Eternal treasury interface
    IEternalTreasury private eternalTreasury;

    // The keccak256 hash of this address
    bytes32 public immutable entity;

/**

/////–––««« Variables: Hidden Mappings »»»––––\\\\\
    
    // Keeps track of the respective gage tied to any given ID
    mapping (uint256 => address) gages

    // Keeps track of the risk percentage for any given asset's liquidity gage
    mapping (address => uint256) risk;

    // Keeps track of whether a user is in a liquid gage for a given asset
    mapping (address => mapping (address => bool)) inLiquidGage
*/

/////–––««« Variables: Gage Bookkeeping »»»––––\\\\\

    // Keeps track of the latest Gage ID
    bytes32 public immutable lastId;
    // The total number of active liquid gages
    bytes32 public immutable totalLiquidGages;
    // The number of liquid gages that can possibly be active at a time
    bytes32 public immutable liquidGageLimit;

/////–––««« Variables: Constants, Factors and Estimates »»»––––\\\\\

    // The holding time constant used in the percent change condition calculation (decided by the Eternal Fund) (x 10 ** 6)
    bytes32 public immutable timeFactor;
    // The average amount of time that users provide liquidity for
    bytes32 public immutable timeConstant;
    // The risk constant used in the calculation of the treasury's risk (x 10 ** 4)
    bytes32 public immutable riskConstant;
    // The minimum token value estimate of transactions in 24h, used in case the alpha value is not determined yet
    bytes32 public immutable baseline;

/////–––««« Constructors & Initializers »»»––––\\\\\

    constructor (address _eternal, address _eternalStorage) {
        // Set the initial Eternal token and storage interfaces
        eternal = IEternalToken(_eternal);
        eternalStorage = IEternalStorage(_eternalStorage);

        // Initialize keccak256 hashes
        entity = keccak256(abi.encodePacked(address(this)));
        lastId = keccak256(abi.encodePacked("lastId"));
        timeFactor = keccak256(abi.encodePacked("timeFactor"));
        timeConstant = keccak256(abi.encodePacked("timeConstant"));
        riskConstant = keccak256(abi.encodePacked("riskConstant"));
        baseline = keccak256(abi.encodePacked("baseline"));
        totalLiquidGages = keccak256(abi.encodePacked("totalLiquidGages"));
        liquidGageLimit = keccak256(abi.encodePacked("liquidGageLimit"));
    }

    function initialize(address _treasury) external onlyAdmin() {
        // Set the initial treasury interface
        eternalTreasury = IEternalTreasury(_treasury);
        // Set initial constants and factors
        eternalStorage.setUint(entity, timeFactor, 2 * (10 ** 6));
        eternalStorage.setUint(entity, timeConstant, 15);
        eternalStorage.setUint(entity, riskConstant, 100);
        // Set initial baseline
        eternalStorage.setUint(entity, baseline, 10 ** 5);
    }
    
/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @notice Creates an ETRNL liquid gage contract for a given user, asset and amount
     * @param asset The address of the asset being deposited in the liquid gage by the receiver
     * @param amount The amount of the asset being deposited in the liquid gage by the receiver
     *
     * Requirements:
     *
     * - The asset must be supported by Eternal
     * - Receivers (users) cannot deposit ETRNL into liquid gages
     * - There must be less active gages than the liquid gage limit dictates
     * - Users are only able to join 1 liquid gage per Asset-ETRNL pair offered (the maximum being the number of existing liquid gage pairs)
     */
    function initiateEternalLiquidGage(address asset, uint256 amount) external payable override returns(uint256) {
        // Checks
        uint256 userRisk = eternalStorage.getUint(entity, keccak256(abi.encodePacked("risk", asset)));
        require(userRisk > 0, "This asset is not supported");
        uint256 gageLimit = eternalStorage.getUint(entity, liquidGageLimit);
        require(asset != address(eternal), "Receiver can't deposit ETRNL");
        uint256 liquidGages = eternalStorage.getUint(entity, totalLiquidGages);
        require(liquidGages < gageLimit, "Liquid gage limit is reached");
        bool inLiquidGage = eternalStorage.getBool(entity, keccak256(abi.encodePacked("inLiquidGage", _msgSender(), asset)));
        require(!inLiquidGage, "Per-asset gaging limit reached");
        require(!eternalTreasury.viewUndergoingSwap(), "A liquidity swap is in progress");

        // Compute the percent change condition
        bytes32 eternalToken = keccak256(abi.encodePacked(address(eternal)));
        uint256 alpha = eternalStorage.getUint(eternalToken, keccak256(abi.encodePacked("alpha")));
        if (alpha == 0) {
            alpha = eternalStorage.getUint(entity, baseline);
        }
        uint256 burnRate = eternalStorage.getUint(eternalToken, keccak256(abi.encodePacked("burnRate")));
        uint256 _timeConstant = eternalStorage.getUint(entity, timeConstant);
        uint256 _timeFactor = eternalStorage.getUint(entity, timeFactor);
        uint256 percent = burnRate * alpha * (10 ** 18) * _timeConstant * _timeFactor / eternal.totalSupply();

        // Incremement the lastId tracker and the number of active liquid gages
        uint256 idLast = eternalStorage.getUint(entity, lastId) + 1;
        uint256 totalGagesLiquid = eternalStorage.getUint(entity, totalLiquidGages);
        eternalStorage.setUint(entity, lastId, idLast);
        eternalStorage.setUint(entity, totalLiquidGages, totalGagesLiquid + 1);

        // Deploy a new Gage
        LoyaltyGage newGage = new LoyaltyGage(idLast, percent, 2, false, address(eternalTreasury), _msgSender(), address(this));
        emit NewGage(idLast, address(newGage));
        eternalStorage.setAddress(entity, keccak256(abi.encodePacked("gages", idLast)), address(newGage));

        //Transfer the deposit to the treasury, calculate risk and join the gage for the user and the treasury
        uint256 treasuryRisk = userRisk - eternalStorage.getUint(entity, riskConstant);
        if (msg.value == 0) {
            require(IERC20(asset).transferFrom(_msgSender(), address(eternalTreasury), amount), "Failed to deposit asset");
        }
        eternalTreasury.fundEternalLiquidGage{value: msg.value}(address(newGage), _msgSender(), asset, amount, userRisk, treasuryRisk);
        return idLast;
    }

/////–––««« Fund-only functions »»»––––\\\\\

    /**
     * @notice Updates the address of the Eternal Treasury contract
     * @param newContract The new address for the Eternal Treasury contract
     */
    function setEternalTreasury(address newContract) external override onlyFund() {
        eternalTreasury = IEternalTreasury(newContract);
    }

    /**
     * @notice Updates the address of the Eternal Token contract
     * @param newContract The new address for the Eternal Token contract
     */
    function setEternalToken(address newContract) external override onlyFund() {
        eternal = IEternalToken(newContract);
    }
}