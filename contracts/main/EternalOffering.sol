//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "../interfaces/ILoyaltyGage.sol";
import "../gages/LoyaltyGage.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Contract for the Eternal gaging platform
 * @author Nobody (me)
 * @notice The Eternal contract holds all user-data and gage logic.
 */
contract EternalOffering {

/////–––««« Variables: Events, Interfaces and Addresses »»»––––\\\\\

    // Signals the deployment of a new gage
    event NewGage(uint256 id, address indexed gageAddress);

    // The Joe router interface
    IJoeRouter02 public immutable joeRouter;
    // The Joe factory interface
    IJoeFactory public immutable joeFactory;
    // The Eternal token interface
    IERC20 public immutable eternal;

    // The address of the Eternal Treasury
    address public immutable treasury;
    // The address of the ETRNL-MIM pair
    address public immutable mimPair;
    // The address of the ETRNL-AVAX pair
    address public immutable avaxPair;

/////–––««« Variables: Mappings »»»––––\\\\\

    // Keeps track of the respective gage tied to any given ID
    mapping (uint256 => address) private gages;
    // Keeps track of whether a user is in a loyalty gage or has provided liquidity for this offering
    mapping (address => bool) private participated;
    // Keeps track of the amount of ETRNL the user has used in liquidity provision
    mapping (address => uint256) private liquidityOffered;

/////–––««« Variables: Constants and factors »»»––––\\\\\

    // The holding time constant used in the percent change condition calculation (decided by the Eternal Fund) (x 10 ** 6)
    uint256 public constant TIME_FACTOR = 2 * (10 ** 6);
    // The average amount of time that users provide liquidity for
    uint256 public constant TIME_CONSTANT = 15;
    // The minimum token value estimate of transactions in 24h, used in case the alpha value is not determined yet
    uint256 public constant BASELINE = 10 ** 6;
    // The number of ETRNL allocated
    uint256 public constant LIMIT = 425 * (10 ** 7);
    // The MIM address
    address public constant MIM = 0x130966628846BFd36ff31a822705796e8cb8C18D;

/////–––««« Variables: Gage/Liquidity bookkeeping »»»––––\\\\\

    // Keeps track of the latest Gage ID
    uint256 private lastId;
    // The total number of ETRNL dispensed in this offering thus far
    uint256 private totalETRNLOffered;
    // The total number of MIM-ETRNL lp tokens acquired
    uint256 private totalLpMIM;
    // The total number of AVAX-ETRNL lp tokens acquired
    uint256 private totalLpAVAX;
    // The blockstamp at which this contract will cease to offer
    uint256 private offeringEnds;

/////–––««« Constructor »»»––––\\\\\

    constructor (address _eternal, address _treasury) {
        // Set the initial Eternal token and storage interfaces
        eternal = IERC20(_eternal);
        IJoeRouter02 _joeRouter = IJoeRouter02(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
        IJoeFactory _joeFactory = IJoeFactory(_joeRouter.factory());
        joeRouter = _joeRouter;
        joeFactory = _joeFactory;

        // Create the pairs
        avaxPair = _joeFactory.getPair(_eternal, _joeRouter.WAVAX());
        mimPair = _joeFactory.createPair(_eternal, MIM);
        treasury = _treasury;
        offeringEnds = block.timestamp + 1 days;
    }

/////–––««« Variable state-inspection functions »»»––––\\\\\

    /**
     * @notice Computes the equivalent of an asset to an other asset and the minimum amount of the two needed to provide liquidity
     * @param asset The first specified asset, which we want to convert 
     * @param otherAsset The other specified asset
     * @param amountAsset The amount of the first specified asset
     * @param uncertainty The minimum loss to deduct from each minimum in case of price changes
     * @return minOtherAsset The minimum amount of otherAsset needed to provide liquidity (not given if uncertainty = 0)
     * @return minAsset The minimum amount of Asset needed to provide liquidity (not given if uncertainty = 0)
     * @return amountOtherAsset The equivalent in otherAsset of the given amount of asset
     */
    function computeMinAmounts(address asset, address otherAsset, uint256 amountAsset, uint256 uncertainty) public view returns(uint256 minOtherAsset, uint256 minAsset, uint256 amountOtherAsset) {
        // Get the reserve ratios for the Asset-otherAsset pair
        (uint256 reserveA, uint256 reserveB,) = IJoePair(joeFactory.getPair(asset, otherAsset)).getReserves();
        (uint256 reserveAsset, uint256 reserveOtherAsset) = asset < otherAsset ? (reserveA, reserveB) : (reserveB, reserveA);

        // Determine a reasonable minimum amount of asset and otherAsset based on current reserves (with a tolerance =  1 / uncertainty)
        amountOtherAsset = joeRouter.quote(amountAsset, reserveAsset, reserveOtherAsset);
        if (uncertainty != 0) {
            minAsset = joeRouter.quote(amountOtherAsset, reserveOtherAsset, reserveAsset);
            minAsset -= minAsset / uncertainty;
            minOtherAsset = amountOtherAsset - (amountOtherAsset / uncertainty);
        }
    }

    /**
     * @notice View the total ETRNL offered in this IGO
     * @return  The total ETRNL distributed in this offering
     */
    function viewTotalETRNLOffered() external view returns(uint256) {
        return totalETRNLOffered;
    }

    /**
     * @notice View the total number of MIM-ETRNL and AVAX-ETRNL lp tokens earned in this IGO
     * @return The total number of lp tokens for the MIM-ETRNl and AVAX-ETRNL pair in this contract
     */
    function viewTotalLp() external view returns (uint256, uint256) {
        return (totalLpMIM, totalLpAVAX);
    }

    /**
     * @notice View the amount of ETRNL a given user has been offered in total
     * @param user The specified user
     * @return  The total amount of ETRNL offered for the user
     */
    function viewLiquidityOffered(address user) external view returns (uint256) {
        return liquidityOffered[user];
    }
    
/////–––««« Gage-logic functions »»»––––\\\\\

    /**
     * @notice Creates an ETRNL loyalty gage contract for a given user and amount
     * @param asset The address of the asset being deposited in the loyalty gage by the receiver
     * @param amount The amount of the asset being deposited in the loyalty gage by the receiver
     * @return The id of the gage created
     *
     * Requirements:
     * 
     * - The offering must be ongoing
     * - Only MIM or AVAX loyalty gages are offered
     * - There can not have been more than 4 250 000 000 ETRNL offered in total
     * - A user can only participate in a maximum of one loyalty gage
     * - A user can not send money to gages/provide liquidity for more than 10 000 000 ETRNL 
     * - The sum of the new amount provided and the previous amounts provided by a user can not exceed the equivalent of 10 000 000 ETRNL
     */
    function initiateEternalLoyaltyGage(address asset, uint256 amount) external payable returns(uint256) {
        // Checks
        require(block.timestamp < offeringEnds, "Offering is over");
        require(asset == MIM || msg.value > 0, "Only MIM or AVAX");
        require(totalETRNLOffered < LIMIT, "ETRNL offering limit is reached");
        require(!participated[msg.sender], "User gage limit reached");
        require(liquidityOffered[msg.sender] < (10 ** 7) * (10 ** 18), "Limit for this user reached");

        uint256 providedETRNL;
        uint256 providedAsset;
        uint256 liquidity;
        // Compute the minimum amounts needed to provide liquidity and the equivalent of the asset in ETRNL
        (uint256 minETRNL, uint256 minAsset, uint256 amountETRNL) = computeMinAmounts(asset, address(eternal), amount, 200);
        require(amountETRNL + liquidityOffered[msg.sender] <= (10 ** 7) * (10 ** 18), "Amount exceeds the user limit");

        // Compute the percent change condition
        uint256 percent = 500 * BASELINE * (10 ** 18) * TIME_CONSTANT * TIME_FACTOR / eternal.totalSupply();

        // Incremement the lastId tracker and increase the total ETRNL count
        lastId += 1;
        participated[msg.sender] = true;

        // Deploy a new Gage
        LoyaltyGage newGage = new LoyaltyGage(lastId, percent, 2, false, address(this), msg.sender, address(this));
        emit NewGage(lastId, address(newGage));
        gages[lastId] = address(newGage);

        //Transfer the deposit
        if (msg.value == 0) {
            require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "Failed to deposit asset");
        } else {
            asset = joeRouter.WAVAX();
        }

        // Calculate risk and join the gage for the user and the Eternal Offering contract
        uint256 rRisk = totalETRNLOffered < LIMIT / 4 ? 3100 : (totalETRNLOffered < LIMIT / 2 ? 2600 : (totalETRNLOffered < LIMIT * 3 / 4 ? 2100 : 1600));

        // Add liquidity to the ETRNL/Asset pair
        require(eternal.approve(address(joeRouter), amountETRNL), "Approve failed");
        if (asset == joeRouter.WAVAX()) {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidityAVAX{value: amount}(address(eternal), amountETRNL, minETRNL, minAsset, address(this), block.timestamp);
            totalLpAVAX += liquidity;
        } else {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidity(address(eternal), asset, amountETRNL, amount, minETRNL, minAsset, address(this), block.timestamp);
            totalLpMIM += liquidity;
        }
        // Calculate the difference in asset given vs asset provided
        providedETRNL += (amount - providedAsset) * providedETRNL / amount;

        // Update the offering variables
        liquidityOffered[msg.sender] += providedETRNL + (providedETRNL * (rRisk - 100) / (10 ** 4));
        totalETRNLOffered += providedETRNL + (providedETRNL * (rRisk - 100) / (10 ** 4));

        // Initialize the loyalty gage and transfer the user's instant reward
        newGage.initialize(asset, address(eternal), amount, providedETRNL, rRisk, 1000);
        require(eternal.transfer(msg.sender, providedETRNL * (rRisk - 100) / (10 ** 4)), "Failed to transfer bonus");

        return lastId;
    }

    /**
     * @notice Settles a given loyalty gage closed by a given receiver
     * @param receiver The specified receiver 
     * @param id The specified id of the gage
     * @param winner Whether the gage closed in favour of the receiver
     *
     * Requirements:
     * 
     * - Only callable by a loyalty gage
     */
    function settleGage(address receiver, uint256 id, bool winner) external {
        // Checks
        address _gage = gages[id];
        require(msg.sender == _gage, "msg.sender must be the gage");

        // Load all gage data
        ILoyaltyGage gage = ILoyaltyGage(_gage);
        (,, uint256 rRisk) = gage.viewUserData(receiver);
        (,uint256 dAmount, uint256 dRisk) = gage.viewUserData(address(this));

        // Compute and transfer the net gage deposit due to the receiver
        if (winner) {
            dAmount += dAmount * dRisk / (10 ** 4);
        } else {
            dAmount -= dAmount * rRisk / (10 ** 4);
        }
        require(eternal.transfer(receiver, dAmount), "Failed to transfer ETRNL");
    }

/////–––««« Liquidity Provision functions »»»––––\\\\\

    /**
     * @notice Provides liquidity to either the MIM-ETRNL or AVAX-ETRNL pairs and sends ETRNL the msg.sender
     * @param amount The amount of the asset being provided
     * @param asset The address of the asset being provided
     *
     * Requirements:
     * 
     * - The offering must be ongoing
     * - Only MIM or AVAX can be used in providing liquidity
     * - There can not have been more than 4 250 000 000 ETRNL offered in total
     * - A user can not send money to gages/provide liquidity for more than 10 000 000 ETRNL 
     * - The sum of the new amount provided and the previous amounts provided by a user can not exceed the equivalent of 10 000 000 ETRNL
     */
    function provideLiquidity(uint256 amount, address asset) external payable {
        // Checks
        require(block.timestamp < offeringEnds, "Offering is over");
        require(asset == MIM || msg.value > 0, "Only MIM or AVAX");
        require(liquidityOffered[msg.sender] < (10 ** 7) * (10 ** 18), "Limit for this user reached");
        require(totalETRNLOffered < LIMIT, "ETRNL offering limit is reached");


        uint256 providedETRNL;
        uint256 providedAsset;
        uint256 liquidity;
        // Compute the minimum amounts needed to provide liquidity and the equivalent of the asset in ETRNL
        (uint256 minETRNL, uint256 minAsset, uint256 amountETRNL) = computeMinAmounts(asset, address(eternal), amount, 200);
        require(amountETRNL + liquidityOffered[msg.sender] <= (10 ** 7) * (10 ** 18), "Amount exceeds the user limit");

        // Transfer user's funds to this contract if it's not already done
        if (msg.value == 0) {
            require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "Failed to deposit funds");
        } else {
            asset = joeRouter.WAVAX();
        }

        // Add liquidity to the ETRNL/Asset pair
        require(eternal.approve(address(joeRouter), amountETRNL), "Approve failed");
        if (asset == joeRouter.WAVAX()) {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidityAVAX{value: amount}(address(eternal), amountETRNL, minETRNL, minAsset, address(this), block.timestamp);
            totalLpAVAX += liquidity;
        } else {
            (providedETRNL, providedAsset, liquidity) = joeRouter.addLiquidity(address(eternal), asset, amountETRNL, amount, minETRNL, minAsset, address(this), block.timestamp);
            totalLpMIM += liquidity;
        }

        // Calculate and add the difference in asset given vs asset provided
        providedETRNL += (amount - providedAsset) * providedETRNL / amount;

        // Update the offering variables
        liquidityOffered[msg.sender] += providedETRNL;
        totalETRNLOffered += providedETRNL;

        // Transfer ETRNL to the user
        require(eternal.transfer(msg.sender, providedETRNL), "ETRNL transfer failed");
    }

