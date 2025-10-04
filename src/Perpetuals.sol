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

    function short(uint256 _amount) external {
        // up OI, totalShortPos and map the position
        
    }

    // Close short
    function closeShort(uint256 _amount) external {
        // close the position
    }

    // Receive USDC for shorting

    // Future ref handle longs for funding rate flip

    // Withdraw function for me to retrieve my balance from contract

    // Liquidate position function? not needed in this context


    
}
