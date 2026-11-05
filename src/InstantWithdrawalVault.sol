// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractCallback } from "reactive-lib/base/AbstractCallback.sol";
import { IPayable } from "reactive-lib/interfaces/IPayable.sol";

interface IERC20Min {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title A vault whose withdrawal queue settles the moment liquidity returns.
/// @notice Deposits sit as idle liquidity until the owner deploys part of them elsewhere (a strategy, a loan book).
/// A withdrawal that idle liquidity cannot cover joins a FIFO queue. When liquidity comes back, `LiquidityAdded`
/// is emitted; a reactive contract on Reactive Network sees it and calls `settle()` through the callback proxy,
/// which pays the queue head first, as far as idle liquidity reaches. Nobody has to watch or poke the vault.
contract InstantWithdrawalVault is AbstractCallback {
    struct Request {
        address owner;
        uint128 amount;
        uint64 requestedAt;
        uint64 requestedBlock;
    }

    IERC20Min public immutable asset;
    address public immutable owner;
    /// @notice Reactive contract allowed to settle; set once after it is deployed on Reactive Network.
    address public callbackSender;

    mapping(address => uint256) public balanceOf;   // deposited and not yet withdrawn, in asset units
    uint256 public deployed;                         // liquidity lent out by the owner
    Request[] public requests;
    uint256 public head;                             // index of the oldest unpaid request
    uint256 public queuedTotal;

    event Deposited(address indexed user, uint256 amount);
    event WithdrawalQueued(uint256 indexed id, address indexed user, uint256 amount, uint256 queuedTotal);
    event WithdrawalPaid(uint256 indexed id, address indexed user, uint256 amount, uint256 waitSeconds, uint256 waitBlocks);
    event LiquidityDeployed(uint256 amount, uint256 idle);
    event LiquidityAdded(uint256 amount, uint256 idle, uint256 queuedTotal);
    event Settled(uint256 originBlock, uint256 paidCount, uint256 paidAmount, uint256 remainingQueued);

    error NotOwner();
    error InsufficientBalance();
    error AlreadySet();
    error NotAuthorizedSender(address sender);

    constructor(IERC20Min asset_, address callbackProxy_)
        payable
        AbstractCallback(IPayable(payable(callbackProxy_)), address(0))
    {
        asset = asset_;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setCallbackSender(address sender_) external onlyOwner {
        if (callbackSender != address(0)) revert AlreadySet();
        callbackSender = sender_;
    }

    function idle() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function queueLength() external view returns (uint256) {
        return requests.length - head;
    }

    function deposit(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Pays at once when idle liquidity covers it and nobody is waiting; otherwise joins the queue.
    function requestWithdrawal(uint256 amount) external returns (uint256 id) {
        if (amount == 0 || balanceOf[msg.sender] < amount) revert InsufficientBalance();
        balanceOf[msg.sender] -= amount;
        id = requests.length;
        requests.push(Request(msg.sender, uint128(amount), uint64(block.timestamp), uint64(block.number)));
        if (head == id && idle() >= amount) {
            head = id + 1;
            asset.transfer(msg.sender, amount);
            emit WithdrawalPaid(id, msg.sender, amount, 0, 0);
        } else {
            queuedTotal += amount;
            emit WithdrawalQueued(id, msg.sender, amount, queuedTotal);
        }
    }

    /// @notice Owner lends idle liquidity out (to a strategy or loan book), which is what makes the queue form.
    function deployLiquidity(address to, uint256 amount) external onlyOwner {
        deployed += amount;
        asset.transfer(to, amount);
        emit LiquidityDeployed(amount, idle());
    }

    /// @notice Anyone returning liquidity (a strategy repaying, a new depositor of reserves) calls this.
    function addLiquidity(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
        deployed = deployed > amount ? deployed - amount : 0;
        emit LiquidityAdded(amount, idle(), queuedTotal);
    }

    /// @notice Called through the callback proxy; the proxy injects the reactive contract's address as `sender`.
    function settle(address sender, uint256 originBlock, uint256 maxItems) external onlyServiceProvider {
        if (sender != callbackSender) revert NotAuthorizedSender(sender);
        uint256 available = idle();
        uint256 paid;
        uint256 paidAmount;
        uint256 h = head;
        while (h < requests.length && paid < maxItems) {
            Request memory r = requests[h];
            if (r.amount > available) break;
            available -= r.amount;
            paidAmount += r.amount;
            asset.transfer(r.owner, r.amount);
            emit WithdrawalPaid(h, r.owner, r.amount, block.timestamp - r.requestedAt, block.number - r.requestedBlock);
            ++h;
            ++paid;
        }
        head = h;
        queuedTotal -= paidAmount;
        emit Settled(originBlock, paid, paidAmount, queuedTotal);
    }
}
