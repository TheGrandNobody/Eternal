//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/IEternalFactory.sol";
import "../interfaces/ILoyaltyGage.sol";
import "../gages/LoyaltyGage.sol";
import "../inheritances/OwnableEnhanced.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody (me)
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract EternalFactory is IEternalFactory, OwnableEnhanced {

/////–––««« Variables: Interfaces, Addresses and Hashes »»»––––\\\\\

    // The Eternal shared storage interface
    IEternalStorage public immutable eternalStorage;
    // The Eternal token interface
    IERC20 private eternal;
    // The Eternal treasury interface
    IEternalTreasury private eternalTreasury;

    // The keccak256 hash of this address
    bytes32 public immutable entity;

/////–––««« Variables: Hidden Mappings »»»––––\\\\\
/**
    // Keeps track of the respective gage tied to any given ID
    mapping (uint256 => address) gages

    // Keeps track of the risk percentage for any given asset's liquidity gage (x 10 ** 4)
    mapping (address => uint256) risk;

    // Keeps track of whether a user is in a liquid gage for a given asset
    mapping (address => mapping (address => bool)) inLiquidGage
*/

/////–––««« Variables: Gage Bookkeeping »»»––––\\\\\

    // Keeps track of the latest Gage ID
    bytes32 public immutable lastId;

/////–––««« Variables: Constants, Factors and Limits »»»––––\\\\\

    // The holding time constant used in the percent change condition calculation (decided by the Eternal Fund) (x 10 ** 6)
    bytes32 public immutable timeFactor;
    // The average amount of time that users provide liquidity for (in days)
    bytes32 public immutable timeConstant;
    // The risk constant used in the calculation of the treasury's risk (x 10 ** 4)
    bytes32 public immutable riskConstant;
    // The general limiting variable deciding the total amount of ETRNL which can be used from the treasury's reserves
    bytes32 public immutable psi;

/////–––««« Variables: Counters and Estimates »»»––––\\\\\
    // The total number of ETRNL transacted with fees in the last full 24h period
    bytes32 public immutable alpha;
    // The total number of ETRNL transacted with fees in the current 24h period (ongoing)
    bytes32 public immutable transactionCount;
    // Keeps track of the UNIX time to recalculate the average transaction estimate
    bytes32 public immutable oneDayFromNow;
    // The minimum token value estimate of transactions in 24h, used in case the alpha value is not determined yet
    bytes32 public immutable baseline;

/////–––««« Constructors & Initializers »»»––––\\\\\

    constructor (address _eternalStorage, address _eternal) {
        // Set the initial Eternal storage and token interfaces
        eternalStorage = IEternalStorage(_eternalStorage);
        eternal = IERC20(_eternal);

        // Initialize keccak256 hashes
        entity = keccak256(abi.encodePacked(address(this)));
        lastId = keccak256(abi.encodePacked("lastId"));
        timeFactor = keccak256(abi.encodePacked("timeFactor"));
        timeConstant = keccak256(abi.encodePacked("timeConstant"));
        riskConstant = keccak256(abi.encodePacked("riskConstant"));
        baseline = keccak256(abi.encodePacked("baseline"));
        psi = keccak256(abi.encodePacked("psi"));
        alpha = keccak256(abi.encodePacked("alpha"));
        transactionCount = keccak256(abi.encodePacked("transactionCount"));
        oneDayFromNow = keccak256(abi.encodePacked("oneDayFromNow"));
    }

    function initialize(address _treasury, address _fund) external onlyAdmin {
        // Set the initial treasury interface
        eternalTreasury = IEternalTreasury(_treasury);

        // Set initial constants, factors and limiting variables
        eternalStorage.setUint(entity, timeFactor, 6 * (10 ** 6));
        eternalStorage.setUint(entity, timeConstant, 15);
        eternalStorage.setUint(entity, riskConstant, 100);
        eternalStorage.setUint(entity, psi, 4164 * (10 ** 6) * (10 ** 18));
        // Set initial baseline
        eternalStorage.setUint(entity, baseline, (10 ** 7) * (10 ** 18));
        // Initialize the transaction count time tracker
        eternalStorage.setUint(entity, oneDayFromNow, block.timestamp + 1 days);
        // Set initial risk
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("risk", 0xc778417E063141139Fce010982780140Aa0cD5Ab)), 1100);
        eternalStorage.setUint(entity, keccak256(abi.encodePacked("risk", 0x130966628846BFd36ff31a822705796e8cb8C18D)), 1100);

        attributeFundRights(_fund);
    }
    
