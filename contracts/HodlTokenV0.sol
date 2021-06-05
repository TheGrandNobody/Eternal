//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinFactory.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol";

/**
 * @title Contract for the HODL Token (HODLS)
 * @author Nobody (credits to OpenZeppelin for the IERC20 and IERC20Metadata interfaces)
 * @notice The HODL Token contract holds 
 */
contract HodlTokenV0 is Context, IERC20, IERC20Metadata, Ownable {

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

    // The largest possible number in a 256-bit integer
    uint256 private constant MAX = ~uint256(0);
    // The true total token supply 
    uint256 private totalTokenSupply = (10**10) * (10**9);
    // The total token supply after taking reflections into account
    uint256 private totalReflectedSupply;
    // The percentage of the total fee rate used to auto-lock liquidity
    uint256 private liquidityRate;
    // The percentage of the total fee rate stored in the HODLFund
    uint256 private storageRate;
    // The percentage of the total fee rate that is burned
    uint256 private burnRate;
    // The percentage of the total fee rate redistributed to HODLers
    uint256 private redistributionRate;

    // PangolinDex Router interface to swap tokens for WAVAX and add liquidity
    IPangolinRouter internal immutable pangolinRouter;
    // The address of the HODLS/WAVAX pair
    address internal immutable pangolinPair;

    /**
     * @dev Sets the token ticker and token name. Mints the total supply to the contract deployer.
     */
    constructor () {
        // Initialize name, ticker symbol and total supply
        totalReflectedSupply = (MAX - (MAX % totalTokenSupply));
        reflectedBalances[_msgSender()] = totalTokenSupply;

        // Create pair address
        IPangolinRouter _pangolinRouter = IPangolinRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
        pangolinPair = IPangolinFactory(_pangolinRouter.factory()).createPair(address(this), _pangolinRouter.WAVAX());

        // Initialize Pangolin Router
        pangolinRouter = _pangolinRouter;

        // Exclude the owner from rewards
        isExcludedFromRewards[owner()] = true;
        excludedAddresses.push(owner());
        // Exclude this contract from rewards
        isExcludedFromRewards[address(this)] = true;
        excludedAddresses.push(address(this));
    }

    /**
     * @dev The name of the token. 
     * @return The token name
     */
    function name() external pure override returns (string memory) {
        return "HODL Token";
    }

    /**
     * @dev View the token ticker
     * @return The token symbol
     */
    function symbol() external pure override returns (string memory) {
        return "HODLS";
    }

    /**
     * @dev View the maximum number of decimals for the HODL token
     * @return The number of decimals
     */
    function decimals() external pure override returns (uint8) {
        return 9;
    }
    
    /**
     * @dev View the total supply of the HODL token.
     * @return Returns the total HODLS supply.
     */
    function totalSupply() external view override returns (uint256){
        return totalTokenSupply;
    }

    /**
     * @dev View the balance of a given user's address.
     * @param account The address of the user
     * @return The balance of the account
     */
    function balanceOf(address account) external view override returns (uint256){
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
    function isExcludedFromFee(address account) public view returns (bool) {
        return isExcludedFromFees[account];
    }

    /**
     * @dev View whether a given wallet or contract's address is excluded from rewards.
     * @param account The wallet or contract's address
     * @return Whether the account is excluded from rewards.
     */
    function isExcludedFromReward(address account) public view returns (bool) {
        return isExcludedFromRewards[account];
    }
    
    /**
     * @dev Excludes a given wallet or contract's address from accruing rewards. (Owner only)
     * @param account The wallet or contract's address
     *
     * Requirements:
     * – Account must not already be excluded from rewards.
     */
    function excludeFromReward(address account) external onlyOwner() {
        require(!isExcludedFromRewards[account], "HodlTokenV0::excludeFromReward(): Account is already excluded.");
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
        require(isExcludedFromRewards[account], "HodlTokenV0::IncludeInReward(): Account is already included");
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
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] + addedValue));
        return true;
    }
    
    /**
     * @dev Decreases the allowance for a given spender address by a given amount.
     * @param spender The address whom we are decrease the allowance for
     * @param subtractedValue The amount by which we decrease the allowance
     * @return True if the decrease in allowance is successful
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, (allowances[_msgSender()][spender] - subtractedValue));
        return true;
    }
    
    /**
     * @dev Translates a given amount of HODLS into its reflected sum variant (with the transfer fee deducted if specified).
     * @param amount The specified amount of HODLS
     * @param deductTransferFee Boolean – True if we deduct the transfer fee from the reflected sum variant. False otherwise.
     * @return The reflected amount proportional to the given amount of HODLS if False, else the fee-adjusted variant of said reflected amount
     *
     * Requirements:
     * 
     * - Given HODLS amount cannot be greater than the total token supply
     */
    function convertFromTrueToReflectedAmount(uint256 amount, bool deductTransferFee) public view returns(uint256) {
        require(amount <= totalTokenSupply, "HodlTokenV0::convertFromTrueToReflectedAmount(): Amount must be less than total token supply");
        if (!deductTransferFee) {
            (uint256 reflectedAmount,,,) = getValues(amount);
            return reflectedAmount;
        } else {
            (,uint256 netReflectedTransferAmount,,) = getValues(amount);
            return netReflectedTransferAmount;
        }
    }

    /**
     * @dev Translates a given reflected sum of HODLS into the true amount of HODLS it represents based on the current reserve rate.
     * @param reflectedAmount The specified reflected sum of HODLS
     * @return The true amount of HODLS representing by its reflected amount
     * Requirements:
     * 
     * - Given reflected HODLS amount cannot be greater than the total reflected token supply
     */
    function convertFromReflectedToTrueAmount(uint256 reflectedAmount) public view returns(uint256) {
        require(reflectedAmount <= totalReflectedSupply, "HodlTokenV0::convertFromReflectedToTrueAmount(): Amount must be less than total reflected supply");
        uint256 currentRate =  getRate();
        return reflectedAmount / currentRate;
    }

    /**
     * @dev Compute the reflected and net reflected transferred amounts and the net transferred amount from a given amount of HODLS
     * @param trueAmount The specified amount of HODLS
     * @return The reflected amount, the net reflected transfer amount, the actual net transfer amount, and the total reflected fees
     */
    function getValues(uint256 trueAmount) internal view returns (uint256, uint256, uint256, uint256) {

        // Calculate the total fees and transfered amount after fees
        uint256 totalFees = (trueAmount * (liquidityRate + burnRate + storageRate + redistributionRate)) / 100;
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
     * @return The ratio of net reflected HODLS to net total HODLS
     */
    function getRate() internal view returns(uint256) {
        (uint256 netReflectedSupply, uint256 netTokenSupply) = getNetSupplies();
        return netReflectedSupply / netTokenSupply;
    }

    /**
     * @dev Computes the net reflected and total token supplies (adjusted for non-reward-accruing accounts)
     * @return The adjusted reflected supply and adjusted total token supply
     */
    function getNetSupplies() internal view returns(uint256, uint256) {
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
     * @dev Tranfers a given amount of HODLS to a given receiver address.
     * @param recipient The destination to which the HODLS are to be transferred
     * @param amount The amount of HODLS to be transferred
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
     * @dev Transfers a given amount of HODLS for a given sender address to a given recipient address.
     * @param sender The address whom we withdraw the HODLS from
     * @param recipient The address which shall receive the HODLS
     * @param amount The amount of HODLS which is being transferred
     * @return True if the transfer and approval are both successful.
     *
     * Requirements:
     * 
     * - The caller must be allowed to spend (at least) the given amount on the sender's behalf
     */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "HodlTokenV0::transferFrom(): transfer amount exceeds allowance");
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
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "HodlTokenV0::_approve(): approve from the zero address");
        require(spender != address(0), "HodlTokenV0::_approve(): approve to the zero address");

        allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Transfers a given amount of HODLS from a given sender's address to a given recipient's address.
     * Bottleneck for what transfer equation to use.
     * @param sender The address of whom the HODLS will be transferred from
     * @param recipient The address of whom the HODLS will be transferred to
     * @param amount The amount of HODLS to be transferred
     * 
     * Requirements:
     * 
     * - Sender or recipient cannot be the zero address
     * - Transferred amount must be greater than zero
     */
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "HodlTokenV0::_transfer(): transfer from the zero address");
        require(recipient != address(0), "HodlTokenV0::_transfer(): transfer to the zero address");
        require(amount > 0, "HodlTokenV0::_transfer(): transfer amount must be greater than zero");

        (uint256 reflectedAmount, uint256 netReflectedTransferAmount, uint256 netTransferAmount, uint256 totalReflectedFees) = getValues(amount);

        // Always update the reflected balances of sender and recipient
        reflectedBalances[sender] -= reflectedAmount;
        reflectedBalances[recipient] += netReflectedTransferAmount;

        // Update true balances for any non-reward-accruing accounts 
        trueBalances[sender] = isExcludedFromRewards[sender] ? (trueBalances[sender] - amount) : trueBalances[sender]; 
        trueBalances[recipient] = isExcludedFromRewards[recipient] ? (trueBalances[recipient] + netTransferAmount) : trueBalances[recipient]; 

        // Adjust the total reflected supply for the new fees
        // If the sender or recipient are excluded from fees, we ignore the fee altogether
        totalReflectedSupply = (isExcludedFromFees[sender] || isExcludedFromFees[recipient]) ? (totalReflectedSupply - totalReflectedFees) : totalReflectedSupply;

        emit Transfer(sender, recipient, netTransferAmount);
    }

    /**
     * @dev Swaps a given amount of HODLS for AVAX using PangolinDEX. (Used for auto-liquidity swaps)
     * @param amount The amount of HODLS to be swapped for AVAX
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