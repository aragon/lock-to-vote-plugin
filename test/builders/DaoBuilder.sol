// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {createProxyAndCall, createSaltedProxyAndCall, predictProxyAddress} from "../../src/util/proxy.sol";
import {ALICE_ADDRESS} from "../constants.sol";
import {LockToApprovePlugin} from "../../src/LockToApprovePlugin.sol";
import {LockToVotePlugin, MajorityVotingBase} from "../../src/LockToVotePlugin.sol";
import {LockManager} from "../../src/LockManager.sol";
import {LockManagerSettings, UnlockMode, PluginMode} from "../../src/interfaces/ILockManager.sol";
import {ILockToGovernBase} from "../../src/interfaces/ILockToGovernBase.sol";
import {RATIO_BASE} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "../mocks/TestToken.sol";

contract DaoBuilder is Test {
    address immutable DAO_BASE = address(new DAO());
    address immutable LOCK_TO_APPROVE_BASE = address(new LockToApprovePlugin());
    address immutable LOCK_TO_VOTE_BASE = address(new LockToVotePlugin());

    struct MintEntry {
        address tokenHolder;
        uint256 amount;
    }

    address owner;

    address[] proposers;
    MintEntry[] tokenHolders;

    // Lock Manager
    UnlockMode unlockMode = UnlockMode.Strict;
    PluginMode pluginMode = PluginMode.Approval;
    IERC20 underlyingTokenAddr;

    // Voting
    MajorityVotingBase.VotingMode votingMode = MajorityVotingBase.VotingMode.Standard;
    uint32 supportThresholdRatio = 100_000; // 10%
    uint32 minParticipationRatio = 100_000; // 10%
    // Approval + voting
    uint32 minApprovalRatio = 100_000; // 10%
    uint32 proposalDuration = 10 days;

    function withDaoOwner(address newOwner) public returns (DaoBuilder) {
        owner = newOwner;
        return this;
    }

    function withTokenHolder(address newTokenHolder, uint256 amount) public returns (DaoBuilder) {
        tokenHolders.push(MintEntry({tokenHolder: newTokenHolder, amount: amount}));
        return this;
    }

    function withStrictUnlock() public returns (DaoBuilder) {
        unlockMode = UnlockMode.Strict;
        return this;
    }

    function withStandardUnlock() public returns (DaoBuilder) {
        unlockMode = UnlockMode.Standard;
        return this;
    }

    function withApprovalPlugin() public returns (DaoBuilder) {
        pluginMode = PluginMode.Approval;
        return this;
    }

    function withVotingPlugin() public returns (DaoBuilder) {
        pluginMode = PluginMode.Voting;
        return this;
    }

    function withStandardVoting() public returns (DaoBuilder) {
        votingMode = MajorityVotingBase.VotingMode.Standard;
        return this;
    }

    function withVoteReplacement() public returns (DaoBuilder) {
        votingMode = MajorityVotingBase.VotingMode.VoteReplacement;
        return this;
    }

    function withEarlyExecution() public returns (DaoBuilder) {
        votingMode = MajorityVotingBase.VotingMode.EarlyExecution;
        return this;
    }

    function withSupportThresholdRatio(uint32 newSupportThresholdRatio) public returns (DaoBuilder) {
        supportThresholdRatio = newSupportThresholdRatio;
        return this;
    }

    function withMinParticipationRatio(uint32 newMinParticipationRatio) public returns (DaoBuilder) {
        minParticipationRatio = newMinParticipationRatio;
        return this;
    }

    function withMinApprovalRatio(uint32 newApprovalRatio) public returns (DaoBuilder) {
        if (newApprovalRatio > RATIO_BASE) revert("Approval ratio above 100%");
        minApprovalRatio = newApprovalRatio;
        return this;
    }

    function withDuration(uint32 newDuration) public returns (DaoBuilder) {
        proposalDuration = newDuration;
        return this;
    }

    function withProposer(address newProposer) public returns (DaoBuilder) {
        proposers.push(newProposer);
        return this;
    }

    function withUnderlyingToken(IERC20 underlyingToken) public returns (DaoBuilder) {
        underlyingTokenAddr = underlyingToken;
        return this;
    }

    /// @dev Creates a DAO with the given orchestration settings.
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build()
        public
        returns (
            DAO dao,
            LockToApprovePlugin ltaPlugin,
            LockToVotePlugin ltvPlugin,
            LockManager lockManager,
            IERC20 lockableToken,
            IERC20 underlyingToken
        )
    {
        if (owner == address(0)) owner = msg.sender;

        // Deploy the DAO with `this` as root
        dao = DAO(
            payable(
                createProxyAndCall(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
                )
            )
        );

        // Deploy ERC20 token
        lockableToken = new TestToken();
        underlyingToken = underlyingTokenAddr;

        if (tokenHolders.length > 0) {
            for (uint256 i = 0; i < tokenHolders.length; i++) {
                TestToken(address(lockableToken)).mint(tokenHolders[i].tokenHolder, tokenHolders[i].amount);
            }
        } else {
            TestToken(address(lockableToken)).mint(owner, 10 ether);
        }

        ILockToGovernBase targetPlugin;

        {
            // Plugin and helper

            lockManager =
                new LockManager(dao, LockManagerSettings(unlockMode, pluginMode), lockableToken, underlyingToken);

            bytes memory pluginMetadata = "";
            IPlugin.TargetConfig memory targetConfig =
                IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});

            if (pluginMode == PluginMode.Approval) {
                LockToApprovePlugin.ApprovalSettings memory approvalSettings = LockToApprovePlugin.ApprovalSettings({
                    minApprovalRatio: minApprovalRatio,
                    proposalDuration: proposalDuration,
                    minProposerVotingPower: 0
                });

                ltaPlugin = LockToApprovePlugin(
                    createProxyAndCall(
                        address(LOCK_TO_APPROVE_BASE),
                        abi.encodeCall(
                            LockToApprovePlugin.initialize,
                            (dao, lockManager, approvalSettings, targetConfig, pluginMetadata)
                        )
                    )
                );
                targetPlugin = ILockToGovernBase(address(ltaPlugin));
            } else {
                MajorityVotingBase.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
                    votingMode: votingMode,
                    supportThresholdRatio: supportThresholdRatio,
                    minParticipationRatio: minParticipationRatio,
                    minApprovalRatio: minApprovalRatio,
                    proposalDuration: proposalDuration,
                    minProposerVotingPower: 0
                });

                ltvPlugin = LockToVotePlugin(
                    createProxyAndCall(
                        address(LOCK_TO_VOTE_BASE),
                        abi.encodeCall(
                            LockToVotePlugin.initialize,
                            (dao, lockManager, votingSettings, targetConfig, pluginMetadata)
                        )
                    )
                );
                targetPlugin = ILockToGovernBase(address(ltvPlugin));
            }

            lockManager.setPluginAddress(targetPlugin);
        }

        // The plugin can execute on the DAO
        dao.grant(address(dao), address(targetPlugin), dao.EXECUTE_PERMISSION_ID());

        // The LockManager can manage the plugin
        dao.grant(
            address(targetPlugin),
            address(lockManager),
            LockToApprovePlugin(address(targetPlugin)).LOCK_MANAGER_PERMISSION_ID()
        );

        if (proposers.length > 0) {
            for (uint256 i = 0; i < proposers.length; i++) {
                dao.grant(
                    address(targetPlugin),
                    proposers[i],
                    LockToApprovePlugin(address(targetPlugin)).CREATE_PROPOSAL_PERMISSION_ID()
                );
            }
        } else {
            // Ensure that at least the owner can propose
            dao.grant(
                address(targetPlugin), owner, LockToApprovePlugin(address(targetPlugin)).CREATE_PROPOSAL_PERMISSION_ID()
            );
        }

        // Transfer ownership to the owner
        dao.grant(address(dao), owner, dao.ROOT_PERMISSION_ID());
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(ltaPlugin), "LockToApprove");
        vm.label(address(ltvPlugin), "LockToVote");
        vm.label(address(lockManager), "LockManager");
        vm.label(address(lockableToken), "VotingToken");
        vm.label(address(underlyingToken), "UnderlyingToken");

        // Moving forward to avoid proposal creations failing or getVotes() giving inconsistent values
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
