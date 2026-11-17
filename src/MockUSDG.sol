// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDG — testnet stand-in for Paxos USDG (6 decimals)
/// @notice Demo token only. Anyone can mint on testnet; it is NOT the real
/// USDG. Used so the BRLPay demo runs end-to-end on Arbitrum Sepolia
/// without needing a real USDG faucet.
contract MockUSDG is ERC20 {
    constructor() ERC20("Mock Paxos USDG", "mUSDG") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
