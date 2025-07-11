// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AragonTest} from "./lib/TestBase.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
import {DAO, IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {LockToApprovePlugin} from "../src/LockToApprovePlugin.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {LockManagerSettings, UnlockMode, PluginMode} from "../src/interfaces/ILockManager.sol";
import {IMajorityVoting} from "../src/interfaces/IMajorityVoting.sol";
import {LockManager} from "../src/LockManager.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {ILockToVoteBase} from "../src/interfaces/ILockToVoteBase.sol";

contract LockManagerTest is AragonTest {
    DaoBuilder builder;
    DAO dao;
    LockToApprovePlugin ltaPlugin;
    LockToVotePlugin ltvPlugin;
    LockManager lockManager;
    IERC20 lockableToken;
    IERC20 underlyingToken;
    uint256 proposalId;

    event BalanceLocked(address voter, uint256 amount);
    event BalanceUnlocked(address voter, uint256 amount);
    event ProposalEnded(uint256 proposalId);

    error NoBalance();
    error ApprovalForbidden(uint256 proposalId, address voter);
    error VoteCastForbidden(uint256 proposalId, address account);
    error SetPluginAddressForbidden();
    error InvalidPluginMode();
    error InvalidPluginAddress();

    function setUp() public {
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) = builder.withTokenHolder(
            alice, 1 ether
        ).withTokenHolder(bob, 10 ether).withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether)
            .withStrictUnlock().withApprovalPlugin().build();
    }

    modifier givenTheContractIsBeingDeployed() {
        _;
    }

    function test_WhenDeployingWithValidParametersAndANonzeroUnderlyingToken()
        external
        givenTheContractIsBeingDeployed
    {
        // It Should set the DAO address correctly
        // It Should set the unlockMode correctly
        // It Should set the pluginMode correctly
        // It Should set the token address correctly
        // It Should set the underlying token address correctly
        // It Should initialize the plugin address to address(0)
        IDAO testDao = IDAO(address(dao));
        IERC20 testToken = IERC20(address(new TestToken()));
        IERC20 testUnderlying = IERC20(address(new TestToken()));
        LockManagerSettings memory settings =
            LockManagerSettings({unlockMode: UnlockMode.Strict, pluginMode: PluginMode.Approval});

        LockManager newLockManager = new LockManager(testDao, settings, testToken, testUnderlying);

        assertEq(address(newLockManager.dao()), address(testDao), "DAO address mismatch");
        (UnlockMode um, PluginMode pm) = newLockManager.settings();
        assertEq(uint8(um), uint8(UnlockMode.Strict), "Unlock mode mismatch");
        assertEq(uint8(pm), uint8(PluginMode.Approval), "Plugin mode mismatch");
        assertEq(address(newLockManager.token()), address(testToken), "Token address mismatch");
        assertEq(address(newLockManager.underlyingToken()), address(testUnderlying), "Underlying token mismatch");
        assertEq(address(newLockManager.plugin()), address(0), "Plugin should be zero");
    }

    function test_WhenDeployingWithAZeroaddressForTheUnderlyingToken() external givenTheContractIsBeingDeployed {
        // It Should set the underlying token address to address(0)
        LockManager newLockManager = new LockManager(
            dao, LockManagerSettings(UnlockMode.Strict, PluginMode.Approval), lockableToken, IERC20(address(0))
        );

        assertEq(address(newLockManager.underlyingToken()), address(lockableToken));
    }

    modifier givenThePluginAddressHasNotBeenSetYet() {
        lockManager = new LockManager(
            dao, LockManagerSettings(UnlockMode.Strict, PluginMode.Approval), lockableToken, underlyingToken
        );
        _;
    }

    function test_WhenCallingSetPluginAddressWithAnAddressThatDoesNotSupportILockToVoteBase()
        external
        givenThePluginAddressHasNotBeenSetYet
    {
        // It Should revert with InvalidPlugin
        vm.expectRevert(LockManager.InvalidPlugin.selector);
        lockManager.setPluginAddress(ILockToVoteBase(address(dao)));
    }

    modifier givenThePluginModeIsApproval() {
        // The default setup is Approval mode, so no changes needed
        _;
    }

    function test_WhenCallingSetPluginAddressWithAPluginThatSupportsILockToVoteBaseButNotILockToApprove()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsApproval
    {
        // It Should revert with InvalidPlugin
        (,, LockToVotePlugin votingPlugin,,,) = builder.withVotingPlugin().build();

        vm.expectRevert(LockManager.InvalidPlugin.selector);
        lockManager.setPluginAddress(votingPlugin);
    }

    function test_WhenCallingSetPluginAddressWithAValidApprovalPlugin()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsApproval
    {
        // It Should set the plugin address
        assertEq(address(lockManager.plugin()), address(0));
        lockManager.setPluginAddress(ltaPlugin);
        assertEq(address(lockManager.plugin()), address(ltaPlugin));
    }

    modifier givenThePluginModeIsVoting() {
        lockManager = new LockManager(
            dao, LockManagerSettings(UnlockMode.Strict, PluginMode.Voting), lockableToken, underlyingToken
        );
        _;
    }

    function test_WhenCallingSetPluginAddressWithAPluginThatSupportsILockToVoteBaseButNotILockToVote()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsVoting
    {
        // It Should revert with InvalidPlugin
        vm.expectRevert(LockManager.InvalidPlugin.selector);
        lockManager.setPluginAddress(ltaPlugin);
    }

    function test_WhenCallingSetPluginAddressWithAValidVotingPlugin()
        external
        givenThePluginAddressHasNotBeenSetYet
        givenThePluginModeIsVoting
    {
        // It Should set the plugin address
        (,, LockToVotePlugin votingPlugin,,,) = builder.withVotingPlugin().build();

        assertEq(address(lockManager.plugin()), address(0));
        lockManager.setPluginAddress(votingPlugin);
        assertEq(address(lockManager.plugin()), address(votingPlugin));
    }

    modifier givenThePluginAddressHasAlreadyBeenSet() {
        // The default setup already sets a plugin
        _;
    }

    function test_WhenCallingSetPluginAddressAgain() external givenThePluginAddressHasAlreadyBeenSet {
        // It Should revert with SetPluginAddressForbidden
        vm.expectRevert(SetPluginAddressForbidden.selector);
        lockManager.setPluginAddress(ltaPlugin);
    }

    modifier givenAUserWantsToLockTokens() {
        _;
    }

    modifier whenTheUserHasNotApprovedTheLockManagerToSpendAnyTokens() {
        TestToken(address(lockableToken)).mint(bob, 1 ether);

        vm.prank(bob);
        assertEq(lockableToken.allowance(bob, address(lockManager)), 0);
        _;
    }

    function test_WhenCallingLock()
        external
        givenAUserWantsToLockTokens
        whenTheUserHasNotApprovedTheLockManagerToSpendAnyTokens
    {
        // It Should revert with NoBalance
        vm.prank(bob);
        vm.expectRevert(NoBalance.selector);
        lockManager.lock();
    }

    modifier whenTheUserHasApprovedTheLockManagerToSpendTokens() {
        TestToken(address(lockableToken)).mint(bob, 1 ether);

        vm.prank(bob);
        lockableToken.approve(address(lockManager), 1 ether);
        _;
    }

    function test_WhenCallingLock2()
        external
        givenAUserWantsToLockTokens
        whenTheUserHasApprovedTheLockManagerToSpendTokens
    {
        // It Should transfer the full allowance amount from the user
        // It Should increase the user's lockedBalances by the allowance amount
        // It Should emit a BalanceLocked event with the correct user and amount
        uint256 allowance = lockableToken.allowance(bob, address(lockManager));
        uint256 initialBobBalance = lockableToken.balanceOf(bob);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit BalanceLocked(bob, allowance);
        lockManager.lock();

        assertEq(lockManager.lockedBalances(bob), allowance, "Locked balance incorrect");
        assertEq(lockableToken.balanceOf(bob), initialBobBalance - allowance, "User balance incorrect");
    }

    modifier givenVotingPluginIsActive() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withVotingPlugin().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);
        _;
    }

    function test_WhenCallingApprove() external givenVotingPluginIsActive {
        // It Should revert with InvalidPluginMode
        vm.expectRevert(InvalidPluginMode.selector);
        vm.prank(alice);
        lockManager.approve(proposalId);
    }

    function test_WhenCallingLockAndApprove() external givenVotingPluginIsActive {
        // It Should revert with InvalidPluginMode
        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.expectRevert(InvalidPluginMode.selector);
        lockManager.lockAndApprove(proposalId);
    }

    modifier givenTheUserHasNoLockedBalance() {
        vm.prank(alice);
        assertEq(lockManager.lockedBalances(alice), 0);
        _;
    }

    function test_WhenCallingVote() external givenVotingPluginIsActive givenTheUserHasNoLockedBalance {
        // It Should revert with NoBalance
        vm.prank(david);
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, david));
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserHasNoTokenAllowanceForTheLockManager() {
        assertEq(lockableToken.allowance(alice, address(lockManager)), 0);
        _;
    }

    function test_WhenCallingLockAndVote()
        external
        givenVotingPluginIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasNoTokenAllowanceForTheLockManager
    {
        // It Should revert with NoBalance
        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserHasATokenAllowanceForTheLockManager() {
        TestToken(address(lockableToken)).mint(alice, 1 ether);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        _;
    }

    function test_WhenCallingLockAndVote2()
        external
        givenVotingPluginIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasATokenAllowanceForTheLockManager
    {
        // It Should first lock the tokens by transferring the full allowance
        // It Should then call vote() on the plugin with the new balance
        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(
                ltvPlugin.vote.selector, proposalId, alice, IMajorityVoting.VoteOption.Yes, allowance
            )
        );
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        assertEq(lockManager.lockedBalances(alice), allowance, "Locked balance incorrect");
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance, "User balance not transferred");
    }

    modifier givenTheUserHasALockedBalance() {
        TestToken(address(lockableToken)).mint(alice, 0.5 ether);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lock();
        assertEq(lockManager.lockedBalances(alice), 0.5 ether);
        _;
    }

    function test_WhenCallingVoteForTheFirstTimeOnAProposal()
        external
        givenVotingPluginIsActive
        givenTheUserHasALockedBalance
    {
        // It Should call vote() on the plugin with the user's full locked balance
        uint256 lockedBalance = lockManager.lockedBalances(alice);

        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(
                ltvPlugin.vote.selector, proposalId, alice, IMajorityVoting.VoteOption.Yes, lockedBalance
            )
        );
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance() {
        uint256 lockedBalance = lockManager.lockedBalances(alice);
        vm.prank(alice);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), lockedBalance);
        _;
    }

    function test_WhenCallingVoteAgainWithTheSameParameters()
        external
        givenVotingPluginIsActive
        givenTheUserHasALockedBalance
        givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance
    {
        // It Should revert with VoteCastForbidden

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VoteCastForbidden.selector, proposalId, alice));
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheUserLocksMoreTokens() {
        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lock();
        _;
    }

    function test_WhenCallingVoteAgain()
        external
        givenVotingPluginIsActive
        givenTheUserHasALockedBalance
        givenTheUserHasAlreadyVotedOnTheProposalWithTheirCurrentBalance
        givenTheUserLocksMoreTokens
    {
        // It Should call vote() on the plugin with the new, larger balance
        // Note: For this to work, votingMode must be VoteReplacement
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withVotingPlugin().withVoteReplacement().withTokenHolder(alice, 2 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));

        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 0.5 ether);
        vm.prank(alice);
        lockManager.lock();

        uint256 newLockedBalance = lockManager.lockedBalances(alice);
        assertGt(newLockedBalance, 0.5 ether);

        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(
                ltvPlugin.vote.selector, proposalId, alice, IMajorityVoting.VoteOption.No, newLockedBalance
            )
        );
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.No);
    }

    modifier givenApprovalPluginIsActive() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withApprovalPlugin().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltaPlugin));
        lockManager.proposalCreated(proposalId);
        _;
    }

    function test_WhenCallingVote2() external givenApprovalPluginIsActive {
        // It Should revert with InvalidPluginMode
        vm.prank(alice);
        vm.expectRevert(InvalidPluginMode.selector);
        lockManager.vote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    function test_WhenCallingLockAndVote3() external givenApprovalPluginIsActive {
        // It Should revert with InvalidPluginMode
        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);

        vm.prank(alice);
        vm.expectRevert(InvalidPluginMode.selector);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
    }

    function test_WhenCallingApprove2() external givenApprovalPluginIsActive givenTheUserHasNoLockedBalance {
        // It Should revert with NoBalance
        vm.prank(david);
        vm.expectRevert(abi.encodeWithSelector(ApprovalForbidden.selector, proposalId, david));
        lockManager.approve(proposalId);
    }

    function test_WhenCallingLockAndApprove2()
        external
        givenApprovalPluginIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasNoTokenAllowanceForTheLockManager
    {
        // It Should revert with NoBalance
        vm.prank(david);
        vm.expectRevert(NoBalance.selector);
        lockManager.lockAndApprove(proposalId);
    }

    function test_WhenCallingLockAndApprove3()
        external
        givenApprovalPluginIsActive
        givenTheUserHasNoLockedBalance
        givenTheUserHasATokenAllowanceForTheLockManager
    {
        // It Should first lock the tokens by transferring the full allowance
        // It Should then call approve() on the plugin with the new balance

        uint256 allowance = lockableToken.allowance(alice, address(lockManager));
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectCall(
            address(ltaPlugin), abi.encodeWithSelector(ltaPlugin.approve.selector, proposalId, alice, allowance)
        );
        lockManager.lockAndApprove(proposalId);

        assertEq(lockManager.lockedBalances(alice), allowance, "Locked balance incorrect");
        assertEq(lockableToken.balanceOf(alice), initialBalance - allowance, "User balance not transferred");
    }

    function test_WhenCallingApproveForTheFirstTimeOnAProposal()
        external
        givenApprovalPluginIsActive
        givenTheUserHasALockedBalance
    {
        // It Should call approve() on the plugin with the user's full locked balance
        uint256 lockedBalance = lockManager.lockedBalances(alice);
        vm.expectCall(
            address(ltaPlugin), abi.encodeWithSelector(ltaPlugin.approve.selector, proposalId, alice, lockedBalance)
        );
        vm.prank(alice);
        lockManager.approve(proposalId);
    }

    modifier givenTheUserHasAlreadyApprovedTheProposalWithTheirCurrentBalance() {
        uint256 lockedBalance = lockManager.lockedBalances(alice);
        vm.prank(alice);
        lockManager.approve(proposalId);
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), lockedBalance);
        _;
    }

    function test_WhenCallingApproveAgain()
        external
        givenApprovalPluginIsActive
        givenTheUserHasALockedBalance
        givenTheUserHasAlreadyApprovedTheProposalWithTheirCurrentBalance
    {
        // It Should revert with ApprovalForbidden
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ApprovalForbidden.selector, proposalId, alice));
        lockManager.approve(proposalId);
    }

    function test_WhenCallingApproveAgain2()
        external
        givenApprovalPluginIsActive
        givenTheUserHasALockedBalance
        givenTheUserHasAlreadyApprovedTheProposalWithTheirCurrentBalance
        givenTheUserLocksMoreTokens
    {
        // It Should call approve() on the plugin with the new, larger balance
        uint256 newLockedBalance = lockManager.lockedBalances(alice);
        vm.expectCall(
            address(ltaPlugin), abi.encodeWithSelector(ltaPlugin.approve.selector, proposalId, alice, newLockedBalance)
        );
        vm.prank(alice);
        lockManager.approve(proposalId);
    }

    modifier givenAUserWantsToUnlockTokens() {
        _;
    }

    modifier givenTheUserHasNoLockedBalance3() {
        assertEq(lockManager.lockedBalances(alice), 0);
        _;
    }

    function test_WhenCallingUnlock() external givenAUserWantsToUnlockTokens givenTheUserHasNoLockedBalance3 {
        // It Should revert with NoBalance
        vm.prank(alice);
        vm.expectRevert(NoBalance.selector);
        lockManager.unlock();
    }

    modifier givenTheUserHasALockedBalance3() {
        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lock();
        _;
    }

    modifier givenUnlockModeIsStrict() {
        // Default setup is strict
        _;
    }

    modifier givenTheUserHasNoActiveVotesOnAnyOpenProposals() {
        // User has locked tokens but not voted/approved
        _;
    }

    function test_WhenCallingUnlock2()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserHasALockedBalance3
        givenUnlockModeIsStrict
        givenTheUserHasNoActiveVotesOnAnyOpenProposals
    {
        // It Should transfer the locked balance back to the user
        // It Should set the user's lockedBalances to 0
        // It Should emit a BalanceUnlocked event
        uint256 lockedAmount = lockManager.lockedBalances(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit BalanceUnlocked(alice, lockedAmount);
        lockManager.unlock();

        assertEq(lockManager.lockedBalances(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
    }

    modifier givenTheUserHasAnActiveVoteOnAtLeastOneOpenProposal() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withApprovalPlugin().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltaPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndApprove(proposalId);
        _;
    }

    function test_WhenCallingUnlock3()
        external
        givenAUserWantsToUnlockTokens
        givenUnlockModeIsStrict
        givenTheUserHasAnActiveVoteOnAtLeastOneOpenProposal
    {
        // It Should revert with LocksStillActive
        vm.prank(alice);
        vm.expectRevert(LockManager.LocksStillActive.selector);
        lockManager.unlock();
    }

    modifier givenTheUserOnlyHasVotesOnProposalsThatAreNowClosed() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withApprovalPlugin().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltaPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndApprove(proposalId);

        vm.warp(block.timestamp + ltaPlugin.proposalDuration() + 1 days);
        assertFalse(ltaPlugin.isProposalOpen(proposalId));
        _;
    }

    function test_WhenCallingUnlock4()
        external
        givenAUserWantsToUnlockTokens
        givenUnlockModeIsStrict
        givenTheUserOnlyHasVotesOnProposalsThatAreNowClosed
    {
        // It Should succeed and transfer the locked balance back to the user
        // It Should remove the closed proposal from knownProposalIds
        uint256 lockedAmount = lockManager.lockedBalances(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        lockManager.unlock();

        assertEq(lockManager.lockedBalances(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
        vm.expectRevert();
        lockManager.knownProposalIdAt(0);
    }

    modifier givenUnlockModeIsDefault() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withEarlyUnlock().withApprovalPlugin().withTokenHolder(alice, 1 ether).build();
        _;
    }

    modifier givenTheUserHasNoActiveVotesOnAnyOpenProposals2() {
        // User has locked tokens but not voted/approved
        _;
    }

    function test_WhenCallingUnlock5()
        external
        givenAUserWantsToUnlockTokens
        givenUnlockModeIsDefault
        givenTheUserHasALockedBalance3
        givenTheUserHasNoActiveVotesOnAnyOpenProposals2
    {
        // It Should succeed and transfer the locked balance back to the user
        uint256 lockedAmount = lockManager.lockedBalances(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        lockManager.unlock();

        assertEq(lockManager.lockedBalances(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
    }

    modifier givenTheUserHasVotesOnOpenProposals() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withEarlyUnlock().withVotingPlugin().withVoteReplacement().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);
        _;
    }

    function test_WhenCallingUnlock6()
        external
        givenAUserWantsToUnlockTokens
        givenUnlockModeIsDefault
        givenTheUserHasVotesOnOpenProposals
    {
        // It Should call clearVote() on the plugin for each active proposal
        // It Should transfer the locked balance back to the user
        // It Should set the user's lockedBalances to 0
        // It Should emit a BalanceUnlocked event
        uint256 lockedAmount = lockManager.lockedBalances(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.expectCall(address(ltvPlugin), abi.encodeWithSelector(ltvPlugin.clearVote.selector, proposalId, alice));
        vm.expectEmit(true, true, true, true);
        emit BalanceUnlocked(alice, lockedAmount);

        vm.prank(alice);
        lockManager.unlock();

        assertEq(lockManager.lockedBalances(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
    }

    modifier givenTheUserHasApprovalsOnOpenProposals() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withEarlyUnlock().withApprovalPlugin().withTokenHolder(alice, 1 ether).build();

        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltaPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndApprove(proposalId);
        _;
    }

    function test_WhenCallingUnlock7() external givenAUserWantsToUnlockTokens givenTheUserHasApprovalsOnOpenProposals {
        // It Should call clearApproval() on the plugin for each active proposal
        // It Should transfer the locked balance back to the user
        // It Should set the user's lockedBalances to 0
        // It Should emit a BalanceUnlocked event
        uint256 lockedAmount = lockManager.lockedBalances(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        vm.prank(alice);
        vm.expectCall(address(ltaPlugin), abi.encodeWithSelector(ltaPlugin.clearApproval.selector, proposalId, alice));
        vm.expectEmit(true, true, true, true);
        emit BalanceUnlocked(alice, lockedAmount);
        lockManager.unlock();

        assertEq(lockManager.lockedBalances(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
    }

    modifier givenTheUserOnlyHasVotesOnProposalsThatAreNowClosedOrEnded() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withEarlyUnlock().withVotingPlugin().withVoteReplacement().withTokenHolder(alice, 1 ether).build();
        Action[] memory _actions = new Action[](0);
        proposalId = ltvPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltvPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.warp(block.timestamp + ltvPlugin.proposalDuration() + 1 days);
        assertFalse(ltvPlugin.isProposalOpen(proposalId));
        _;
    }

    function test_WhenCallingUnlock8()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserOnlyHasVotesOnProposalsThatAreNowClosedOrEnded
    {
        // It Should not attempt to clear votes for the closed proposal
        // It Should remove the closed proposal from knownProposalIds
        // It Should succeed and transfer the locked balance back to the user
        uint256 lockedAmount = lockManager.lockedBalances(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);
        vm.prank(alice);
        lockManager.unlock();
        assertEq(ltvPlugin.usedVotingPower(proposalId, alice), 1 ether);

        assertEq(lockManager.lockedBalances(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
        vm.expectRevert();
        lockManager.knownProposalIdAt(0);
    }

    modifier givenTheUserOnlyHasApprovalsOnProposalsThatAreNowClosedOrEnded() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withEarlyUnlock().withApprovalPlugin().withTokenHolder(alice, 1 ether).build();

        Action[] memory _actions = new Action[](0);
        proposalId = ltaPlugin.createProposal(bytes(""), _actions, 0, 0, bytes(""));
        vm.prank(address(ltaPlugin));
        lockManager.proposalCreated(proposalId);

        vm.prank(alice);
        lockableToken.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndApprove(proposalId);

        vm.warp(block.timestamp + ltaPlugin.proposalDuration() + 1 days);
        assertFalse(ltaPlugin.isProposalOpen(proposalId));
        _;
    }

    function test_WhenCallingUnlock9()
        external
        givenAUserWantsToUnlockTokens
        givenTheUserOnlyHasApprovalsOnProposalsThatAreNowClosedOrEnded
    {
        // It Should not attempt to clear votes for the closed proposal
        // It Should remove the closed proposal from knownProposalIds
        // It Should succeed and transfer the locked balance back to the user
        uint256 lockedAmount = lockManager.lockedBalances(alice);
        uint256 initialBalance = lockableToken.balanceOf(alice);

        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 1 ether);
        vm.prank(alice);
        lockManager.unlock();
        assertEq(ltaPlugin.usedVotingPower(proposalId, alice), 1 ether);

        assertEq(lockManager.lockedBalances(alice), 0);
        assertEq(lockableToken.balanceOf(alice), initialBalance + lockedAmount);
        vm.expectRevert();
        lockManager.knownProposalIdAt(0);
    }

    modifier givenThePluginHasBeenSet() {
        // Default setup has a plugin set
        _;
    }

    modifier givenTheCallerIsNotTheRegisteredPlugin() {
        _;
    }

    function test_WhenCallingProposalCreated()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsNotTheRegisteredPlugin
    {
        // It Should revert with InvalidPluginAddress
        vm.prank(bob);
        vm.expectRevert(InvalidPluginAddress.selector);
        lockManager.proposalCreated(1);
    }

    function test_WhenCallingProposalEnded() external givenThePluginHasBeenSet givenTheCallerIsNotTheRegisteredPlugin {
        // It Should revert with InvalidPluginAddress
        vm.prank(bob);
        vm.expectRevert(InvalidPluginAddress.selector);
        lockManager.proposalEnded(1);
    }

    modifier givenTheCallerIsTheRegisteredPlugin() {
        _;
    }

    function test_WhenCallingProposalCreatedWithANewProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
    {
        // It Should add the proposal ID to knownProposalIds
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalCreated(123);
        assertEq(lockManager.knownProposalIdAt(0), 123);
    }

    modifier givenAProposalIDIsAlreadyKnown() {
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalCreated(123);
        _;
    }

    function test_WhenCallingProposalCreatedWithThatSameID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
        givenAProposalIDIsAlreadyKnown
    {
        // It Should not change the set of known proposals
        uint256 initialLength = lockManager.knownProposalIdsLength();
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalCreated(123);
        assertEq(lockManager.knownProposalIdsLength(), initialLength);
    }

    function test_WhenCallingProposalEndedWithThatProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
        givenAProposalIDIsAlreadyKnown
    {
        // It Should remove the proposal ID from knownProposalIds
        // It Should emit a ProposalEnded event
        vm.expectEmit(true, false, false, true);
        emit ProposalEnded(123);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(123);

        vm.expectRevert();
        lockManager.knownProposalIdAt(0);
    }

    function test_WhenCallingProposalEndedWithANonexistentProposalID()
        external
        givenThePluginHasBeenSet
        givenTheCallerIsTheRegisteredPlugin
    {
        // It Should do nothing
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(999);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(55667788);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(0);
        vm.prank(address(lockManager.plugin()));
        lockManager.proposalEnded(1000);
    }

    modifier givenTheContractIsInitialized() {
        _;
    }

    modifier givenANonzeroUnderlyingTokenWasProvidedInTheConstructor() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withUnderlyingToken(new TestToken()).build();

        _;
    }

    function test_WhenCallingUnderlyingToken()
        external
        givenTheContractIsInitialized
        givenANonzeroUnderlyingTokenWasProvidedInTheConstructor
    {
        // It Should return the address of the underlying token
        assertEq(address(lockManager.underlyingToken()), address(underlyingToken));
    }

    modifier givenAZeroaddressUnderlyingTokenWasProvidedInTheConstructor() {
        (dao, ltaPlugin, ltvPlugin, lockManager, lockableToken, underlyingToken) =
            builder.withUnderlyingToken(IERC20(address(0))).build();
        _;
    }

    function test_WhenCallingUnderlyingToken2()
        external
        givenTheContractIsInitialized
        givenAZeroaddressUnderlyingTokenWasProvidedInTheConstructor
    {
        // It Should return the address of the main token
        assertEq(address(lockManager.underlyingToken()), address(lockableToken));
    }

    modifier givenAPluginIsSetAndAProposalExists() {
        // This will be handled by more specific modifiers
        _;
    }

    function test_WhenCallingCanVote() external givenVotingPluginIsActive {
        // It Should proxy the call to the plugin's canVote() and return its result
        vm.prank(alice);
        vm.expectCall(
            address(ltvPlugin),
            abi.encodeWithSelector(ltvPlugin.canVote.selector, proposalId, alice, IMajorityVoting.VoteOption.Yes)
        );
        lockManager.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes);
    }

    function test_WhenCallingCanVote2() external givenApprovalPluginIsActive {
        // It Should proxy the call to the plugin's canApprove() and return its result
        vm.prank(alice);
        vm.expectCall(address(ltaPlugin), abi.encodeWithSelector(ltaPlugin.canApprove.selector, proposalId, alice));
        lockManager.canVote(proposalId, alice, IMajorityVoting.VoteOption.Yes);
    }

    modifier givenTheContractHasSeveralKnownProposalIDs() {
        vm.startPrank(address(ltaPlugin));
        lockManager.proposalCreated(101);
        lockManager.proposalCreated(102);
        lockManager.proposalCreated(103);
        vm.stopPrank();

        _;
    }

    function test_WhenCallingKnownProposalIdAtWithAValidIndex()
        external
        givenTheContractIsInitialized
        givenTheContractHasSeveralKnownProposalIDs
    {
        // It Should return the correct proposal ID at that index
        assertEq(lockManager.knownProposalIdAt(0), 101);
        assertEq(lockManager.knownProposalIdAt(1), 102);
        assertEq(lockManager.knownProposalIdAt(2), 103);
    }

    function test_RevertWhen_CallingKnownProposalIdAtWithAnOutofboundsIndex()
        external
        givenTheContractIsInitialized
        givenTheContractHasSeveralKnownProposalIDs
    {
        // It Should revert
        vm.expectRevert();
        lockManager.knownProposalIdAt(3);
        vm.expectRevert();
        lockManager.knownProposalIdAt(10);
    }
}
