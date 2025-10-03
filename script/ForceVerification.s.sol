// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../src/LockToVotePlugin.sol";
import {ILockToGovernBase} from "../src/interfaces/ILockToGovernBase.sol";
import {createProxyAndCall} from "../src/util/proxy.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import {LockManagerERC20} from "../src/LockManagerERC20.sol";
import {MinVotingPowerCondition} from "../src/conditions/MinVotingPowerCondition.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ForceVerificationScript is Script {
    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Chain ID:", block.chainid);
        console.log("Deploying from:", vm.addr(privKey));
        console.log("");

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        // LockManagerERC20
        LockManagerERC20 lockManager = new LockManagerERC20(IERC20(address(0)));
        console.log("Deploying dummy LockManagerERC20", address(lockManager));

        // Condition
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(1234), operation: IPlugin.Operation.Call});

        MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.Standard,
            supportThresholdRatio: 500_000,
            minParticipationRatio: 500_000,
            minApprovalRatio: 500_000,
            proposalDuration: 10 days,
            minProposerVotingPower: 0
        });

        LockToVotePlugin ltvPlugin = LockToVotePlugin(
            createProxyAndCall(
                address(new LockToVotePlugin()),
                abi.encodeCall(
                    LockToVotePlugin.initialize,
                    (IDAO(address(1234)), lockManager, votingSettings, targetConfig, bytes(""))
                )
            )
        );

        console.log(
            "Deploying dummy MinVotingPowerCondition",
            address(new MinVotingPowerCondition(ILockToGovernBase(ltvPlugin)))
        );

        // Proxy
        console.log("Deploying dummy ERC1967Proxy", address(new ERC1967Proxy(address(ltvPlugin), bytes(""))));
    }
}
