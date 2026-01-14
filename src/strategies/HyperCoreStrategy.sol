// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICoreWriter} from "../interfaces/ICoreWriter.sol";

/**
 * @title HyperCoreStrategy
 * @notice Adapter strategy for interacting with HyperLiquid's HyperCore.
 * @dev Manages deposits into HyperLP (HLP) via the CoreWriter contract.
 */
contract HyperCoreStrategy is Ownable {
    IERC20 public asset;
    ICoreWriter public coreWriter;
    
    /// @notice Tracks total assets deposited into the strategy (simulated).
    uint256 public totalAssets;

    /**
     * @notice Initializes the strategy.
     * @param _asset The underlying asset (OSDC).
     * @param _coreWriter The HyperCore CoreWriter address.
     */
    constructor(address _asset, address _coreWriter) Ownable(msg.sender) {
        asset = IERC20(_asset);
        coreWriter = ICoreWriter(_coreWriter);
    }

    /**
     * @notice Sets the total asset value directly (Mock/Simulation only).
     * @dev Used because we cannot easily read HLP value on-chain without an oracle.
     * @param _assets The new total asset value.
     */
    function setTotalAssets(uint256 _assets) external onlyOwner {
        totalAssets = _assets;
    }

    /**
     * @notice Deposits assets into the strategy.
     * @dev Transfers assets from caller, approves CoreWriter, and executes Action ID 2 (HLP Deposit).
     * @param amount The amount of assets to deposit.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Amount > 0");
        asset.transferFrom(msg.sender, address(this), amount);
        
        // Prepare params for HyperCore Action 2 (Deposit)
        // Format: abi.encode(amount, destination)
        bytes memory params = abi.encode(amount, address(this));
        
        // Approve CoreWriter to spend tokens if needed (depending on implementation)
        // safeApprove or just standard approve
        asset.approve(address(coreWriter), amount); 
        
        // Execute the action on HyperCore
        coreWriter.ensureAction(2, params); 
        
        totalAssets += amount;
    }

    /**
     * @notice Withdraws assets from the strategy.
     * @dev For mock/testnet purposes, this simply transfers assets back.
     *      In prod, this would trigger a withdrawal action on HyperCore.
     * @param amount The amount to withdraw.
     */
    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= totalAssets, "Insufficient strategy balance");
        totalAssets -= amount;
        asset.transfer(msg.sender, amount);
    }
}
