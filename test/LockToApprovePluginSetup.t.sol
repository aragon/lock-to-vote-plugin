// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "./lib/TestBase.sol";
import {LockToApprovePluginSetup} from "../src/setup/LockToApprovePluginSetup.sol";
import {LockToApprovePlugin} from "../src/LockToApprovePlugin.sol";
import {LockManager} from "../src/LockManager.sol";
import {MinVotingPowerCondition} from "../src/conditions/MinVotingPowerCondition.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockToApprovePluginSetupTest is TestBase {
    // Contracts
    LockToApprovePluginSetup internal setup;
    DAO internal dao;
    TestToken internal token;

    // Parameters
    LockToApprovePluginSetup.InstallationParameters internal installParams;
    bytes internal installData;

    // Results from prepareInstallation
    address internal plugin;

    function setUp() public {
        setup = new LockToApprovePluginSetup();
        dao = DAO(
            payable(createProxyAndCall(DAO_BASE, abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))))
        );
        token = new TestToken();
    }

    function test_WhenDeployingANewInstance() external {
        // It completes without errors
        assertNotEq(address(new LockToApprovePluginSetup()), address(0));
    }

    modifier whenPreparingAnInstallation() {
        installParams = LockToApprovePluginSetup.InstallationParameters({
            token: token,
            underlyingToken: IERC20(address(0)),
            approvalSettings: LockToApprovePlugin.ApprovalSettings({
                approvalMode: LockToApprovePlugin.ApprovalMode.Standard,
                minApprovalRatio: 100_000, // 10%
                proposalDuration: 10 days,
                minProposerVotingPower: 1 ether
            }),
            pluginMetadata: "ipfs://...",
            createProposalCaller: alice,
            executeCaller: bob,
            targetConfig: IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
        });

        installData = setup.encodeInstallationParams(installParams);

        _;
    }

    function test_WhenPreparingAnInstallation() external whenPreparingAnInstallation {
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (plugin, preparedSetupData) = setup.prepareInstallation(address(dao), installData);

        // It should return the plugin address
        assertNotEq(plugin, address(0));

        // It should return a list with the 3 helpers
        assertEq(preparedSetupData.helpers.length, 3, "Incorrect helper count");
        address lockManagerAddr = preparedSetupData.helpers[0];
        assertEq(preparedSetupData.helpers[1], installParams.createProposalCaller, "helper 1 mismatch");
        assertEq(preparedSetupData.helpers[2], installParams.executeCaller, "helper 2 mismatch");

        // It all plugins use the same implementation
        address pluginImplementation = _getImplementation(address(plugin));
        assertEq(pluginImplementation, setup.implementation(), "Plugin implementation mismatch");

        // It the plugin has the given settings
        LockToApprovePlugin ltaPlugin = LockToApprovePlugin(plugin);
        assertEq(
            ltaPlugin.minApprovalRatio(), installParams.approvalSettings.minApprovalRatio, "minApprovalRatio mismatch"
        );
        assertEq(
            ltaPlugin.proposalDuration(), installParams.approvalSettings.proposalDuration, "proposalDuration mismatch"
        );
        assertEq(
            ltaPlugin.minProposerVotingPower(),
            installParams.approvalSettings.minProposerVotingPower,
            "minProposerVotingPower mismatch"
        );

        // It should set the address of the lockManager on the plugin
        // (Note: test name is misleading, it sets the plugin on the lock manager)
        assertEq(address(LockManager(lockManagerAddr).plugin()), plugin, "Plugin address not set on lock manager");

        // It the plugin should have the right lockManager address
        assertEq(address(ltaPlugin.lockManager()), lockManagerAddr, "Lock manager address mismatch on plugin");

        // It the list of permissions should match
        assertEq(preparedSetupData.permissions.length, 8, "Incorrect permission count");

        LockToApprovePlugin impl = LockToApprovePlugin(setup.implementation());

        _assertPermission(
            preparedSetupData.permissions[0],
            PermissionLib.Operation.Grant,
            address(dao),
            plugin,
            PermissionLib.NO_CONDITION,
            dao.EXECUTE_PERMISSION_ID()
        );
        _assertPermission(
            preparedSetupData.permissions[1],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPDATE_SETTINGS_PERMISSION_ID()
        );
        _assertPermission(
            preparedSetupData.permissions[2],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPGRADE_PLUGIN_PERMISSION_ID()
        );
        _assertPermission(
            preparedSetupData.permissions[3],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_TARGET_CONFIG_PERMISSION_ID()
        );
        _assertPermission(
            preparedSetupData.permissions[4],
            PermissionLib.Operation.Grant,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_METADATA_PERMISSION_ID()
        );
        _assertPermission(
            preparedSetupData.permissions[5],
            PermissionLib.Operation.Grant,
            plugin,
            installParams.createProposalCaller,
            preparedSetupData.permissions[5].condition,
            impl.CREATE_PROPOSAL_PERMISSION_ID()
        );
        address conditionAddr = address(preparedSetupData.permissions[5].condition);
        assertNotEq(conditionAddr, PermissionLib.NO_CONDITION, "Condition should exist for CREATE_PROPOSAL");
        assertTrue(conditionAddr.code.length > 0, "condition is not a contract");
        assertEq(address(MinVotingPowerCondition(conditionAddr).plugin()), address(plugin), "condition plugin mismatch");
        assertEq(address(MinVotingPowerCondition(conditionAddr).token()), address(token), "condition token mismatch");

        _assertPermission(
            preparedSetupData.permissions[6],
            PermissionLib.Operation.Grant,
            plugin,
            lockManagerAddr,
            PermissionLib.NO_CONDITION,
            impl.LOCK_MANAGER_PERMISSION_ID()
        );
        _assertPermission(
            preparedSetupData.permissions[7],
            PermissionLib.Operation.Grant,
            plugin,
            installParams.executeCaller,
            PermissionLib.NO_CONDITION,
            impl.EXECUTE_PROPOSAL_PERMISSION_ID()
        );
    }

    function test_RevertWhen_PassingAnInvalidTokenContract() external whenPreparingAnInstallation {
        // It should revert

        // Case 1: Token is not a contract
        installParams.token = IERC20(alice);
        bytes memory encodedParams = setup.encodeInstallationParams(installParams);
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePluginSetup.TokenNotContract.selector, alice));
        setup.prepareInstallation(address(dao), encodedParams);

        // Case 2: Token is not ERC20 compliant
        installParams.token = IERC20(address(setup));
        encodedParams = setup.encodeInstallationParams(installParams);
        vm.expectRevert(abi.encodeWithSelector(LockToApprovePluginSetup.TokenNotERC20.selector, address(setup)));
        setup.prepareInstallation(address(dao), encodedParams);
    }

    modifier whenPreparingAnUninstallation() {
        installParams = LockToApprovePluginSetup.InstallationParameters({
            token: token,
            underlyingToken: IERC20(address(0)),
            approvalSettings: LockToApprovePlugin.ApprovalSettings({
                approvalMode: LockToApprovePlugin.ApprovalMode.Standard,
                minApprovalRatio: 100_000, // 10%
                proposalDuration: 10 days,
                minProposerVotingPower: 1 ether
            }),
            pluginMetadata: "ipfs://...",
            createProposalCaller: alice,
            executeCaller: bob,
            targetConfig: IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
        });
        installData = setup.encodeInstallationParams(installParams);
        _;
    }

    function test_WhenPreparingAnUninstallation() external whenPreparingAnUninstallation {
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (plugin, preparedSetupData) = setup.prepareInstallation(address(dao), installData);
        // It generates a correct list of permission changes
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: plugin, currentHelpers: preparedSetupData.helpers, data: ""});

        PermissionLib.MultiTargetPermission[] memory perms = setup.prepareUninstallation(address(dao), payload);
        assertEq(perms.length, 8, "Incorrect permission count for uninstallation");

        LockToApprovePlugin impl = LockToApprovePlugin(setup.implementation());
        address lockManagerAddr = preparedSetupData.helpers[0];
        address createProposalCaller = preparedSetupData.helpers[1];
        address executeCaller = preparedSetupData.helpers[2];

        _assertPermission(
            perms[0],
            PermissionLib.Operation.Revoke,
            address(dao),
            plugin,
            PermissionLib.NO_CONDITION,
            dao.EXECUTE_PERMISSION_ID()
        );
        _assertPermission(
            perms[1],
            PermissionLib.Operation.Revoke,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPDATE_SETTINGS_PERMISSION_ID()
        );
        _assertPermission(
            perms[2],
            PermissionLib.Operation.Revoke,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPGRADE_PLUGIN_PERMISSION_ID()
        );
        _assertPermission(
            perms[3],
            PermissionLib.Operation.Revoke,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_TARGET_CONFIG_PERMISSION_ID()
        );
        _assertPermission(
            perms[4],
            PermissionLib.Operation.Revoke,
            plugin,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_METADATA_PERMISSION_ID()
        );
        _assertPermission(
            perms[5],
            PermissionLib.Operation.Revoke,
            plugin,
            createProposalCaller,
            PermissionLib.NO_CONDITION,
            impl.CREATE_PROPOSAL_PERMISSION_ID()
        );
        _assertPermission(
            perms[6],
            PermissionLib.Operation.Revoke,
            plugin,
            lockManagerAddr,
            PermissionLib.NO_CONDITION,
            impl.LOCK_MANAGER_PERMISSION_ID()
        );
        _assertPermission(
            perms[7],
            PermissionLib.Operation.Revoke,
            plugin,
            executeCaller,
            PermissionLib.NO_CONDITION,
            impl.EXECUTE_PROPOSAL_PERMISSION_ID()
        );

        // All uninstallation permissions should have NO_CONDITION
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(address(perms[i].condition), PermissionLib.NO_CONDITION, "Revoke condition mismatch");
        }
    }

    function test_RevertGiven_AListOfHelpersWithMoreOrLessThan3() external whenPreparingAnUninstallation {
        // It should revert
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: plugin, currentHelpers: new address[](2), data: ""}); // 2 helpers

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePluginSetup.WrongHelpersArrayLength.selector, 2));
        setup.prepareUninstallation(address(dao), payload);

        address[] memory helpers_4 = new address[](4);
        payload.currentHelpers = helpers_4; // 4 helpers

        vm.expectRevert(abi.encodeWithSelector(LockToApprovePluginSetup.WrongHelpersArrayLength.selector, 4));
        setup.prepareUninstallation(address(dao), payload);
    }

    /// @dev Asserts that a permission matches the expected values.
    function _assertPermission(
        PermissionLib.MultiTargetPermission memory actual,
        PermissionLib.Operation op,
        address where,
        address who,
        address condition,
        bytes32 permissionId
    ) internal pure {
        assertEq(uint8(actual.operation), uint8(op), "operation mismatch");
        assertEq(actual.where, where, "permission where");
        assertEq(actual.who, who, "permission who");
        assertEq(actual.condition, condition, "permission condition");
        assertEq(actual.permissionId, permissionId, "permission id");
    }

    /// @dev Gets the implementation address from an ERC1967 proxy.
    function _getImplementation(address proxy) internal view returns (address) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implBytes = vm.load(proxy, slot);
        return address(uint160(uint256(implBytes)));
    }
}
