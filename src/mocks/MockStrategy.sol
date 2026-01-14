// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockStrategy is Ownable {
    IERC20 public asset;
    uint256 public totalAssets;
    uint256 public lockupEnd;

    mapping(address => bool) public approvedWithdrawers;

    constructor(address _asset) Ownable(msg.sender) {
        asset = IERC20(_asset);
    }

    function setApproved(address _addr, bool _state) external onlyOwner {
        approvedWithdrawers[_addr] = _state;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        asset.transferFrom(msg.sender, address(this), amount);
        totalAssets += amount;
    }

    function withdraw(uint256 amount) external {
        require(msg.sender == owner() || approvedWithdrawers[msg.sender], "Strategy: Unauthorized");
        require(block.timestamp >= lockupEnd, "Strategy: Locked");
        require(amount <= totalAssets, "Strategy: Insufficient funds");

        totalAssets -= amount;
        asset.transfer(msg.sender, amount);
    }

    function setLockup(uint256 duration) external onlyOwner {
        lockupEnd = block.timestamp + duration;
    }

    function simulateYield(int256 delta) external onlyOwner {
        if (delta > 0) {
            totalAssets += uint256(delta);
        } else {
            uint256 loss = uint256(-delta);
            if (loss > totalAssets) totalAssets = 0;
            else totalAssets -= loss;
        }
    }
}
