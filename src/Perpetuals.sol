// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract Perpetuals {

    // Current Funding rate
    uint256 public fundingRate;
    // Open Interest
    uint256 public openInterest;
    // Total short position
    uint256 public totalShortPosition;
    // map users address => position opened
    mapping (address => uint256) addrToPosition;
    // Mock USDC contract address
    address public usdcToken;

    function short(uint256 _amount) external {
        // up OI, totalShortPos and map the position
        // Pull USDC from contract's / user's wallet first
        // Require allowance else will fail by revert

    }

    // Close short
    function closeShort(uint256 _amount) external {
        // close the position
        // Calculate the interest first before sending capital + interest, since mock perpetuals contract
        // No need for PNL calculation reduction in gas, not creating a full scale perps contract as that is heavy coding sorry prof

    }

    // Receive USDC for shorting

    // Future ref handle longs for funding rate flip

    // Withdraw function for me to retrieve my balance from contract

    // Liquidate position function? not needed in this context


    
}