/////–––««« Post-Offering functions »»»––––\\\\\

    /**
     * @notice Transfer all lp tokens, leftover ETRNL and any dust present in this contract, to the Eternal Treasury
     * 
     * Requirements:
     *
     * - Either the time or ETRNL limit must be met
     */
    function sendLPToTreasury() external {
        // Checks
        require(totalETRNLOffered == LIMIT || offeringEnds < block.timestamp, "Offering not over yet");

        uint256 mimBal = IERC20(MIM).balanceOf(address(this));
        uint256 etrnlBal = eternal.balanceOf(address(this));
        uint256 avaxBal = address(this).balance;
        // Send the MIM and AVAX balance of this contract to the Eternal Treasury if there is any dust leftover
        if (mimBal > 0) {
            require(IERC20(MIM).transfer(treasury, mimBal), "MIM Transfer failed");
        }
        if (avaxBal > 0) {
            (bool success,) = treasury.call{value: avaxBal}("");
            require(success, "AVAX transfer failed");
        }

        // Send any leftover ETRNL from this offering to the Eternal Treasury
        if (etrnlBal > 0) {
            require(eternal.transfer(treasury, etrnlBal), "ETRNL transfer failed");
        }

        // Send the lp tokens earned from this offering to the Eternal Treasury
        require(IERC20(avaxPair).transfer(treasury, totalLpAVAX), "Failed to transfer AVAX lp");
        require(IERC20(mimPair).transfer(treasury, totalLpMIM), "Failed to transfer MIM lp");
    }
}