// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./xToken.sol";
import "./AssetOracle.sol";


contract AssetPool is Ownable {
    xToken public tokenX;
    IERC20 public tokenY;
    AssetOracle public oracle;

    uint256 public totalDeposits; // Total USDC deposited
    uint256 public totalScaledDeposits; // Total scaled USDC equivalent

    event Deposited(address indexed user, uint256 amount, uint256 xTokenMinted);
    event Withdrawn(address indexed user, uint256 amount, uint256 xTokenBurned);
    event Rebalanced(uint256 lpAdded, uint256 lpWithdrawn);

    mapping(address => uint256) public scaledBalances;

    constructor(
        address _tokenY,
        address _oracle,
        string memory _xtokenName,
        string memory _xtokenSymbol
    ) Ownable(msg.sender) {
        tokenY = IERC20(_tokenY);
        oracle = AssetOracle(_oracle);
        tokenX = new xToken(_xtokenName, _xtokenSymbol, address(oracle));

    }

    function _getScaledBalance(uint256 amount, uint256 price) internal pure returns (uint256) {
        // Price is in cents, so divide by 100 to convert to a scaled factor
        return (amount * 1e18) / (price * 1e16);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        uint256 price = oracle.assetPrice();
        require(price > 0, "Invalid asset price");

        tokenY.transferFrom(msg.sender, address(this), amount);

        uint256 scaledAmount = _getScaledBalance(amount, price);
        totalDeposits += amount;
        totalScaledDeposits += scaledAmount;

        scaledBalances[msg.sender] += scaledAmount;
        tokenX.mint(msg.sender, scaledAmount);

        emit Deposited(msg.sender, amount, scaledAmount);
    }

    function withdraw(uint256 xtokenAmount) external {
        require(xtokenAmount > 0, "Amount must be greater than zero");
        require(tokenX.balanceOf(msg.sender) >= xtokenAmount, "Insufficient xToken balance");

        uint256 price = oracle.assetPrice();
        require(price > 0, "Invalid asset price");

        uint256 usdcAmount = (xtokenAmount * (price * 1e16)) / 1e18;
        require(usdcAmount <= tokenY.balanceOf(address(this)), "Insufficient USDC liquidity");

        tokenX.burn(msg.sender, xtokenAmount);
        scaledBalances[msg.sender] -= xtokenAmount;
        totalDeposits -= usdcAmount;
        totalScaledDeposits -= xtokenAmount;

        tokenY.transfer(msg.sender, usdcAmount);

        emit Withdrawn(msg.sender, usdcAmount, xtokenAmount);
    }

    function rebalance(uint256 lpAdded, uint256 lpWithdrawn) external onlyOwner {
        require(lpAdded > 0 || lpWithdrawn > 0, "Invalid rebalance amounts");

        if (lpAdded > 0) {
            tokenY.transferFrom(msg.sender, address(this), lpAdded);
            totalDeposits += lpAdded;
        }

        if (lpWithdrawn > 0) {
            require(lpWithdrawn <= tokenY.balanceOf(address(this)), "Insufficient USDC liquidity");
            tokenY.transfer(msg.sender, lpWithdrawn);
            totalDeposits -= lpWithdrawn;
        }

        emit Rebalanced(lpAdded, lpWithdrawn);
    }

}
