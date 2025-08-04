// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ForkTestBase} from "../lib/ForkTestBase.sol";

import {LockToVotePluginSetup} from "../../src/setup/LockToVotePluginSetup.sol";
import {LockToVotePlugin} from "../../src/LockToVotePlugin.sol";
import {ILockManager} from "../../src/interfaces/ILockManager.sol";
import {MajorityVotingBase} from "../../src/base/MajorityVotingBase.sol";
import {IMajorityVoting} from "../../src/interfaces/IMajorityVoting.sol";

import {ForkBuilder} from "../builders/ForkBuilder.sol";
import {NON_EMPTY_BYTES} from "../constants.sol";

// Aragon OSx Contracts
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {PermissionManager} from "@aragon/osx/src/core/permission/PermissionManager.sol";
import {PluginRepo} from "@aragon/osx/src/framework/plugin/repo/PluginRepo.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    PluginSetupRef,
    hashHelpers,
    hashPermissions
} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginSetupProcessor} from "@aragon/osx/src/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {TestToken} from "../mocks/TestToken.sol";

contract PluginSetupForkTest is ForkTestBase {
    DAO internal dao;
    PluginRepo internal repo;
    LockToVotePluginSetup internal pluginSetup;
    TestToken internal token;
    address internal constant ANY_ADDR = address(type(uint160).max);

    function setUp() public virtual {
        (dao, repo, pluginSetup, token) = new ForkBuilder().build();
    }

    modifier givenTheDeployerCanInstallPlugins() {
        // PERMISSIONS
        // Grant the necessary permissions for the PluginSetupProcessor to install
        dao.grant(address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID());
        dao.grant(
            address(pluginSetupProcessor), address(this), pluginSetupProcessor.APPLY_UNINSTALLATION_PERMISSION_ID()
        );
        dao.grant(address(dao), address(pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        _;
    }

    function test_WhenPreparingAndApplyingAnInstallation() external givenTheDeployerCanInstallPlugins {
        // INSTALLATION
        // Prepare installation data using the token
        bytes memory installData;
        {
            LockToVotePluginSetup.InstallationParameters memory installParams = LockToVotePluginSetup
                .InstallationParameters({
                token: token,
                votingSettings: MajorityVotingBase.VotingSettings({
                    votingMode: MajorityVotingBase.VotingMode.Standard,
                    supportThresholdRatio: 500_000, // 50%
                    minParticipationRatio: 100_000, // 10%
                    minApprovalRatio: 200_000, // 20%
                    proposalDuration: 1 hours,
                    minProposerVotingPower: 0
                }),
                pluginMetadata: "ipfs://...",
                createProposalCaller: alice,
                executeCaller: bob,
                targetConfig: IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
            });

            installData = pluginSetup.encodeInstallationParams(installParams);
        }

        // Prepare and apply the installation
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;
        {
            PluginSetupRef memory setupRef = PluginSetupRef({versionTag: getLatestTag(repo), pluginSetupRepo: repo});
            PluginSetupProcessor.PrepareInstallationParams memory prepareInstallParams =
                PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: setupRef, data: installData});

            // PREPARE
            (pluginAddr, preparedSetupData) =
                pluginSetupProcessor.prepareInstallation(address(dao), prepareInstallParams);

            vm.label(pluginAddr, "NewPlugin");

            // APPLY
            PluginSetupProcessor.ApplyInstallationParams memory applyInstallParams = PluginSetupProcessor
                .ApplyInstallationParams({
                pluginSetupRef: setupRef,
                plugin: pluginAddr,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            });
            pluginSetupProcessor.applyInstallation(address(dao), applyInstallParams);

            vm.assertTrue(
                dao.isGranted(address(dao), pluginAddr, dao.EXECUTE_PERMISSION_ID(), ""), "Plugin should be installed"
            );
        }

        token.mint(alice, 1 ether);

        // It Successfully sets the appropriate permissions
        {
            LockToVotePlugin plugin = LockToVotePlugin(pluginAddr);
            assertEq(address(plugin.lockManager().token()), address(token), "Token address mismatch");
            assertTrue(plugin.isMember(alice), "Alice should be a member");
            assertFalse(plugin.isMember(bob), "Bob should not be a member");
        }
    }

    function test_WhenInstallingAPluginWithoutAMinimumProposerVotingPower()
        external
        givenTheDeployerCanInstallPlugins
    {
        // INSTALLATION
        // Prepare installation data using the token
        bytes memory installData;
        {
            LockToVotePluginSetup.InstallationParameters memory installParams = LockToVotePluginSetup
                .InstallationParameters({
                token: token,
                votingSettings: MajorityVotingBase.VotingSettings({
                    votingMode: MajorityVotingBase.VotingMode.Standard,
                    supportThresholdRatio: 500_000, // 50%
                    minParticipationRatio: 100_000, // 10%
                    minApprovalRatio: 200_000, // 20%
                    proposalDuration: 1 hours,
                    minProposerVotingPower: 0 // No minimum voting power
                }),
                pluginMetadata: "ipfs://...",
                createProposalCaller: alice, // Only Alice can propose
                executeCaller: bob, // Only Bob can execute (if passed)
                targetConfig: IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
            });

            installData = pluginSetup.encodeInstallationParams(installParams);
        }

        // Prepare and apply the installation
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;
        {
            PluginSetupRef memory setupRef = PluginSetupRef({versionTag: getLatestTag(repo), pluginSetupRepo: repo});
            PluginSetupProcessor.PrepareInstallationParams memory prepareInstallParams =
                PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: setupRef, data: installData});

            // PREPARE
            (pluginAddr, preparedSetupData) =
                pluginSetupProcessor.prepareInstallation(address(dao), prepareInstallParams);

            vm.label(pluginAddr, "NewPlugin");

            // APPLY
            PluginSetupProcessor.ApplyInstallationParams memory applyInstallParams = PluginSetupProcessor
                .ApplyInstallationParams({
                pluginSetupRef: setupRef,
                plugin: pluginAddr,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            });
            pluginSetupProcessor.applyInstallation(address(dao), applyInstallParams);
        }

        LockToVotePlugin plugin = LockToVotePlugin(pluginAddr);
        ILockManager lockManager = plugin.lockManager();

        token.mint(randomWallet, 1);
        Action[] memory actions = new Action[](0);

        // It Should revert when creating a proposal without permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(pluginAddr), bob, plugin.CREATE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        plugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        // It Anyone with the permission can create proposals
        vm.prank(alice); // no token balance, but the minimum required is 0
        uint256 proposalId = plugin.createProposal("ipfs://", actions, 0, 0, bytes(""));

        token.mint(alice, 1 ether);

        // Make the proposal pass
        vm.prank(alice);
        token.approve(address(lockManager), 1 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.warp(block.timestamp + 1 hours);

        // It Anyone with the permission can execute (passed) proposals
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(pluginAddr),
                alice,
                plugin.EXECUTE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(alice);
        plugin.execute(proposalId);

        vm.prank(bob);
        plugin.execute(proposalId);
    }

    function test_WhenInstallingAPluginWithAMinimumProposerVotingPower() external givenTheDeployerCanInstallPlugins {
        // INSTALLATION
        // Prepare installation data using the token
        bytes memory installData;
        {
            LockToVotePluginSetup.InstallationParameters memory installParams = LockToVotePluginSetup
                .InstallationParameters({
                token: token,
                votingSettings: MajorityVotingBase.VotingSettings({
                    votingMode: MajorityVotingBase.VotingMode.Standard,
                    supportThresholdRatio: 500_000, // 50%
                    minParticipationRatio: 100_000, // 10%
                    minApprovalRatio: 200_000, // 20%
                    proposalDuration: 1 hours,
                    minProposerVotingPower: 10 ether // MIN VOTING POWER
                }),
                pluginMetadata: "ipfs://...",
                createProposalCaller: ANY_ADDR, // anyone with minProposalVotingPower can propose
                executeCaller: ANY_ADDR, // Anyone can execute passed proposals
                targetConfig: IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
            });

            installData = pluginSetup.encodeInstallationParams(installParams);
        }

        // Prepare and apply the installation
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        address pluginAddr;
        {
            PluginSetupRef memory setupRef = PluginSetupRef({versionTag: getLatestTag(repo), pluginSetupRepo: repo});
            PluginSetupProcessor.PrepareInstallationParams memory prepareInstallParams =
                PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: setupRef, data: installData});

            // PREPARE
            (pluginAddr, preparedSetupData) =
                pluginSetupProcessor.prepareInstallation(address(dao), prepareInstallParams);

            vm.label(pluginAddr, "NewPlugin");

            // APPLY
            PluginSetupProcessor.ApplyInstallationParams memory applyInstallParams = PluginSetupProcessor
                .ApplyInstallationParams({
                pluginSetupRef: setupRef,
                plugin: pluginAddr,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            });
            pluginSetupProcessor.applyInstallation(address(dao), applyInstallParams);
        }

        LockToVotePlugin plugin = LockToVotePlugin(pluginAddr);
        ILockManager lockManager = plugin.lockManager();

        token.mint(randomWallet, 1);
        Action[] memory actions = new Action[](0);

        // It Anyone with the permission (and enough voting power) can create proposals
        token.mint(alice, 15 ether);

        vm.prank(alice);
        uint256 proposalId = plugin.createProposal("ipfs://1234", actions, 0, 0, bytes(""));

        // It Should revert otherwise
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(pluginAddr), bob, plugin.CREATE_PROPOSAL_PERMISSION_ID()
            )
        );
        vm.prank(bob);
        plugin.createProposal("ipfs://2345", actions, 0, 0, bytes(""));

        // Can't execute proposals that haven't passed
        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert();
        vm.prank(alice);
        plugin.execute(proposalId);

        // New proposal
        vm.prank(alice);
        proposalId = plugin.createProposal("ipfs://3456", actions, 0, 0, bytes(""));

        // Make the proposal pass
        vm.prank(alice);
        token.approve(address(lockManager), 15 ether);
        vm.prank(alice);
        lockManager.lockAndVote(proposalId, IMajorityVoting.VoteOption.Yes);

        vm.warp(block.timestamp + 1 hours);

        // It Anyone with the permission can execute (passed) proposals
        vm.prank(alice);
        plugin.execute(proposalId);
    }
}
