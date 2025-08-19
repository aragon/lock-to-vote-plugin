// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {TestBase} from "./lib/TestBase.sol";
import {LockToVotePluginSetup} from "../src/setup/LockToVotePluginSetup.sol";
import {LockToVotePlugin} from "../src/LockToVotePlugin.sol";
import {LockManagerERC20} from "../src/LockManagerERC20.sol";
import {MinVotingPowerCondition} from "../src/conditions/MinVotingPowerCondition.sol";
import {TestToken} from "./mocks/TestToken.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {MajorityVotingBase} from "../src/base/MajorityVotingBase.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";
import {PluginMode} from "../src/interfaces/ILockManager.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockToVotePluginSetupTest is TestBase {
    // Contracts
    LockToVotePluginSetup internal setup;
    DAO internal dao;
    TestToken internal token;

    // Parameters for installation
    LockToVotePluginSetup.InstallationParameters internal installParams;
    bytes internal encodedParams;

    // Results from prepareInstallation
    address internal pluginAddr;

    function setUp() public {
        setup = new LockToVotePluginSetup();
        dao = DAO(
            payable(createProxyAndCall(DAO_BASE, abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))))
        );
        token = new TestToken();
    }

    function test_WhenDeployingANewInstance() external {
        // It completes without errors
        LockToVotePluginSetup newSetup = new LockToVotePluginSetup();
        assertNotEq(address(newSetup), address(0));
    }

    modifier whenPreparingAnInstallation() {
        installParams = LockToVotePluginSetup.InstallationParameters({
            token: token,
            votingSettings: MajorityVotingBase.VotingSettings({
                votingMode: MajorityVotingBase.VotingMode.Standard,
                supportThresholdRatio: 500_000, // 50%
                minParticipationRatio: 100_000, // 10%
                minApprovalRatio: 200_000, // 20%
                proposalDuration: 7 days,
                minProposerVotingPower: 1 ether
            }),
            pluginMetadata: "ipfs://...",
            createProposalCaller: alice,
            executeCaller: bob,
            targetConfig: IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
        });
        encodedParams = setup.encodeInstallationParams(installParams);
        _;
    }

    function test_WhenPreparingAnInstallation() external whenPreparingAnInstallation {
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), encodedParams);

        // It should return the plugin address
        assertNotEq(pluginAddr, address(0));
        assertTrue(pluginAddr.code.length > 0);

        // It should return a list with the 4 helpers
        assertEq(preparedSetupData.helpers.length, 4, "helpers length should be 4");
        address conditionAddr = preparedSetupData.helpers[0];
        address lockManagerAddr = preparedSetupData.helpers[1];
        address createProposalCaller = preparedSetupData.helpers[2];
        address executeCaller = preparedSetupData.helpers[3];

        assertTrue(conditionAddr.code.length > 0, "condition should be deployed");
        assertTrue(lockManagerAddr.code.length > 0, "lock manager should be deployed");
        assertEq(createProposalCaller, installParams.createProposalCaller, "create proposal caller mismatch");
        assertEq(executeCaller, installParams.executeCaller, "execute caller mismatch");

        // It all plugins use the same implementation
        address pluginImplementation = _getImplementation(pluginAddr);
        assertEq(pluginImplementation, setup.implementation(), "plugin implementation mismatch");

        address minVotingPowerConditionAddr = preparedSetupData.permissions[5].condition;
        assertNotEq(minVotingPowerConditionAddr, address(0));
        assertTrue(minVotingPowerConditionAddr.code.length > 0, "condition helper not deployed");
        MinVotingPowerCondition conditionContract = MinVotingPowerCondition(minVotingPowerConditionAddr);
        assertEq(address(conditionContract.plugin()), pluginAddr, "condition helper has wrong plugin address");

        // It the plugin has the given settings
        LockToVotePlugin plugin = LockToVotePlugin(pluginAddr);
        MajorityVotingBase.VotingSettings memory settings = plugin.getVotingSettings();
        assertEq(uint8(settings.votingMode), uint8(installParams.votingSettings.votingMode));
        assertEq(settings.supportThresholdRatio, installParams.votingSettings.supportThresholdRatio);
        assertEq(settings.minParticipationRatio, installParams.votingSettings.minParticipationRatio);
        assertEq(settings.minApprovalRatio, installParams.votingSettings.minApprovalRatio);
        assertEq(settings.proposalDuration, installParams.votingSettings.proposalDuration);
        assertEq(settings.minProposerVotingPower, installParams.votingSettings.minProposerVotingPower);

        // It should set the address of the lockManager on the plugin
        assertEq(
            address(LockManagerERC20(lockManagerAddr).plugin()), pluginAddr, "plugin address not set on lockManager"
        );

        // It the plugin should have the right lockManager address
        assertEq(address(plugin.lockManager()), lockManagerAddr, "lockManager address mismatch on plugin");

        // It the list of permissions should match
        assertEq(preparedSetupData.permissions.length, 8, "permissions length mismatch");

        LockToVotePlugin impl = LockToVotePlugin(setup.implementation());

        // 0. Plugin can execute on DAO
        _assertPermission(
            preparedSetupData.permissions[0],
            PermissionLib.Operation.Grant,
            address(dao),
            pluginAddr,
            PermissionLib.NO_CONDITION,
            dao.EXECUTE_PERMISSION_ID()
        );
        // 1. DAO can update plugin settings
        _assertPermission(
            preparedSetupData.permissions[1],
            PermissionLib.Operation.Grant,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPDATE_SETTINGS_PERMISSION_ID()
        );
        // 2. DAO can upgrade plugin
        _assertPermission(
            preparedSetupData.permissions[2],
            PermissionLib.Operation.Grant,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPGRADE_PLUGIN_PERMISSION_ID()
        );
        // 3. DAO can update target config
        _assertPermission(
            preparedSetupData.permissions[3],
            PermissionLib.Operation.Grant,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_TARGET_CONFIG_PERMISSION_ID()
        );
        // 4. DAO can update plugin metadata
        _assertPermission(
            preparedSetupData.permissions[4],
            PermissionLib.Operation.Grant,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_METADATA_PERMISSION_ID()
        );
        // 5. Caller can create proposal
        _assertPermission(
            preparedSetupData.permissions[5],
            PermissionLib.Operation.GrantWithCondition,
            pluginAddr,
            installParams.createProposalCaller,
            minVotingPowerConditionAddr,
            impl.CREATE_PROPOSAL_PERMISSION_ID()
        );
        assertEq(conditionAddr, address(preparedSetupData.permissions[5].condition), "Condition should match");
        assertNotEq(conditionAddr, PermissionLib.NO_CONDITION, "Condition should exist for CREATE_PROPOSAL");
        assertTrue(conditionAddr.code.length > 0, "condition is not a contract");
        assertEq(address(MinVotingPowerCondition(conditionAddr).plugin()), address(plugin), "condition plugin mismatch");
        assertEq(address(MinVotingPowerCondition(conditionAddr).token()), address(token), "condition token mismatch");

        // 6. LockManagerERC20 can manage plugin
        _assertPermission(
            preparedSetupData.permissions[6],
            PermissionLib.Operation.Grant,
            pluginAddr,
            lockManagerAddr,
            PermissionLib.NO_CONDITION,
            impl.LOCK_MANAGER_PERMISSION_ID()
        );
        // 7. Caller can execute proposal
        _assertPermission(
            preparedSetupData.permissions[7],
            PermissionLib.Operation.Grant,
            pluginAddr,
            installParams.executeCaller,
            PermissionLib.NO_CONDITION,
            impl.EXECUTE_PROPOSAL_PERMISSION_ID()
        );
    }

    function test_RevertWhen_PassingAnInvalidTokenContract() external whenPreparingAnInstallation {
        // It should revert

        // Case 1: Token is not a contract
        installParams.token = IERC20(alice);
        encodedParams = setup.encodeInstallationParams(installParams);
        vm.expectRevert(abi.encodeWithSelector(LockToVotePluginSetup.TokenNotContract.selector, alice));
        setup.prepareInstallation(address(dao), encodedParams);

        // Case 2: Token is not ERC20 compliant
        installParams.token = IERC20(address(setup));
        encodedParams = setup.encodeInstallationParams(installParams);
        vm.expectRevert(abi.encodeWithSelector(LockToVotePluginSetup.TokenNotERC20.selector, address(setup)));
        setup.prepareInstallation(address(dao), encodedParams);
    }

    modifier whenPreparingAnUninstallation() {
        installParams = LockToVotePluginSetup.InstallationParameters({
            token: token,
            votingSettings: MajorityVotingBase.VotingSettings({
                votingMode: MajorityVotingBase.VotingMode.Standard,
                supportThresholdRatio: 500_000,
                minParticipationRatio: 100_000,
                minApprovalRatio: 200_000,
                proposalDuration: 7 days,
                minProposerVotingPower: 1 ether
            }),
            pluginMetadata: "ipfs://...",
            createProposalCaller: alice,
            executeCaller: bob,
            targetConfig: IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call})
        });
        encodedParams = setup.encodeInstallationParams(installParams);
        _;
    }

    function test_WhenPreparingAnUninstallation() external whenPreparingAnUninstallation {
        // It generates a correct list of permission changes
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (pluginAddr, preparedSetupData) = setup.prepareInstallation(address(dao), encodedParams);

        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: pluginAddr, currentHelpers: preparedSetupData.helpers, data: ""});

        PermissionLib.MultiTargetPermission[] memory revokePermissions =
            setup.prepareUninstallation(address(dao), payload);

        assertEq(revokePermissions.length, 8, "uninstallation permissions length mismatch");

        LockToVotePlugin impl = LockToVotePlugin(setup.implementation());
        address lockManagerAddr = preparedSetupData.helpers[1];

        // 0. Revoke Plugin can execute on DAO
        _assertPermission(
            revokePermissions[0],
            PermissionLib.Operation.Revoke,
            address(dao),
            pluginAddr,
            PermissionLib.NO_CONDITION,
            dao.EXECUTE_PERMISSION_ID()
        );
        // 1. Revoke DAO can update plugin settings
        _assertPermission(
            revokePermissions[1],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPDATE_SETTINGS_PERMISSION_ID()
        );
        // 2. Revoke DAO can upgrade plugin
        _assertPermission(
            revokePermissions[2],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.UPGRADE_PLUGIN_PERMISSION_ID()
        );
        // 3. Revoke DAO can update target config
        _assertPermission(
            revokePermissions[3],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_TARGET_CONFIG_PERMISSION_ID()
        );
        // 4. Revoke DAO can update plugin metadata
        _assertPermission(
            revokePermissions[4],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            address(dao),
            PermissionLib.NO_CONDITION,
            impl.SET_METADATA_PERMISSION_ID()
        );
        // 5. Revoke Caller can create proposal
        _assertPermission(
            revokePermissions[5],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            installParams.createProposalCaller,
            PermissionLib.NO_CONDITION,
            impl.CREATE_PROPOSAL_PERMISSION_ID()
        );
        // 6. Revoke LockManagerERC20 can manage plugin
        _assertPermission(
            revokePermissions[6],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            lockManagerAddr,
            PermissionLib.NO_CONDITION,
            impl.LOCK_MANAGER_PERMISSION_ID()
        );
        // 7. Revoke Caller can execute proposal
        _assertPermission(
            revokePermissions[7],
            PermissionLib.Operation.Revoke,
            pluginAddr,
            installParams.executeCaller,
            PermissionLib.NO_CONDITION,
            impl.EXECUTE_PROPOSAL_PERMISSION_ID()
        );
    }

    function test_RevertGiven_AListOfHelpersWithMoreOrLessThan3() external whenPreparingAnUninstallation {
        // It should revert

        // Case 1: Less than 3 helpers
        address[] memory wrongHelpers1 = new address[](3);
        IPluginSetup.SetupPayload memory payload1 =
            IPluginSetup.SetupPayload({plugin: pluginAddr, currentHelpers: wrongHelpers1, data: ""});

        vm.expectRevert(abi.encodeWithSelector(LockToVotePluginSetup.WrongHelpersArrayLength.selector, 3));
        setup.prepareUninstallation(address(dao), payload1);

        // Case 2: More than 3 helpers
        address[] memory wrongHelpers2 = new address[](5);
        IPluginSetup.SetupPayload memory payload2 =
            IPluginSetup.SetupPayload({plugin: pluginAddr, currentHelpers: wrongHelpers2, data: ""});

        vm.expectRevert(abi.encodeWithSelector(LockToVotePluginSetup.WrongHelpersArrayLength.selector, 5));
        setup.prepareUninstallation(address(dao), payload2);
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
