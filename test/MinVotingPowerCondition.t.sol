// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "./lib/TestBase.sol";
import {DaoBuilder} from "./builders/DaoBuilder.sol";
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
import {MinVotingPowerCondition} from "../src/conditions/MinVotingPowerCondition.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";

contract MinVotingPowerConditionTest is TestBase {
    DaoBuilder builder;
    DAO dao;
    LockToApprovePlugin ltaPlugin;
    LockToVotePlugin ltvPlugin;
    IERC20 token;

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (dao, ltaPlugin, ltvPlugin,, token,) = builder.withTokenHolder(alice, 1 ether).withTokenHolder(bob, 10 ether)
            .withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether).withApprovalPlugin().withDaoOwner(alice)
            .build();
    }

    function test_WhenDeployingTheContract() external {
        // Deploys a testable version of the condition contract
        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltaPlugin)));

        // It records the given plugin address
        assertEq(address(condition.plugin()), address(ltaPlugin), "Should record plugin address");

        // It records the plugin's token address
        assertEq(address(condition.token()), address(token), "Should record plugin's token address");
    }

    modifier whenCallingIsGranted() {
        _;
    }

    function test_GivenAPluginWithZeroMinimumVotingPower() external whenCallingIsGranted {
        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltaPlugin)));

        // It should return true
        assertEq(ltaPlugin.minProposerVotingPower(), 0, "Pre-condition: min power should be 0");

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
        dao.grant(address(ltaPlugin), alice, ltaPlugin.UPDATE_SETTINGS_PERMISSION_ID());

        // Update settings to require a minimum voting power
        uint256 minPower = 10 ether;
        LockToApprovePlugin.ApprovalSettings memory newSettings = LockToApprovePlugin.ApprovalSettings({
            minApprovalRatio: uint32(ltaPlugin.minApprovalRatio()),
            proposalDuration: ltaPlugin.proposalDuration(),
            minProposerVotingPower: minPower
        });
        ltaPlugin.updateApprovalSettings(newSettings);
        assertEq(ltaPlugin.minProposerVotingPower(), minPower, "Min power should be updated");

        MinVotingPowerCondition condition = new MinVotingPowerCondition(ILockToGovernBase(address(ltaPlugin)));

        // It should return false when 'who' holds less than the minimum voting power
        assertFalse(
            condition.isGranted(address(0x0), alice, bytes32(0x0), ""), // Alice has 1 ether
            "Should return false for user with less than min power"
        );

        // It should return true when 'who' holds the minimum voting power
        assertTrue(
            condition.isGranted(address(0x0), bob, bytes32(0x0), ""), // Bob has 10 ether
            "Should return true for user with exact min power"
        );
        assertTrue(
            condition.isGranted(address(0x0), david, bytes32(0x0), ""), // David has 15 ether
            "Should return true for user with more than min power"
        );
    }
}
