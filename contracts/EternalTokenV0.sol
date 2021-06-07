//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interfaces/IEternalTokenV0.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinFactory.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";

/**
 * @title Contract for the Eternal Token (ETRNL)
 * @author Nobody (credits to OpenZeppelin for the IERC20 and IERC20Metadata interfaces)
 * @notice The Eternal Token contract holds all the deflationary, burn, reflect, funding and auto-liquidity provision mechanics
 */
contract EternalTokenV0 is Context, IERC20, IERC20Metadata, IEternalTokenV0, Ownable {

    // Keeps track of how much an address allows any other address to spend on its behalf
    mapping (address => mapping (address => uint256)) private allowances;
    // The reflected balances used to track reward-accruing users' total balances
    mapping (address => uint256) private reflectedBalances;
    // The true balances used to track non-reward-accruing addresses' total balances
    mapping (address => uint256) private trueBalances;
    // Keeps track of whether an address is excluded from rewards
    mapping (address => bool) private isExcludedFromRewards;
    // Keeps track of whether an address is excluded from transfer fees
    mapping (address => bool) private isExcludedFromFees;

    // Keeps track of all reward-excluded addresses
    address[] private excludedAddresses;

    // The total token supply after taking reflections into account
    uint256 private totalReflectedSupply;
    // The true total token supply 
    uint64 private totalTokenSupply = (10**10) * (10**9);
    // The percentage of the total fee rate used to auto-lock liquidity
    uint8 private liquidityProvisionRate;
    // The percentage of the total fee rate stored in the EternalFund
    uint8 private fundingRate;
    // The percentage of the total fee rate that is burned
    uint8 private burnRate;
    // The percentage of the total fee rate redistributed to holders
    uint8 private redistributionRate;

    // PangolinDex Router interface to swap tokens for WAVAX and add liquidity
    IPangolinRouter internal immutable pangolinRouter;
    // The address of the ETRNL/WAVAX pair
    address internal immutable pangolinPair;

    /**
     * @dev Sets the token ticker and token name. Mints the total supply to the contract deployer.
     */
    constructor () {

        // The largest possible number in a 256-bit integer
        uint256 max = ~uint256(0);

        // Initialize name, ticker symbol and total supply
        totalReflectedSupply = (max - (max % totalTokenSupply));
        reflectedBalances[_msgSender()] = totalTokenSupply;

        // Create pair address
        IPangolinRouter _pangolinRouter = IPangolinRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
        pangolinPair = IPangolinFactory(_pangolinRouter.factory()).createPair(address(this), _pangolinRouter.WAVAX());

        // Initialize Pangolin Router
        pangolinRouter = _pangolinRouter;

        // Exclude the owner from rewards and fees
        excludeFromReward(owner());
        isExcludedFromFees[owner()] = true;

        // Exclude this contract from rewards and fees
        isExcludedFromRewards[address(this)] = true;
        isExcludedFromFees[owner()] = true;
        excludedAddresses.push(address(this));

        // Exclude the burn address from rewards
        isExcludedFromRewards[address(0)];
    }

    /**
     * @dev The name of the token. 
     * @return The token name
     */
    function name() external pure override returns (string memory) {
        return "Eternal Token";
    }

    /**
     * @dev View the token ticker
     * @return The token symbol
     */
    function symbol() external pure override returns (string memory) {
        return "ETRNL";
    }

    /**
     * @dev View the maximum number of decimals for the Eternal token
     * @return The number of decimals
     */
    function decimals() external pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev View the total supply of the Eternal token.
     * @return Returns the total ETRNL supply.
     */
    function totalSupply() external view override returns (uint256){
        return totalTokenSupply;
    }

    function setRate(uint8 newRate, Rate rate) external onlyOwner {
        require((uint(rate) >= 0 && uint(rate) <= 3), "EternalTokenV0::setRate(): Invalid rate type");
        require(newRate >= 0, "EternalTokenV0::setRate(): The new rate must be positive.");
        require((newRate + fundingRate + redistributionRate + burnRate) < 25, "EternalTokenV0::setRate(): Total rate exceeds 25%");

        uint8 oldRate;

        if (rate == Rate.Liquidity) {
            oldRate = liquidityProvisionRate;
            liquidityProvisionRate = newRate;
        } else if (rate == Rate.Funding) {
            oldRate = fundingRate;
            fundingRate = newRate;
        } else if (rate == Rate.Redistribution) {
            oldRate = redistributionRate;
            redistributionRate = newRate;
        } else {
            oldRate = burnRate;
            burnRate = newRate;
        }

        emit UpdateRate(oldRate, newRate, rate);
    }

    /**
     * @dev View the balance of a given user's address.
     * @param account The address of the user
     * @return The balance of the account
     */
    function balanceOf(address account) public view override returns (uint256){
        if (isExcludedFromRewards[account]) {
            return trueBalances[account];
        }
        return convertFromReflectedToTrueAmount(reflectedBalances[account]);
    }

    /**
     * @dev View the allowance of a given owner address for a given spender address.
     * @param owner The address of whom we are checking the allowance of
     * @param spender The address of whom we are checking the allowance for
     * @return The allowance of the owner for the spender
     */
    function allowance(address owner, address spender) external view override returns (uint256){
        return allowances[owner][spender];
    }
    
    /**
     * @dev View whether a given wallet or contract's address is excluded from transaction fees.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from transaction fees.
     */
    function isExcludedFromFee(address account) external view returns (bool) {
        return isExcludedFromFees[account];
    }

    /**
     * @dev View whether a given wallet or contract's address is excluded from rewards.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from rewards.
     */
    function isExcludedFromReward(address account) external view returns (bool) {
        return isExcludedFromRewards[account];
    }
    
    /**
     * @dev Excludes a given wallet or contract's address from accruing rewards. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be excluded from rewards.
     */
    function excludeFromReward(address account) public onlyOwner() {
        require(!isExcludedFromRewards[account], "EternalTokenV0::excludeFromReward(): Account is already excluded");
        if(reflectedBalances[account] > 0) {
            // Compute the true token balance from non-empty reflected balances and update it
            // since we must use both reflected and true balances to make our reflected-to-total ratio even
            trueBalances[account] =  convertFromReflectedToTrueAmount(reflectedBalances[account]);
        }
        isExcludedFromRewards[account] = true;
        excludedAddresses.push(account);
    }

    /**
     * @dev Allows a given wallet or contract's address to accrue rewards. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be accruing rewards.
     */
    function includeInReward(address account) external onlyOwner() {
        require(isExcludedFromRewards[account], "EternalTokenV0::includeInReward(): Account is already included");
        for (uint256 i = 0; i < excludedAddresses.length; i++) {
            if (excludedAddresses[i] == account) {
                // Swap last address with current address we want to include so that we can delete it
                excludedAddresses[i] = excludedAddresses[excludedAddresses.length - 1];
                // Set its deposit liabilities to 0 since we use the reserve balance for reward-accruing addresses
                trueBalances[account] = 0;
                excludedAddresses.pop();
                isExcludedFromRewards[account] = false;
                break;
            }
        }
    }
    
    /**
     * @dev Increases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are increasing the allowance for
     * @param addedValue The amount by which we increase the allowance
     * @return True if the increase in allowance is successful
     */
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] + addedValue));
        return true;
    }
    
    /**
     * @dev Decreases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are decrease the allowance for
     * @param subtractedValue The amount by which we decrease the allowance
     * @return True if the decrease in allowance is successful
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] - subtractedValue));
        return true;
    }
    
    /**
     * @dev Translates a given amount of ETRNL into its reflected sum variant (with the transfer fee deducted if specified).
     * @param amount The specified amount of ETRNL
     * @param deductTransferFee Boolean – True if we deduct the transfer fee from the reflected sum variant. False otherwise.
     * @return The reflected amount proportional to the given amount of ETRNL if False, else the fee-adjusted variant of said reflected amount
     *
     * Requirements:
     * 
     * - Given ETRNL amount cannot be greater than the total token supply
     */
    function convertFromTrueToReflectedAmount(uint256 amount, bool deductTransferFee) public view returns(uint256) {
        require(amount <= totalTokenSupply, "EternalTokenV0::convertFromTrueToReflectedAmount(): Amount must be less than total token supply");
        if (!deductTransferFee) {
            (uint256 reflectedAmount,,,) = getValues(amount);
            return reflectedAmount;
        } else {
            (,uint256 netReflectedTransferAmount,,) = getValues(amount);
            return netReflectedTransferAmount;
        }
    }

    /**
     * @dev Translates a given reflected sum of ETRNL into the true amount of ETRNL it represents based on the current reserve rate.
     * @param reflectedAmount The specified reflected sum of ETRNL
     * @return The true amount of ETRNL representing by its reflected amount
     * Requirements:
     * 
     * - Given reflected ETRNL amount cannot be greater than the total reflected token supply
     */
    function convertFromReflectedToTrueAmount(uint256 reflectedAmount) public view returns(uint256) {
        require(reflectedAmount <= totalReflectedSupply, "EternalTokenV0::convertFromReflectedToTrueAmount(): Amount must be less than total reflected supply");
        uint256 currentRate =  getRate();
        return reflectedAmount / currentRate;
    }

    /**
     * @dev Compute the reflected and net reflected transferred amounts and the net transferred amount from a given amount of ETRNL
     * @param trueAmount The specified amount of ETRNL
     * @return The reflected amount, the net reflected transfer amount, the actual net transfer amount, and the total reflected fees
     */
    function getValues(uint256 trueAmount) private view returns (uint256, uint256, uint256, uint256) {

        // Calculate the total fees and transfered amount after fees
        uint256 totalFees = (trueAmount * (liquidityProvisionRate + burnRate + fundingRate + redistributionRate)) / 100;
        uint256 netTransferAmount = trueAmount - totalFees;

        // Calculate the reflected amount, reflected total fees and reflected amount after fees
        uint256 currentRate = getRate();
        uint256 reflectedAmount = trueAmount * currentRate;
        uint256 reflectedTotalFees = totalFees * currentRate;
        uint256 netReflectedTransferAmount = reflectedAmount - reflectedTotalFees;
        
        return (reflectedAmount, netReflectedTransferAmount, netTransferAmount, totalFees * currentRate);
    }

    /**
     * @dev Computes the current rate used to inter-convert from the mathematically reflected space to the "true" or total space
     * @return The ratio of net reflected ETRNL to net total ETRNL
     */
    function getRate() private view returns(uint256) {
        (uint256 netReflectedSupply, uint256 netTokenSupply) = getNetSupplies();
        return netReflectedSupply / netTokenSupply;
    }

    /**
     * @dev Computes the net reflected and total token supplies (adjusted for non-reward-accruing accounts)
     * @return The adjusted reflected supply and adjusted total token supply
     */
    function getNetSupplies() private view returns(uint256, uint256) {
        uint256 netReflectedSupply = totalReflectedSupply;
        uint256 netTokenSupply = totalTokenSupply;  

        for (uint256 i = 0; i < excludedAddresses.length; i++) {
            // Failsafe for non-reward-accruing accounts owning too many tokens (highly unlikely; nonetheless possible)
            if (reflectedBalances[excludedAddresses[i]] > netReflectedSupply || trueBalances[excludedAddresses[i]] > netTokenSupply) {
                return (totalReflectedSupply, totalTokenSupply);
            }
            // Subtracting each excluded account from both supplies yields the adjusted supplies
            netReflectedSupply -= reflectedBalances[excludedAddresses[i]];
            netTokenSupply -= trueBalances[excludedAddresses[i]];
        }
        // In case there are no tokens left in circulation for reward-accruing accounts
        if (netTokenSupply == 0 || netReflectedSupply < (totalReflectedSupply / totalTokenSupply)){
            return (totalReflectedSupply, totalTokenSupply);
        }

        return (netReflectedSupply, netTokenSupply);
    }

    /**
     * @dev Tranfers a given amount of ETRNL to a given receiver address.
     * @param recipient The destination to which the ETRNL are to be transferred
     * @param amount The amount of ETRNL to be transferred
     * @return True if the transfer is successful.
     */
    function transfer(address recipient, uint256 amount) external override returns (bool){
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev Sets the allowance for a given address to a given amount.
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount we are changing the allowance to
     * @return True if the approval is successful.
     */
    function approve(address spender, uint256 amount) external override returns (bool){
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev Transfers a given amount of ETRNL for a given sender address to a given recipient address.
     * @param sender The address whom we withdraw the ETRNL from
     * @param recipient The address which shall receive the ETRNL
     * @param amount The amount of ETRNL which is being transferred
     * @return True if the transfer and approval are both successful.
     *
     * Requirements:
     * 
     * - The caller must be allowed to spend (at least) the given amount on the sender's behalf
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "EternalTokenV0::transferFrom(): transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    /**
     * @dev Sets the allowance of a given owner address for a given spender address to a given amount.
     * @param owner The adress of whom we are changing the allowance of
     * @param spender The address of whom we are changing the allowance for
     * @param amount The amount which we change the allowance to
     *
     * Requirements:
     * 
     * - Owner and spender cannot be the zero address
     */
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "EternalTokenV0::_approve(): approve from the zero address");
        require(spender != address(0), "EternalTokenV0::_approve(): approve to the zero address");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Transfers a given amount of ETRNL from a given sender's address to a given recipient's address.
     * Bottleneck for what transfer equation to use.
     * @param sender The address of whom the ETRNL will be transferred from
     * @param recipient The address of whom the ETRNL will be transferred to
     * @param amount The amount of ETRNL to be transferred
     * 
     * Requirements:
     * 
     * - Sender or recipient cannot be the zero address
     * - Transferred amount must be greater than zero
     */
    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "EternalTokenV0::_transfer(): transfer from the zero address");
        require(recipient != address(0), "EternalTokenV0::_transfer(): transfer to the zero address");
        require(amount > 0, "EternalTokenV0::_transfer(): transfer amount must be greater than zero");

        (uint256 reflectedAmount, uint256 netReflectedTransferAmount, uint256 netTransferAmount, uint256 totalReflectedFees) = getValues(amount);

        // Always update the reflected balances of sender and recipient
        reflectedBalances[sender] -= reflectedAmount;
        reflectedBalances[recipient] += netReflectedTransferAmount;

        // Update true balances for any non-reward-accruing accounts 
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender]; 
        trueBalances[recipient] = isExcludedFromRewards[recipient] ? (trueBalances[recipient] + netTransferAmount) : trueBalances[recipient]; 

        // Adjust the total reflected supply for the new fees
        // If the sender or recipient are excluded from fees, we ignore the fee altogether
        if (!isExcludedFromFees[sender] && !isExcludedFromFees[recipient]) {
            // Perform a burn based on the burn rate 
            _burn(address(this), amount * burnRate / 100, reflectedAmount * burnRate / 100) ;
            // Redistribute based on the redistribution rate 
            totalReflectedSupply -= reflectedAmount * redistributionRate / 100;
            // Store ETRNL away in the EternalFund based on the funding rate
            _store(reflectedAmount * fundingRate / 100);
            // Provide liqudity to the ETRNL/WAVAX pair on Pangolin based on the liquidity provision rate
            provideLiquidity(amount * liquidityProvisionRate / 100, reflectedAmount * liquidityProvisionRate / 100);
        }

        emit Transfer(sender, recipient, netTransferAmount);
    }

    /**
     * @dev Sends a given amount of ETRNL to the Eternal Fund.
     * @param amount
     */
    function _store(uint256 amount, uint256 reflectedAmount) private {
        totalReflectedSupply -= reflectedAmount;
    }
    
    /**
     * @dev Burns a given amount of ETRNL
     * @param amount The amount of ETRNL being burned
     * @return True if the burn is successful
     */
    function burn(uint256 amount) external returns (bool) {

        address sender = _msgSender();
        require(sender != address(0), "EternalTokenV0::burn(): burn from the zero address");

        uint256 balance = balanceOf(sender);
        require(balance >= amount, "EternalTokenV0::burn(): burn amount exceeds balance");

        // Subtract the amounts from the sender before so we can reuse _burn elsewhere
        uint256 reflectedAmount = convertFromTrueToReflectedAmount(amount, false);
        reflectedBalances[sender] -= reflectedAmount;
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender];

        _burn(sender, amount, reflectedAmount);
        return true;
    }
    
    /**
     * @dev Burns the specified amount of ETRNL for a given sender by sending them to the 0x0 address
     * @param sender The specified address burning ETRNL
     * @param amount The amount of ETRNL being burned
     * @param reflectedAmount The reflected equivalent of ETRNL being burned
     */
    function _burn(address sender, uint256 amount, uint256 reflectedAmount) private {
        // Send tokens to the 0x0 address
        reflectedBalances[address(0)] += reflectedAmount;
        trueBalances[address(0)] += amount;

        // Update supplies accordingly
        totalReflectedSupply -= reflectedAmount;
        totalTokenSupply -= amount;

        emit Transfer(sender, address(0), amount);
    }

    /**
     * @dev Swaps a given amount of ETRNL for AVAX using PangolinDEX. (Used for auto-liquidity swaps)
     * @param amount The amount of ETRNL to be swapped for AVAX
     */
    function swapTokensForAVAX(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pangolinRouter.WAVAX();

        _approve(address(this), address(pangolinRouter), amount);

        pangolinRouter.swapExactTokensForAVAXSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);
    }
    
    // Allows contract to receive AVAX tokens from Pangolin
    receive() external payable {}
}