//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract Lending {
    // Only handle eth loans
    // lend at 2% APR average of ethstaking yield

    uint256 public constant APR = 200; // 2% annual (200 basis points)
    uint256 public constant YEAR = 365 days;
    struct DepositInfo {
        uint256 amount;      // ETH deposited
        uint256 lastUpdate;  // timestamp of last deposit or withdrawal
    }

    mapping(address => DepositInfo) public deposits;
    uint256 public totalDeposits;
    address public owner;

    constructor() {
        owner = msg.sender;
    }


    function deposit() external payable {
        require(msg.value > 0, "No ETH sent");

        DepositInfo storage user = deposits[msg.sender];

        // Accrue yield before updating
        uint256 pendingInterest = _calculateInterest(msg.sender);
        if (pendingInterest > 0) {
            // Add earned interest to principal
            user.amount += pendingInterest;
            totalDeposits += pendingInterest;
        }

        // Add new deposit
        user.amount += msg.value;
        user.lastUpdate = block.timestamp;
        totalDeposits += msg.value;
    }

    function withdraw(uint256 _amount) external {
        DepositInfo storage user = deposits[msg.sender];
        require(user.amount > 0, "No balance");

        uint256 pendingInterest = _calculateInterest(msg.sender);
        if (pendingInterest > 0) {
            user.amount += pendingInterest;
            totalDeposits += pendingInterest;
        }

        require(_amount > 0 && _amount <= user.amount, "Invalid amount");


        // Withdraw requested amount
        user.amount -= _amount;
        totalDeposits -= _amount;
        user.lastUpdate = block.timestamp;

        (bool sent, ) = payable(msg.sender).call{value: _amount}("");
        require(sent, "ETH transfer failed");
    }


    function getAccruedBalance(address _user) public view returns (uint256) {
        DepositInfo memory user = deposits[_user];
        if (user.amount == 0) return 0;
        uint256 interest = _pendingInterest(user);
        return user.amount + interest;
    }


    function _calculateInterest(address _user) internal view returns (uint256) {
        DepositInfo memory user = deposits[_user];
        if (user.amount == 0) return 0;
        return _pendingInterest(user);
    }

    function _pendingInterest(DepositInfo memory user) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - user.lastUpdate;
        // Simple interest: principal * rate * time / year
        uint256 interest = (user.amount * APR * timeElapsed) / (YEAR * 10000);
        return interest;
    }


    function ownerWithdraw(uint256 _amount) external {
        require(msg.sender == owner, "Not owner");
        (bool sent, ) = payable(owner).call{value: _amount}("");
        require(sent, "Withdraw failed");
    }

    receive() external payable {}
}