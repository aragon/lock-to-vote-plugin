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
    LockToApprovePlugin ltaPlugin;
    LockToVotePlugin ltvPlugin;
    IERC20 token;

    function setUp() public {
        vm.startPrank(alice);
        vm.warp(1 days);
        vm.roll(100);

        builder = new DaoBuilder();
        (, ltaPlugin, ltvPlugin,, token,) = builder.withTokenHolder(alice, 1 ether).withTokenHolder(bob, 10 ether)
            .withTokenHolder(carol, 10 ether).withTokenHolder(david, 15 ether).withApprovalPlugin().build();
    }

    function test_WhenDeployingTheContract() external {
        // It records the given plugin address
        // It records the plugin's token address
        vm.skip(true);
    }

    modifier whenCallingIsGranted() {
        _;
    }

    function test_GivenAPluginWithZeroMinimumVotingPower() external whenCallingIsGranted {
        // It should return true
        vm.skip(true);
    }

    function test_GivenAPluginWithAMinimumVotingPower() external whenCallingIsGranted {
        // It should return true when 'who' holds the minimum voting power
        // It should return false when 'who' holds less than the minimum voting power
        vm.skip(true);
    }
}
