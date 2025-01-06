// SPDX-License-Identifier: AGPL-3.0
// author: bhargavaparoksham

pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./AssetOracle.sol";

contract xToken is ERC20 {
    AssetOracle public oracle;
    address public pool;

    uint256 public constant XTOKEN_VERSION = 0x1;
    mapping(address => uint256) private _scaledBalances;

    modifier onlyPool() {
        require(msg.sender == pool, "Only pool can call this function");
        _;
    }

    constructor(string memory name, string memory symbol, address _oracle) ERC20(name, symbol) {
        oracle = AssetOracle(_oracle);
        pool = msg.sender;
    }

    function scaledBalanceOf(address account) public view returns (uint256) {
        return _scaledBalances[account];
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 price = oracle.assetPrice();
        require(price > 0, "Invalid asset price");
        return (_scaledBalances[account] * (price * 1e16)) / 1e18;
    }

    function totalScaledSupply() public view returns (uint256) {
        uint256 price = oracle.assetPrice();
        require(price > 0, "Invalid asset price");
        return (totalSupply() / (price * 1e16) / 1e18);
    }

    function mint(address account, uint256 amount) external onlyPool {
        uint256 price = oracle.assetPrice();
        require(price > 0, "Invalid asset price");
        uint256 scaledAmount = (amount * 1e18) / (price * 1e16);
        _scaledBalances[account] += scaledAmount;
        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) external onlyPool {
        uint256 price = oracle.assetPrice();
        require(price > 0, "Invalid asset price");
        uint256 scaledAmount = (amount * 1e18) / (price * 1e16);
        require(_scaledBalances[account] >= scaledAmount, "Insufficient balance");
        _scaledBalances[account] -= scaledAmount;
        emit Transfer(account, address(0), amount);
    }
}