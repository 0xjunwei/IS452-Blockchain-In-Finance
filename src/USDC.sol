// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// got it from openzeppelin erc20 standards
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract USDC is ERC20, ERC20Permit {
    constructor(address recipient) ERC20("USDC", "USDC") ERC20Permit("USDC") {
        _mint(recipient, 100000000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
