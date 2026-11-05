// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { InstantWithdrawalVault, IERC20Min } from "../src/InstantWithdrawalVault.sol";
import { QueueReactive } from "../src/QueueReactive.sol";
import { MockUSD } from "../src/MockUSD.sol";
import { ISystemContract } from "reactive-lib/interfaces/ISystemContract.sol";
import { IReactive } from "reactive-lib/interfaces/IReactive.sol";

/// Stands in for the Reactive Network system contract at 0x8888...: records subscriptions and callback requests.
contract MockSystem {
    uint256 public subscriptions;
    ISystemContract.CallbackConfiguration_V_1_0 public last;
    uint256 public callbacks;

    receive() external payable {}

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        ++subscriptions;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory c) external {
        last = c;
        ++callbacks;
    }
}

contract QueueTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address proxy = makeAddr("callbackProxy");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address strategy = makeAddr("strategy");

    MockUSD usd;
    InstantWithdrawalVault vault;
    QueueReactive reactive;
    MockSystem sys;

    function setUp() public {
        vm.etch(SYSTEM, address(new MockSystem()).code);
        sys = MockSystem(payable(SYSTEM));
        usd = new MockUSD();
        vault = new InstantWithdrawalVault(IERC20Min(address(usd)), proxy);
        reactive = new QueueReactive(block.chainid, address(vault));
        vault.setCallbackSender(address(reactive));

        for (uint256 i; i < 2; ++i) {
            address u = i == 0 ? alice : bob;
            usd.mint(u, 100e6);
            vm.startPrank(u);
            usd.approve(address(vault), type(uint256).max);
            vault.deposit(100e6);
            vm.stopPrank();
        }
        vault.deployLiquidity(strategy, 150e6); // 50e6 idle left
        vm.prank(strategy);
        usd.approve(address(vault), type(uint256).max);
    }

    function _liquidityLog(uint256 amount) internal view returns (IReactive.LogRecord memory log_) {
        log_.chainId = block.chainid;
        log_.contractAddress = address(vault);
        log_.topic0 = reactive.LIQUIDITY_ADDED_TOPIC();
        log_.data = abi.encode(amount, vault.idle(), vault.queuedTotal());
        log_.blockNumber = block.number;
    }

    function _deliver() internal {
        (uint256 chainId, address recipient,, bytes memory payload) = sys.last();
        assertEq(chainId, block.chainid);
        assertEq(recipient, address(vault));
        // The proxy replaces the first argument with the reactive contract's address before calling.
        (, uint256 originBlock, uint256 maxItems) = abi.decode(_args(payload), (address, uint256, uint256));
        vm.prank(proxy);
        vault.settle(address(reactive), originBlock, maxItems);
    }

    function _args(bytes memory payload) internal pure returns (bytes memory out) {
        out = new bytes(payload.length - 4);
        for (uint256 i; i < out.length; ++i) out[i] = payload[i + 4];
    }

    function test_subscribesOnDeploy() public view {
        assertEq(sys.subscriptions(), 1);
    }

    function test_paysAtOnceWhenIdleCoversAndNobodyWaits() public {
        vm.prank(bob);
        vault.requestWithdrawal(50e6);
        assertEq(usd.balanceOf(bob), 50e6);
        assertEq(vault.queueLength(), 0);
    }

    function test_queueIsFifoEvenWhenALaterRequestWouldFit() public {
        vm.prank(alice);
        vault.requestWithdrawal(100e6); // idle 50: queued
        vm.prank(bob);
        vault.requestWithdrawal(50e6);  // would fit, but Alice is first: queued behind her
        assertEq(vault.queueLength(), 2);
        assertEq(usd.balanceOf(bob), 0);
    }

    function test_liquidityTriggersSettlementOfTheWholeQueue() public {
        vm.prank(alice);
        vault.requestWithdrawal(100e6);
        vm.prank(bob);
        vault.requestWithdrawal(50e6);
        vm.prank(strategy);
        vault.addLiquidity(100e6);       // idle 150
        IReactive.LogRecord memory log_ = _liquidityLog(100e6);
        vm.prank(SYSTEM);
        reactive.react(log_);
        assertEq(sys.callbacks(), 1);
        _deliver();
        assertEq(usd.balanceOf(alice), 100e6);
        assertEq(usd.balanceOf(bob), 50e6);
        assertEq(vault.queuedTotal(), 0);
        assertEq(vault.queueLength(), 0);
    }

    function test_partialLiquidityKeepsTheHeadWaiting() public {
        vm.prank(alice);
        vault.requestWithdrawal(100e6);
        vm.prank(strategy);
        vault.addLiquidity(10e6);        // idle 60 < 100
        IReactive.LogRecord memory log_ = _liquidityLog(10e6);
        vm.prank(SYSTEM);
        reactive.react(log_);
        _deliver();
        assertEq(usd.balanceOf(alice), 0);
        assertEq(vault.queueLength(), 1);
    }

    function test_noCallbackWhenNothingIsQueued() public {
        vm.prank(strategy);
        vault.addLiquidity(10e6);
        IReactive.LogRecord memory log_ = _liquidityLog(10e6);
        vm.prank(SYSTEM);
        reactive.react(log_);
        assertEq(sys.callbacks(), 0);
    }

    function test_reactRejectsCallersOtherThanTheSystem() public {
        IReactive.LogRecord memory log_ = _liquidityLog(1);
        vm.expectRevert();
        reactive.react(log_);
    }

    function test_settleRejectsAnyoneButTheProxy() public {
        vm.expectRevert();
        vault.settle(address(reactive), 1, 25);
    }

    function test_settleRejectsAForeignReactiveContract() public {
        vm.prank(proxy);
        vm.expectRevert(abi.encodeWithSelector(InstantWithdrawalVault.NotAuthorizedSender.selector, address(0xBAD)));
        vault.settle(address(0xBAD), 1, 25);
    }
}
