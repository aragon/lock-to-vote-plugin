// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

contract LockToApprovePluginSetupTest is Test {
    function test_WhenDeployingANewInstance() external {
        // It completes without errors
        vm.skip(true);
    }

    modifier whenPreparingAnInstallation() {
        _;
    }

    function test_WhenPreparingAnInstallation() external whenPreparingAnInstallation {
        // It should return the plugin address
        // It should return a list with the 3 helpers
        // It all plugins use the same implementation
        // It the plugin has the given settings
        // It should set the address of the lockManager on the plugin
        // It the plugin should have the right lockManager address
        // It the list of permissions should match
        vm.skip(true);
    }

    function test_RevertWhen_PassingAnInvalidTokenContract() external whenPreparingAnInstallation {
        // It should revert
        vm.skip(true);
    }

    modifier whenPreparingAnUninstallation() {
        _;
    }

    function test_WhenPreparingAnUninstallation() external whenPreparingAnUninstallation {
        // It generates a correct list of permission changes
        vm.skip(true);
    }

    function test_RevertGiven_AListOfHelpersWithMoreOrLessThan3() external whenPreparingAnUninstallation {
        // It should revert
        vm.skip(true);
    }
}
