// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "./lib/TestBase.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MinVotingPowerCondition} from "../src/conditions/MinVotingPowerCondition.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";

contract MinVotingPowerConditionTest is TestBase {
    DaoBuilder builder;
    DAO dao;
    LockToVotePlugin ltvPlugin;
    IERC20 token;

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, ltvPlugin,, token) = builder.withTokenHolder(alice, 1 ether).withTokenHolder(bob, 10 ether)
            .withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether).withDaoOwner(alice).build();
    }

    function test_WhenDeployingTheContract() external {
        // Deploys a testable version of the condition contract
        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltvPlugin)));

        // It records the given plugin address
        assertEq(address(condition.plugin()), address(ltvPlugin), "Should record plugin address");

        // It records the plugin's token address
        assertEq(address(condition.token()), address(token), "Should record plugin's token address");
    }

    modifier whenCallingIsGranted() {
        _;
    }

    function test_GivenAPluginWithZeroMinimumVotingPower() external whenCallingIsGranted {
        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltvPlugin)));

        // It should return true
        assertEq(ltvPlugin.minProposerVotingPower(), 0, "Pre-condition: min power should be 0");

        // Test with a user with no tokens
        assertTrue(
            condition.isGranted(address(0x0), randomWallet, bytes32(0x0), ""),
            "Should return true for user with no tokens if min power is 0"
        );
        // Test with a user with tokens
        assertTrue(
            condition.isGranted(address(0x0), alice, bytes32(0x0), ""),
            "Should return true for user with tokens if min power is 0"
        );
    }

    function test_GivenAPluginWithAMinimumVotingPower() external whenCallingIsGranted {
        // Grant alice permission to update settings. Prank is active from setUp.
        dao.grant(address(ltvPlugin), alice, ltvPlugin.UPDATE_SETTINGS_PERMISSION_ID());

        // Update settings to require a minimum voting power
        uint256 minPower = 10 ether;
        MajorityVotingBase.VotingSettings memory newSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.VoteReplacement,
            supportThresholdRatio: 500_000,
            minParticipationRatio: ltvPlugin.minParticipationRatio(),
            minApprovalRatio: 150_000,
            proposalDuration: ltvPlugin.proposalDuration(),
            minProposerVotingPower: minPower
        });
        ltvPlugin.updateVotingSettings(newSettings);
        assertEq(ltvPlugin.minProposerVotingPower(), minPower, "Min power should be updated");

        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltvPlugin)));

        // It should return false when 'who' holds less than the minimum voting power
        assertFalse(
            condition.isGranted(address(0x0), alice, bytes32(0x0), ""), // Alice has 1 ether, 0 locked
            "Should return false for user with less than min power"
        );

        vm.startPrank(alice);
        token.approve(address(ltvPlugin.lockManager()), 0.5 ether);
        ltvPlugin.lockManager().lock();
        assertFalse(
            condition.isGranted(address(0x0), alice, bytes32(0x0), ""), // Alice has 0.5 ether locked
            "Should return false for alice"
        );

        // It should return true when 'who' holds the minimum voting power
        assertFalse(
            condition.isGranted(address(0x0), bob, bytes32(0x0), ""), // Bob has 10 ether, 0 locked
            "Should return false for user with no tokens locked"
        );
        vm.startPrank(bob);
        token.approve(address(ltvPlugin.lockManager()), 9.5 ether);
        ltvPlugin.lockManager().lock();
        assertFalse(
            condition.isGranted(address(0x0), bob, bytes32(0x0), ""), // Bob has 0.5 ether, 9.5 locked
            "Should return false for user with less than minPower locked"
        );
        token.approve(address(ltvPlugin.lockManager()), 0.5 ether);
        ltvPlugin.lockManager().lock();
        assertTrue(
            condition.isGranted(address(0x0), bob, bytes32(0x0), ""), // Bob has 10 ether, 0 locked
            "Should return true for user with exact min power"
        );

        // 2
        assertFalse(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 15 ether, 0 locked
            "Should return false for user with less than min power"
        );

        vm.startPrank(david);
        token.approve(address(ltvPlugin.lockManager()), 12 ether);
        ltvPlugin.lockManager().lock();
        assertTrue(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 12 ether locked
            "Should return false for user with more than min power"
        );
    }

    function test_GivenTheSenderCreatedManyProposals() external whenCallingIsGranted {
        // Grant alice permission to update settings. Prank is active from setUp.
        dao.grant(address(ltvPlugin), alice, ltvPlugin.UPDATE_SETTINGS_PERMISSION_ID());
        dao.grant(address(ltvPlugin), david, ltvPlugin.CREATE_PROPOSAL_PERMISSION_ID());

        // Update settings to require a minimum voting power
        uint256 minPower = 2 ether;
        MajorityVotingBase.VotingSettings memory newSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.VoteReplacement,
            supportThresholdRatio: 500_000,
            minParticipationRatio: ltvPlugin.minParticipationRatio(),
            minApprovalRatio: 150_000,
            proposalDuration: ltvPlugin.proposalDuration(),
            minProposerVotingPower: minPower
        });
        ltvPlugin.updateVotingSettings(newSettings);

        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltvPlugin)));

        // It the voting power required should be proportional to the amount of proposals created
        vm.startPrank(david);

        // 0 proposals

        assertFalse(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 15 ether, 0 locked
            "Should return false for user with less than min power"
        );

        token.approve(address(ltvPlugin.lockManager()), 1.9 ether);
        ltvPlugin.lockManager().lock();
        assertFalse(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 13.1 ether, 1.9 locked
            "Should return false for user with less than min power"
        );

        token.approve(address(ltvPlugin.lockManager()), 0.1 ether);
        ltvPlugin.lockManager().lock();
        assertTrue(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 13 ether, 2 locked
            "Should return true for user with >= min power"
        );

        ltvPlugin.createProposal(bytes(""), new Action[](0), 0, 0, bytes(""));
        vm.roll(block.number + 1);

        // 1 proposals

        token.approve(address(ltvPlugin.lockManager()), 1.9 ether);
        ltvPlugin.lockManager().lock();
        assertFalse(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 11.1 ether, 3.9 locked
            "Should return false for user with less than min power"
        );

        token.approve(address(ltvPlugin.lockManager()), 0.1 ether);
        ltvPlugin.lockManager().lock();
        assertTrue(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 11 ether, 4 locked
            "Should return true for user with >= min power"
        );

        ltvPlugin.createProposal(bytes(""), new Action[](0), 0, 0, bytes(""));
        vm.roll(block.number + 1);

        // 2 proposals

        token.approve(address(ltvPlugin.lockManager()), 1.9 ether);
        ltvPlugin.lockManager().lock();
        assertFalse(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 9.1 ether, 5.9 locked
            "Should return false for user with less than min power"
        );

        token.approve(address(ltvPlugin.lockManager()), 0.1 ether);
        ltvPlugin.lockManager().lock();
        assertTrue(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 9 ether, 6 locked
            "Should return true for user with >= min power"
        );
    }
}
