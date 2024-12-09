// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {AragonTest} from "./util/AragonTest.sol";

contract LockToVoteTest is AragonTest {
    function test_WhenDeployingTheContract() external {
        // It should initialize normally
        vm.skip(true);
    }

    function test_GivenADeployedContract() external {
        // It should refuse to initialize again
        vm.skip(true);
    }

    modifier givenANewInstance() {
        _;
    }

    function test_GivenCallingInitialize() external givenANewInstance {
        // It should set the DAO address
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
