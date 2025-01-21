// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./util/AragonTest.sol";
import {DaoBuilder} from "./util/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {LockToApprovePlugin} from "../src/LockToApprovePlugin.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {ILockToVote} from "../src/interfaces/ILockToVote.sol";
import {LockManagerSettings, UnlockMode, PluginMode} from "../src/interfaces/ILockManager.sol";
import {IMajorityVoting} from "../src/interfaces/IMajorityVoting.sol";
import {LockManager} from "../src/LockManager.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockManagerTest is AragonTest {
    DaoBuilder builder;
    DAO dao;
    LockToApprovePlugin ltaPlugin;
    LockToVotePlugin ltvPlugin;
    LockManager lockManager;
    IERC20 lockableToken;
    IERC20 underlyingToken;
    uint256 proposalId;

    address immutable LOCK_TO_VOTE_BASE = address(new LockToApprovePlugin());
    address immutable LOCK_MANAGER_BASE =
        address(
            new LockManager(
                IDAO(address(0)),
                LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
                IERC20(address(0)),
                IERC20(address(0))
            )
        );

    event BalanceLocked(address voter, uint256 amount);
    event BalanceUnlocked(address voter, uint256 amount);
    event ProposalEnded(uint256 proposalId);

    error InvalidUnlockMode();
    error NoBalance();
    error NoNewBalance();

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) = builder
            .withTokenHolder(alice, 1 ether)
            .withTokenHolder(bob, 10 ether)
            .withTokenHolder(carol, 10 ether)
            .withTokenHolder(david, 15 ether)
            .withStrictUnlock()
            .withApprovalPlugin()
            .build();
    }

    modifier givenDeployingTheContract() {
        _;
    }

    function test_RevertWhen_ConstructorHasInvalidUnlockMode() external givenDeployingTheContract {
        // It Should revert
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidUnlockMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode(uint8(2)), PluginMode.Approval),
            IERC20(address(0)),
            IERC20(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidUnlockMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode(uint8(0)), PluginMode.Approval),
            IERC20(address(0)),
            IERC20(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidUnlockMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode(uint8(2)), PluginMode.Voting),
            IERC20(address(0)),
            IERC20(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidUnlockMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode(uint8(0)), PluginMode.Voting),
            IERC20(address(0)),
            IERC20(address(0))
        );

        // OK
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            IERC20(address(0)),
            IERC20(address(0))
        );
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Early, PluginMode.Approval),
            IERC20(address(0)),
            IERC20(address(0))
        );
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Strict, PluginMode.Voting),
            IERC20(address(0)),
            IERC20(address(0))
        );
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Early, PluginMode.Voting),
            IERC20(address(0)),
            IERC20(address(0))
        );
    }

    function test_RevertWhen_ConstructorHasInvalidPluginMode() external givenDeployingTheContract {
        // It Should revert
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPluginMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Strict, PluginMode(uint8(3))),
            IERC20(address(0)),
            IERC20(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPluginMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Early, PluginMode(uint8(0))),
            IERC20(address(0)),
            IERC20(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPluginMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Strict, PluginMode(uint8(3))),
            IERC20(address(0)),
            IERC20(address(0))
        );
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPluginMode.selector));
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Early, PluginMode(uint8(0))),
            IERC20(address(0)),
            IERC20(address(0))
        );

        // OK
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            IERC20(address(0)),
            IERC20(address(0))
        );
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Early, PluginMode.Approval),
            IERC20(address(0)),
            IERC20(address(0))
        );
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Strict, PluginMode.Voting),
            IERC20(address(0)),
            IERC20(address(0))
        );
        new LockManager(
            IDAO(address(0)),
            LockManagerSettings(UnlockMode.Early, PluginMode.Voting),
            IERC20(address(0)),
            IERC20(address(0))
        );
    }

    function test_WhenConstructorWithValidParams() external givenDeployingTheContract {
        // It Registers the DAO address
        // It Stores the given settings
        // It Stores the given token addresses

        // 1
        lockManager = new LockManager(
            IDAO(address(1234)),
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            IERC20(address(2345)),
            IERC20(address(3456))
        );
        assertEq(address(lockManager.dao()), address(1234));
        assertEq(address(lockManager.token()), address(2345));
        assertEq(address(lockManager.underlyingToken()), address(3456));
        (UnlockMode um, PluginMode pm) = lockManager.settings();
        assertEq(uint8(um), uint8(UnlockMode.Strict));
        assertEq(uint8(pm), uint8(PluginMode.Approval));

        // 2
        lockManager = new LockManager(
            IDAO(address(5555)),
            LockManagerSettings(UnlockMode.Early, PluginMode.Voting),
            IERC20(address(6666)),
            IERC20(address(7777))
        );
        assertEq(address(lockManager.dao()), address(5555));
        assertEq(address(lockManager.token()), address(6666));
        assertEq(address(lockManager.underlyingToken()), address(7777));
        assertEq(uint8(um), uint8(UnlockMode.Early));
        assertEq(uint8(pm), uint8(PluginMode.Voting));
    }

    modifier whenCallingSetPluginAddress() {
        _;
    }

    function test_RevertGiven_InvalidPlugin() external whenCallingSetPluginAddress {
        // It should revert

        // 1
        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            lockableToken,
            underlyingToken
        );
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPlugin.selector));
        lockManager.setPluginAddress(LockToApprovePlugin(address(0x5555)));

        // 2
        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Early, PluginMode.Voting),
            lockableToken,
            underlyingToken
        );
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPlugin.selector));
        lockManager.setPluginAddress(LockToApprovePlugin(address(0x5555)));
    }

    function test_RevertGiven_InvalidPluginInterface() external whenCallingSetPluginAddress {
        // It should revert

        // 1
        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            lockableToken,
            underlyingToken
        );
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPlugin.selector));
        lockManager.setPluginAddress(new LockToVotePlugin());

        // 2
        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Early, PluginMode.Voting),
            lockableToken,
            underlyingToken
        );
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPlugin.selector));
        lockManager.setPluginAddress(new LockToApprovePlugin());

        // ok
        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Early, PluginMode.Approval),
            lockableToken,
            underlyingToken
        );
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(new LockToApprovePlugin());
    }

    function test_RevertWhen_SetPluginAddressWithoutThePermission() external whenCallingSetPluginAddress {
        // It should revert

        (, LockToApprovePlugin ltaPlugin2, , , , ) = builder.build();
        (, LockToApprovePlugin ltaPlugin3, , , , ) = builder.build();
        (, , LockToVotePlugin ltvPlugin2, , , ) = builder.withVotingPlugin().build();

        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            lockableToken,
            underlyingToken
        );

        // 1
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(lockManager),
                alice,
                lockManager.UPDATE_SETTINGS_PERMISSION_ID()
            )
        );
        lockManager.setPluginAddress(ltaPlugin2);

        // 2
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(lockManager),
                alice,
                lockManager.UPDATE_SETTINGS_PERMISSION_ID()
            )
        );
        lockManager.setPluginAddress(ltaPlugin3);

        // OK

        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(ltaPlugin2);

        // OK 2

        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Voting),
            lockableToken,
            underlyingToken
        );
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(ltvPlugin2);
    }

    function test_WhenSetPluginAddressWithThePermission() external whenCallingSetPluginAddress {
        // It should update the address
        // It should revert if trying to update it later

        (, LockToApprovePlugin ltaPlugin2, , , , ) = builder.build();
        (, , LockToVotePlugin ltvPlugin2, , , ) = builder.withVotingPlugin().build();

        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            lockableToken,
            underlyingToken
        );
        assertEq(address(lockManager.plugin()), address(0));
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(ltaPlugin2);
        assertEq(address(lockManager.plugin()), address(ltaPlugin2));

        // OK 2

        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Voting),
            lockableToken,
            underlyingToken
        );
        assertEq(address(lockManager.plugin()), address(0));
        dao.grant(address(lockManager), alice, lockManager.UPDATE_SETTINGS_PERMISSION_ID());
        lockManager.setPluginAddress(ltvPlugin2);
        assertEq(address(lockManager.plugin()), address(ltvPlugin2));

        // Attempt to set when already defined
        vm.expectRevert(abi.encodeWithSelector(LockManager.SetPluginAddressForbidden.selector));
        lockManager.setPluginAddress(ltaPlugin2);
    }

    modifier givenProposalOnLockToApprove() {
        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        _;
    }

    modifier givenProposalOnLockToVote() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) = builder.withVotingPlugin().build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        _;
    }

    modifier givenNoLockedTokens() {
        _;
    }

    modifier givenNoTokenAllowanceNoLocked() {
        _;
    }

    function test_RevertWhen_CallingLock1() external givenNoLockedTokens givenNoTokenAllowanceNoLocked {
        // It Should revert

        // 1
        vm.startPrank(randomWallet);
        assertEq(lockableToken.balanceOf(randomWallet), 0);
        assertEq(lockableToken.allowance(randomWallet, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        // 2
        vm.startPrank(address(0x1234));
        assertEq(lockableToken.balanceOf(address(0x1234)), 0);
        assertEq(lockableToken.allowance(address(0x1234), address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        // OK
        vm.startPrank(alice);
        assertEq(lockableToken.balanceOf(alice), 1 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), 0.5 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        assertEq(lockableToken.balanceOf(address(lockManager)), 0.5 ether);
    }

    function test_RevertWhen_CallingLockAndApprove1()
        external
        givenProposalOnLockToApprove
        givenNoLockedTokens
        givenNoTokenAllowanceNoLocked
    {
        // It Should revert

        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        vm.startPrank(randomWallet);
        assertEq(lockableToken.balanceOf(randomWallet), 0);
        assertEq(lockableToken.allowance(randomWallet, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndApprove(proposalId);

        vm.startPrank(address(0x1234));
        assertEq(lockableToken.balanceOf(address(0x1234)), 0);
        assertEq(lockableToken.allowance(address(0x1234), address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndApprove(proposalId);

        // vm.startPrank(alice);
        assertEq(lockableToken.balanceOf(alice), 1 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndApprove(proposalId);
    }

    function test_RevertWhen_CallingApprove1()
        external
        givenProposalOnLockToApprove
        givenNoLockedTokens
        givenNoTokenAllowanceNoLocked
    {
        // It Should revert

        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        vm.startPrank(randomWallet);
        assertEq(lockManager.lockedBalances(randomWallet), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.approve(proposalId);

        vm.startPrank(address(0x1234));
        assertEq(lockManager.lockedBalances(address(0x1234)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.approve(proposalId);

        // vm.startPrank(alice);
        assertEq(lockManager.lockedBalances(alice), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.approve(proposalId);
    }

    function test_RevertWhen_CallingLockAndVote1()
        external
        givenProposalOnLockToVote
        givenNoLockedTokens
        givenNoTokenAllowanceNoLocked
    {
        // It Should revert

        vm.startPrank(randomWallet);
        assertEq(lockableToken.balanceOf(randomWallet), 0);
        assertEq(lockableToken.allowance(randomWallet, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.startPrank(address(0x1234));
        assertEq(lockableToken.balanceOf(address(0x1234)), 0);
        assertEq(lockableToken.allowance(address(0x1234), address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.No);

        // vm.startPrank(alice);
        assertEq(lockableToken.balanceOf(alice), 1 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Abstain);
    }

    function test_RevertWhen_CallingVote1()
        external
        givenProposalOnLockToVote
        givenNoLockedTokens
        givenNoTokenAllowanceNoLocked
    {
        // It Should revert

        vm.startPrank(randomWallet);
        assertEq(lockManager.lockedBalances(randomWallet), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.startPrank(address(0x1234));
        assertEq(lockManager.lockedBalances(address(0x1234)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // vm.startPrank(alice);
        assertEq(lockManager.lockedBalances(alice), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenWithTokenAllowanceNoLocked() {
        lockableToken.approve(address(lockManager), 0.1 ether);
        vm.startPrank(bob);
        lockableToken.approve(address(lockManager), 0.1 ether);
        vm.startPrank(alice);

        _;
    }

    function test_WhenCallingLock2() external givenNoLockedTokens givenWithTokenAllowanceNoLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lock();
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), allowance);

        vm.startPrank(bob);
        initialBalance = lockableToken.balanceOf(bob);
        allowance = lockableToken.allowance(bob, address(lockManager));

        vm.expectEmit();
        emit BalanceLocked(bob, allowance);
        lockManager.lock();
        assertEq(lockableToken.balanceOf(bob), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(bob), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.2 ether);
    }

    function test_WhenCallingLockAndApprove2()
        external
        givenProposalOnLockToApprove
        givenNoLockedTokens
        givenWithTokenAllowanceNoLocked
    {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It The allocated token balance should have the full new balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lockAndApprove(proposalId);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), allowance);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), allowance);

        vm.startPrank(bob);
        initialBalance = lockableToken.balanceOf(bob);
        allowance = lockableToken.allowance(bob, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(bob, allowance);
        lockManager.lockAndApprove(proposalId);
        assertEq(lockableToken.balanceOf(bob), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(bob), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.2 ether);
        assertEq(ltaPlugin.usedVotingPower(proposalId, bob), allowance);
    }

    function test_RevertWhen_CallingApprove2()
        external
        givenProposalOnLockToApprove
        givenNoLockedTokens
        givenWithTokenAllowanceNoLocked
    {
        // It Should revert

        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        // vm.startPrank(alice);
        assertEq(lockManager.lockedBalances(alice), 0);
        vm.expectRevert(NoBalance.selector);
        lockManager.approve(proposalId);

        vm.startPrank(bob);
        assertEq(lockManager.lockedBalances(bob), 0);
        vm.expectRevert(NoBalance.selector);
        lockManager.approve(proposalId);
    }

    function test_WhenCallingLockAndVote2()
        external
        givenProposalOnLockToVote
        givenNoLockedTokens
        givenWithTokenAllowanceNoLocked
    {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It The allocated token balance should have the full new balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), allowance);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), allowance);

        vm.startPrank(bob);
        initialBalance = lockableToken.balanceOf(bob);
        allowance = lockableToken.allowance(bob, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(bob, allowance);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.No);
        assertEq(lockableToken.balanceOf(bob), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(bob), allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.2 ether);
        assertEq(ltvPlugin.usedVotingPower(proposalId, bob), allowance);
    }

    function test_RevertWhen_CallingVote2()
        external
        givenProposalOnLockToVote
        givenNoLockedTokens
        givenWithTokenAllowanceNoLocked
    {
        // It Should revert

        // vm.startPrank(alice);
        assertEq(lockManager.lockedBalances(alice), 0);
        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.startPrank(bob);
        assertEq(lockManager.lockedBalances(bob), 0);
        vm.expectRevert(NoBalance.selector);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);
    }

    modifier givenLockedTokens() {
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        _;
    }

    modifier givenNoTokenAllowanceSomeLocked() {
        _;
    }

    function test_RevertWhen_CallingLock3() external givenLockedTokens givenNoTokenAllowanceSomeLocked {
        // It Should revert

        // 1
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lock();

        // OK
        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), 0.4 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        assertEq(lockableToken.balanceOf(address(lockManager)), 0.6 ether);
    }

    function test_RevertWhen_CallingLockAndApprove3()
        external
        givenProposalOnLockToApprove
        givenLockedTokens
        givenNoTokenAllowanceSomeLocked
    {
        // It Should revert

        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndApprove(proposalId);

        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lockAndApprove(proposalId);

        assertEq(lockableToken.balanceOf(alice), 0.4 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        assertEq(lockableToken.balanceOf(address(lockManager)), 0.6 ether);
    }

    function test_RevertWhen_CallingApproveSameBalance3()
        external
        givenProposalOnLockToApprove
        givenLockedTokens
        givenNoTokenAllowanceSomeLocked
    {
        // Prior approval
        lockManager.approve(proposalId);

        // It Should revert

        vm.expectRevert(NoNewBalance.selector);
        lockManager.approve(proposalId);
    }

    function test_WhenCallingApproveMoreLockedBalance3()
        external
        givenProposalOnLockToApprove
        givenLockedTokens
        givenNoTokenAllowanceSomeLocked
    {
        // It Should approve with the full token balance
        // It Should emit an event

        // vm.startPrank(alice);
        lockManager.approve(proposalId);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.1 ether);

        // More
        assertEq(lockManager.lockedBalances(alice), 0.1 ether);

        lockableToken.approve(address(lockManager), 0.5 ether);

        vm.expectEmit();
        emit BalanceLocked(alice, 0.5 ether);
        lockManager.lock();

        assertEq(lockManager.lockedBalances(alice), 0.6 ether);

        lockManager.approve(proposalId);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.6 ether);
    }

    function test_RevertWhen_CallingLockAndVote3()
        external
        givenProposalOnLockToVote
        givenLockedTokens
        givenNoTokenAllowanceSomeLocked
    {
        // It Should revert

        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        lockableToken.approve(address(lockManager), 0.5 ether);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.No);

        assertEq(lockableToken.balanceOf(alice), 0.4 ether);
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);

        assertEq(lockableToken.balanceOf(address(lockManager)), 0.6 ether);
    }

    function test_RevertWhen_CallingVoteSameBalance3()
        external
        givenProposalOnLockToVote
        givenLockedTokens
        givenNoTokenAllowanceSomeLocked
    {
        // Prior vote
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It Should revert

        vm.expectRevert(NoNewBalance.selector);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);
    }

    function test_WhenCallingVoteMoreLockedBalance3()
        external
        givenProposalOnLockToVote
        givenLockedTokens
        givenNoTokenAllowanceSomeLocked
    {
        // It Should approve with the full token balance
        // It Should emit an event

        // vm.startPrank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 0.1 ether);

        // More
        assertEq(lockManager.lockedBalances(alice), 0.1 ether);

        lockableToken.approve(address(lockManager), 0.5 ether);

        vm.expectEmit();
        emit BalanceLocked(alice, 0.5 ether);
        lockManager.lock();

        assertEq(lockManager.lockedBalances(alice), 0.6 ether);

        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 0.6 ether);
    }

    modifier givenWithTokenAllowanceSomeLocked() {
        lockableToken.approve(address(lockManager), 0.5 ether);

        _;
    }

    function test_WhenCallingLock4() external givenLockedTokens givenWithTokenAllowanceSomeLocked {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
    }

    function test_WhenCallingLockAndApproveNoPriorPower4()
        external
        givenProposalOnLockToApprove
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lockAndApprove(proposalId);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.1 ether + allowance);
    }

    function test_WhenCallingLockAndApproveWithPriorPower4()
        external
        givenProposalOnLockToApprove
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        lockManager.approve(proposalId);

        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lockAndApprove(proposalId);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.1 ether + allowance);
    }

    function test_RevertWhen_CallingApproveSameBalance4()
        external
        givenProposalOnLockToApprove
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        // It Should revert

        // vm.startPrank(alice);
        lockManager.approve(proposalId);

        vm.expectRevert();
        lockManager.approve(proposalId);
    }

    function test_WhenCallingApproveMoreLockedBalance4()
        external
        givenProposalOnLockToApprove
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        lockManager.approve(proposalId);

        // It Should approve with the full token balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceLocked(alice, 0.5 ether);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), initialBalance - 0.5 ether);
        assertEq(lockManager.lockedBalances(alice), 0.6 ether);
        lockManager.approve(proposalId);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.6 ether);
    }

    function test_WhenCallingLockAndVoteNoPriorPower4()
        external
        givenProposalOnLockToVote
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.1 ether + allowance);
    }

    function test_WhenCallingLockAndVoteWithPriorPower4()
        external
        givenProposalOnLockToVote
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It Should allow any token holder to lock
        // It Should approve with the full token balance
        // It Should increase the locked amount
        // It The allocated token balance should have the full new balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        vm.expectEmit();
        emit BalanceLocked(alice, allowance);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance);
        assertEq(lockManager.lockedBalances(alice), 0.1 ether + allowance);
        assertEq(lockableToken.balanceOf(address(lockManager)), 0.1 ether + allowance);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.1 ether + allowance);
    }

    function test_RevertWhen_CallingVoteSameBalance4()
        external
        givenProposalOnLockToVote
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        // It Should revert

        // vm.startPrank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.expectRevert();
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    function test_WhenCallingVoteMoreLockedBalance4()
        external
        givenProposalOnLockToVote
        givenLockedTokens
        givenWithTokenAllowanceSomeLocked
    {
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);

        // It Should approve with the full token balance
        // It Should emit an event

        // vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceLocked(alice, 0.5 ether);
        lockManager.lock();

        assertEq(lockableToken.balanceOf(alice), initialBalance - 0.5 ether);
        assertEq(lockManager.lockedBalances(alice), 0.6 ether);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.6 ether);
    }

    modifier givenCallingLockLockAndApproveOrLockAndVote() {
        _;
    }

    function test_GivenEmptyPlugin() external givenCallingLockLockAndApproveOrLockAndVote {
        // It Locking and voting should revert

        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            lockableToken,
            underlyingToken
        );

        vm.expectRevert();
        lockManager.lockAndApprove(proposalId);

        vm.expectRevert();
        lockManager.approve(proposalId);

        // voting
        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Voting),
            lockableToken,
            underlyingToken
        );

        vm.expectRevert();
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.expectRevert();
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    function test_GivenInvalidToken() external givenCallingLockLockAndApproveOrLockAndVote {
        // It Locking should revert
        // It Locking and voting should revert
        // It Voting should revert

        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            IERC20(address(0x1234)),
            underlyingToken
        );
        lockableToken.approve(address(lockManager), 0.1 ether);
        vm.expectRevert();
        lockManager.lock();

        vm.expectRevert();
        lockManager.lockAndApprove(proposalId);

        vm.expectRevert();
        lockManager.approve(proposalId);

        // Voting
        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Voting),
            IERC20(address(0x1234)),
            underlyingToken
        );
        lockableToken.approve(address(lockManager), 0.1 ether);
        vm.expectRevert();
        lockManager.lock();

        vm.expectRevert();
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.expectRevert();
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenProposalCreatedIsCalled() {
        _;
    }

    function test_RevertWhen_TheCallerIsNotThePluginProposalCreated() external givenProposalCreatedIsCalled {
        // It Should revert

        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPluginAddress.selector));
        lockManager.proposalCreated(1234);

        vm.startPrank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPluginAddress.selector));
        lockManager.proposalCreated(1234);
    }

    function test_WhenTheCallerIsThePluginProposalCreated() external givenProposalCreatedIsCalled {
        // It Adds the proposal ID to the list of known proposals

        vm.startPrank(address(ltaPlugin));

        vm.expectRevert();
        assertEq(lockManager.knownProposalIds(0), 0);

        lockManager.proposalCreated(1234);
        assertEq(lockManager.knownProposalIds(0), 1234);

        // 2
        vm.expectRevert();
        assertEq(lockManager.knownProposalIds(1), 0);

        lockManager.proposalCreated(2345);
        assertEq(lockManager.knownProposalIds(1), 2345);
    }

    modifier givenProposalEndedIsCalled() {
        _;
    }

    function test_RevertWhen_TheCallerIsNotThePluginProposalEnded() external givenProposalEndedIsCalled {
        // It Should revert

        vm.startPrank(address(ltaPlugin));
        lockManager.proposalCreated(1234);
        assertEq(lockManager.knownProposalIds(0), 1234);

        vm.startPrank(address(bob));
        vm.expectRevert(abi.encodeWithSelector(LockManager.InvalidPluginAddress.selector));
        lockManager.proposalEnded(1234);

        assertEq(lockManager.knownProposalIds(0), 1234);
    }

    function test_WhenTheCallerIsThePluginProposalEnded() external givenProposalEndedIsCalled {
        // It Removes the proposal ID from the list of known proposals

        vm.startPrank(address(ltaPlugin));
        lockManager.proposalCreated(1234);
        lockManager.proposalCreated(2345);
        lockManager.proposalCreated(3456);
        assertEq(lockManager.knownProposalIds(0), 1234);
        assertEq(lockManager.knownProposalIds(1), 2345);
        assertEq(lockManager.knownProposalIds(2), 3456);

        lockManager.proposalEnded(3456);
        vm.expectRevert();
        lockManager.knownProposalIds(2);

        lockManager.proposalEnded(2345);
        vm.expectRevert();
        lockManager.knownProposalIds(1);

        lockManager.proposalEnded(1234);
        vm.expectRevert();
        lockManager.knownProposalIds(0);
    }

    modifier givenStrictModeIsSet() {
        _;
    }

    modifier givenDidntLockAnythingStrict() {
        _;
    }

    function test_RevertWhen_TryingToUnlock1Strict() external givenStrictModeIsSet givenDidntLockAnythingStrict {
        // It Should revert

        (UnlockMode mode, ) = lockManager.settings();
        assertEq(uint8(mode), uint8(UnlockMode.Strict));

        // vm.startPrank(alice);
        vm.expectRevert(NoBalance.selector);
        lockManager.unlock();
    }

    modifier givenLockedButDidntApproveAnywhereStrict() {
        _;
    }

    function test_WhenTryingToUnlock2ApprovalStrict() external givenProposalOnLockToApprove givenStrictModeIsSet givenLockedButDidntApproveAnywhereStrict {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.1 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.1 ether);
    }

    modifier givenLockedButDidntVoteAnywhereStrict() {
        _;
    }

    function test_WhenTryingToUnlock2VotingStrict() external givenProposalOnLockToVote givenStrictModeIsSet givenLockedButDidntVoteAnywhereStrict {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lock();

        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.1 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.1 ether);
    }

    modifier givenLockedButApprovedEndedOrExecutedProposalsStrict() {
        _;
    }

    function test_WhenTryingToUnlock3ApprovedStrict()
        external
        givenProposalOnLockToApprove
        givenStrictModeIsSet
        givenLockedButApprovedEndedOrExecutedProposalsStrict
    {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndApprove(proposalId);

        vm.expectRevert(LockManager.LocksStillActive.selector);
        lockManager.unlock();

        vm.startPrank(address(ltaPlugin));
        lockManager.proposalEnded(proposalId);

        vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.1 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.1 ether);
    }

    modifier givenLockedButVotedOnEndedOrExecutedProposalsStrict() {
        _;
    }

    function test_WhenTryingToUnlock3VotedStrict()
        external
        givenProposalOnLockToVote
        givenStrictModeIsSet
        givenLockedButVotedOnEndedOrExecutedProposalsStrict
    {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.expectRevert(LockManager.LocksStillActive.selector);
        lockManager.unlock();

        vm.startPrank(address(ltaPlugin));
        lockManager.proposalEnded(proposalId);

        vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.1 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.1 ether);
    }

    modifier givenLockedAndApprovedCurrentlyActiveProposalsStrict() {
        _;
    }

    function test_RevertWhen_TryingToUnlock4ApprovedStrict()
        external
        givenProposalOnLockToApprove
        givenStrictModeIsSet
        givenLockedAndApprovedCurrentlyActiveProposalsStrict
    {
        // It Should revert

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndApprove(proposalId);

        vm.expectRevert(LockManager.LocksStillActive.selector);
        lockManager.unlock();
    }

    modifier givenLockedAndVotedOnCurrentlyActiveProposalsStrict() {
        _;
    }

    function test_RevertWhen_TryingToUnlock4VotedStrict()
        external
        givenProposalOnLockToVote
        givenStrictModeIsSet
        givenLockedAndVotedOnCurrentlyActiveProposalsStrict
    {
        // It Should revert

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.expectRevert(LockManager.LocksStillActive.selector);
        lockManager.unlock();
    }

    modifier givenFlexibleModeIsSet() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) = builder
            .withTokenHolder(alice, 1 ether)
            .withTokenHolder(bob, 10 ether)
            .withTokenHolder(carol, 10 ether)
            .withTokenHolder(david, 15 ether)
            .withEarlyUnlock()
            .build();

        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        _;
    }

    modifier givenDidntLockAnythingFlexible() {
        _;
    }

    function test_RevertWhen_TryingToUnlock1Flexible() external givenFlexibleModeIsSet givenDidntLockAnythingFlexible {
        // It Should revert

        (UnlockMode mode,) = lockManager.settings();
        assertEq(uint8(mode), uint8(UnlockMode.Early));

        // vm.startPrank(alice);
        vm.expectRevert(NoBalance.selector);
        lockManager.unlock();
    }

    modifier givenLockedButDidntApproveAnywhereFlexible() {
        _;
    }

    function test_WhenTryingToUnlock2ApprovalFlexible()
        external
        givenProposalOnLockToApprove
        givenFlexibleModeIsSet
        givenLockedButDidntApproveAnywhereFlexible
    {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.2 ether);
        lockManager.lock();

        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.2 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.2 ether);
    }

    modifier givenLockedButDidntVoteAnywhereFlexible() {
        _;
    }

    function test_WhenTryingToUnlock2VotingFlexible()
        external
        givenProposalOnLockToVote
        givenFlexibleModeIsSet
        givenLockedButDidntVoteAnywhereFlexible
    {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.2 ether);
        lockManager.lock();

        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.2 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.2 ether);
    }

    modifier givenLockedButApprovedOnEndedOrExecutedProposalsFlexible() {
        _;
    }

    function test_WhenTryingToUnlock3ApprovedFlexible()
        external
        givenProposalOnLockToApprove
        givenFlexibleModeIsSet
        givenLockedButApprovedOnEndedOrExecutedProposalsFlexible
    {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        lockableToken.approve(address(lockManager), 0.3 ether);
        lockManager.lockAndApprove(proposalId);

        vm.startPrank(address(ltaPlugin));
        lockManager.proposalEnded(proposalId);

        vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.3 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.3 ether);
    }

    modifier givenLockedButVotedOnEndedOrExecutedProposalsFlexible() {
        _;
    }

    function test_WhenTryingToUnlock3VotedFlexible()
        external
        givenProposalOnLockToVote
        givenFlexibleModeIsSet
        givenLockedButVotedOnEndedOrExecutedProposalsFlexible
    {
        // It Should unlock and refund the full amount right away
        // It Should emit an event

        lockableToken.approve(address(lockManager), 0.3 ether);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.startPrank(address(ltaPlugin));
        lockManager.proposalEnded(proposalId);

        vm.startPrank(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.3 ether);
        lockManager.unlock();
        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.3 ether);
    }

    modifier givenLockedAndApprovedOnCurrentlyActiveProposalsFlexible() {
        _;
    }

    function test_WhenTryingToUnlock4ApprovalFlexible()
        external
        givenProposalOnLockToApprove
        givenFlexibleModeIsSet
        givenLockedAndApprovedOnCurrentlyActiveProposalsFlexible
    {
        // It Should deallocate the existing voting power from active proposals
        // It Should unlock and refund the full amount
        // It Should emit an event

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndApprove(proposalId);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.1 ether);

        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.1 ether);
        lockManager.unlock();

        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.1 ether);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0);
    }

    modifier givenLockedAndVotedOnCurrentlyActiveProposalsFlexible() {
        _;
    }

    function test_WhenTryingToUnlock4VotingFlexible()
        external
        givenProposalOnLockToVote
        givenFlexibleModeIsSet
        givenLockedAndVotedOnCurrentlyActiveProposalsFlexible
    {
        // It Should deallocate the existing voting power from active proposals
        // It Should unlock and refund the full amount
        // It Should emit an event

        // vm.startPrank(alice);
        lockableToken.approve(address(lockManager), 0.1 ether);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0.1 ether);

        uint256 initialBalance = lockableToken.balanceOf(alice);
        vm.expectEmit();
        emit BalanceUnlocked(alice, 0.1 ether);
        lockManager.unlock();

        assertEq(lockableToken.balanceOf(alice), initialBalance + 0.1 ether);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 0);
    }

    function test_WhenCallingPlugin() external view {
        // It Should return the right address

        assertEq(address(lockManager.plugin()), address(ltaPlugin));
    }

    function test_WhenCallingToken() external view {
        // It Should return the right address

        assertEq(address(lockManager.token()), address(lockableToken));
    }

    modifier givenNoUnderlyingToken() {
        _;
    }

    function test_WhenCallingUnderlyingTokenEmpty() external givenNoUnderlyingToken {
        // It Should return the token address

        lockManager = new LockManager(
            dao,
            LockManagerSettings(UnlockMode.Strict, PluginMode.Approval),
            lockableToken,
            IERC20(address(0)) // underlying
        );

        assertEq(address(lockManager.underlyingToken()), address(lockableToken));
    }

    modifier givenUnderlyingTokenDefined() {
        _;
    }

    function test_WhenCallingUnderlyingTokenSet() external view givenUnderlyingTokenDefined {
        // It Should return the right address
        assertEq(address(lockManager.underlyingToken()), address(underlyingToken));
    }
}
