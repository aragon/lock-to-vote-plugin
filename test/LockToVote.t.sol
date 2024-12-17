// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AragonTest} from "./util/AragonTest.sol";

contract LockToVoteTest is AragonTest {
    function test_WhenDeployingTheContract() external {
        // It should disable the initializers
        vm.skip(true);
    }

    modifier givenANewProxy() {
        _;
    }

    function test_WhenCallingInitialize() external givenANewProxy {
        // It should set the DAO address
        // It should initialize normally
        vm.skip(true);
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        vm.skip(true);
    }

    modifier whenCallingUpdateSettings() {
        _;
    }

    function test_RevertWhen_UpdateSettingsWithoutThePermission()
        external
        whenCallingUpdateSettings
    {
        // It should revert
        vm.skip(true);
    }

    function test_WhenCallingSupportsInterface() external {
        // It does not support the empty interface
        // It supports IERC165Upgradeable
        vm.skip(true);
    }
}
