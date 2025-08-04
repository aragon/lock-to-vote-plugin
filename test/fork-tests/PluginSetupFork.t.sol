// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ForkTestBase} from "../lib/ForkTestBase.sol";

import {ForkBuilder} from "../builders/ForkBuilder.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {PluginRepo} from "@aragon/osx/src/framework/plugin/repo/PluginRepo.sol";

import {LockToVotePluginSetup} from "../../src/setup/LockToVotePluginSetup.sol";
import {LockToVotePlugin} from "../../src/LockToVotePlugin.sol";
import {IMajorityVoting} from "../../src/interfaces/IMajorityVoting.sol";
import {NON_EMPTY_BYTES} from "../constants.sol";

// Aragon OSx Contracts
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {PermissionManager} from "@aragon/osx/src/core/permission/PermissionManager.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PluginRepo} from "@aragon/osx/src/framework/plugin/repo/PluginRepo.sol";
import {
    PluginSetupRef,
    hashHelpers,
    hashPermissions
} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginSetupProcessor} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

contract PluginSetupForkTest is ForkTestBase {
    DAO internal dao;
    PluginRepo internal repo;
    PluginSetup internal pluginSetup;

    function setUp() public virtual {
        (dao, repo, pluginSetup) = new ForkBuilder().build();
    }

    modifier givenTheDeployerCanInstallPlugins() {
        _;
    }

    function test_WhenInstallingAPluginWithoutAMinimumProposerVotingPower()
        external
        givenTheDeployerCanInstallPlugins
    {
        // It Anyone with the permission can create proposals
        // It Should revert when creating a proposal without permission
        // It Anyone with the permission can execute proposals
        vm.skip(true);
    }

    function test_WhenInstallingAPluginWithAMinimumProposerVotingPower() external givenTheDeployerCanInstallPlugins {
        // It Anyone with the permission and enough voting power can create proposals
        // It Should revert otherwise
        // It Anyone with the permission can execute proposals
        vm.skip(true);
    }
}