/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @notice Creates an ETRNL liquid gage contract for a given user, asset and amount.
     * @param asset The address of the asset being deposited in the liquid gage by the receiver
     * @param amount The amount of the asset being deposited in the liquid gage by the receiver
     *
     * Requirements:
     *
     * - The asset must be supported by Eternal
     * - Receivers (users) cannot deposit ETRNL into liquid gages
     * - There must be less active gages than the liquid gage limit dictates
     * - Users are only able to join 1 liquid gage per Asset-ETRNL pair offered (the maximum being the number of existing liquid gage pairs)
     * - The Eternal Treasury cannot have a liquidity swap in progress
     */
    function initiateEternalLiquidGage(address asset, uint256 amount) external payable override {
        // Checks
        uint256 userRisk = eternalStorage.getUint(entity, keccak256(abi.encodePacked("risk", asset)));
        require(userRisk > 0, "This asset is not supported");
        require(asset != address(eternal), "Receiver can't deposit ETRNL");
        uint256 treasuryRisk = userRisk - eternalStorage.getUint(entity, riskConstant);
        require(!gageLimitReached(asset, amount, treasuryRisk), "ETRNL treasury reserves are dry");
        bytes32 inGage = keccak256(abi.encodePacked("inLiquidGage", _msgSender(), asset));
        bool inLiquidGage = eternalStorage.getBool(entity, inGage);
        require(!inLiquidGage, "Per-asset gaging limit reached");
        eternalStorage.setBool(entity, inGage, true);
        require(!eternalTreasury.viewUndergoingSwap(), "A liquidity swap is in progress");

        //Transfer the deposit to the treasury and join the gage for the user and the treasury
        if (msg.value == 0) {
            require(IERC20(asset).transferFrom(_msgSender(), address(eternalTreasury), amount), "Failed to deposit asset");
        } else {
            require(msg.value == amount, "Msg.value must equate amount");
        }

        // Incremement the lastId tracker
        uint256 idLast = eternalStorage.getUint(entity, lastId) + 1;
        eternalStorage.setUint(entity, lastId, idLast);

        // Deploy a new Gage
        LoyaltyGage newGage = new LoyaltyGage(idLast, percentCondition(), 2, false, address(eternalTreasury), _msgSender(), address(eternalStorage));
        emit NewGage(idLast, address(newGage));
        eternalStorage.setAddress(entity, keccak256(abi.encodePacked("gages", idLast)), address(newGage));

        eternalTreasury.fundEternalLiquidGage{value: msg.value}(address(newGage), _msgSender(), asset, amount, userRisk, treasuryRisk);
    }

/////–––««« Counter functions »»»––––\\\\\

    /**
     * @notice Updates any 24h counter related to ETRNL transactions.
     * @param amount The value used to update the counters
     * 
     * Requirements:
     *
     * - Only callable by the Eternal Token
     */
    function updateCounters(uint256 amount) external override {
        require(_msgSender() == address(eternal), "Caller must be the token");
        // If the 24h period is ongoing, then update the counter
        if (block.timestamp < eternalStorage.getUint(entity, oneDayFromNow)) {
            eternalStorage.setUint(entity, transactionCount, eternalStorage.getUint(entity, transactionCount) + amount);
        } else {
            // Update the baseline, alpha and the transaction count
            eternalStorage.setUint(entity, baseline, eternalStorage.getUint(entity, alpha));
            eternalStorage.setUint(entity, alpha, eternalStorage.getUint(entity, transactionCount));
            eternalStorage.setUint(entity, transactionCount, amount);
            // Reset the 24h period tracker
            eternalStorage.setUint(entity, oneDayFromNow, block.timestamp + 1 days);
        }
    }

/////–––««« Utility functions »»»––––\\\\\

    /**
     * @notice Computes whether there is enough ETRNL left in the treasury to allow for a given liquid gage (whilst remaining sustainable).
     * @param asset The address of the asset to be deposited to the specified liquid gage
     * @param amountAsset The amount of the asset being deposited to the specified liquid gage
     * @param risk The current risk percentage for an Eternal liquid gage with this asset as deposit
     * @return limitReached Whether the gaging limit is reached or not
     */
    function gageLimitReached(address asset, uint256 amountAsset, uint256 risk) public view returns (bool limitReached) {
        bytes32 treasury = keccak256(abi.encode(address(eternalTreasury)));
        // Convert the asset to ETRNL if it isn't already
        if (asset != address(eternal)) {
            (, , amountAsset) = eternalTreasury.computeMinAmounts(asset, address(eternal), amountAsset, 0);
        }

        uint256 reserveStakedBalances = eternalStorage.getUint(treasury, keccak256(abi.encodePacked("reserveStakedBalances")));
        uint256 userStakedBalances = reserveStakedBalances - eternalStorage.getUint(treasury, keccak256(abi.encodePacked("reserveBalances", address(eternalTreasury))));
        // Available ETRNL is all the ETRNL which can be spent by the treasury on gages whilst still remaining sustainable
        uint256 availableETRNL = eternal.balanceOf(address(eternalTreasury)) - eternalTreasury.convertToStaked(userStakedBalances) - eternalStorage.getUint(entity, psi); 
        
        limitReached = availableETRNL < amountAsset + (2 * amountAsset * risk / (10 ** 4));
    }

    /**
     * @notice Computes the percent condition for a given Eternal gage.
     * @return The percent by which the ETRNL supply must decrease in order for a gage to close in favor of the receiver
     */
    function percentCondition() public view returns (uint256) {
        uint256 _timeConstant = eternalStorage.getUint(entity, timeConstant);
        uint256 _timeFactor = eternalStorage.getUint(entity, timeFactor);
        uint256 burnRate = eternalStorage.getUint(keccak256(abi.encodePacked(address(eternal))), keccak256(abi.encodePacked("burnRate")));
        uint256 _baseline = eternalStorage.getUint(entity, baseline);
        uint256 _alpha = eternalStorage.getUint(entity, alpha) < _baseline ? _baseline : eternalStorage.getUint(entity, alpha);

        return burnRate * _alpha * _timeConstant * _timeFactor / eternal.totalSupply();
    }

/////–––««« Fund-only functions »»»––––\\\\\

    /**
     * @notice Updates the address of the Eternal Treasury contract.
     * @param newContract The new address for the Eternal Treasury contract
     */
    function setEternalTreasury(address newContract) external onlyFund {
        eternalTreasury = IEternalTreasury(newContract);
    }

    /**
     * @notice Updates the address of the Eternal Token contract.
     * @param newContract The new address for the Eternal Token contract
     */
    function setEternalToken(address newContract) external onlyFund {
        eternal = IERC20(newContract);
    }
}