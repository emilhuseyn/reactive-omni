// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractReactive } from "reactive-lib/base/AbstractReactive.sol";
import { ISystemContract } from "reactive-lib/interfaces/ISystemContract.sol";

/// @title Reactive contract that settles a vault's withdrawal queue when liquidity returns.
/// @notice Subscribes to `LiquidityAdded` on one vault and, when the event says something is queued, asks the
/// system contract for a callback to the vault's `settle()`. On Reactive Omni (about 1 s blocks with instant
/// finality) the queue is paid within a few seconds of the liquidity landing.
contract QueueReactive is AbstractReactive {
    uint256 public constant LIQUIDITY_ADDED_TOPIC = uint256(keccak256("LiquidityAdded(uint256,uint256,uint256)"));
    uint64 public constant CALLBACK_GAS = 900_000;
    uint256 public constant MAX_ITEMS = 25;

    uint256 public immutable chainId;
    address public immutable vault;

    uint256 public triggers;

    event SettleRequested(uint256 originBlock, uint256 idle, uint256 queuedTotal);

    constructor(uint256 chainId_, address vault_) payable {
        chainId = chainId_;
        vault = vault_;
        SYSTEM.subscribe(chainId_, vault_, LIQUIDITY_ADDED_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function react(LogRecord calldata log_) external onlySystem {
        if (log_.contractAddress != vault || log_.topic0 != LIQUIDITY_ADDED_TOPIC) return;
        (, uint256 idleNow, uint256 queued) = abi.decode(log_.data, (uint256, uint256, uint256));
        if (queued == 0) return;
        ++triggers;
        bytes memory payload = abi.encodeWithSignature(
            "settle(address,uint256,uint256)", address(0), log_.blockNumber, MAX_ITEMS
        );
        SYSTEM.requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0(chainId, vault, CALLBACK_GAS, payload));
        emit SettleRequested(log_.blockNumber, idleNow, queued);
    }
}
