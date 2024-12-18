// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/src/core/dao/DAO.sol";
import {createProxyAndCall, createSaltedProxyAndCall, predictProxyAddress} from "../../src/util/proxy.sol";
import {ALICE_ADDRESS} from "../constants.sol";
import {LockToVotePlugin} from "../../src/LockToVotePlugin.sol";
import {LockToVoteSettings} from "../../src/interfaces/ILockToVote.sol";
import {LockManager} from "../../src/LockManager.sol";
import {LockManagerSettings, UnlockMode} from "../../src/interfaces/ILockManager.sol";
import {RATIO_BASE} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "../mocks/TestToken.sol";

contract DaoBuilder is Test {
    address immutable DAO_BASE = address(new DAO());
    address immutable LOCK_TO_VOTE_BASE = address(new LockToVotePlugin());

    struct MintEntry {
        address tokenHolder;
        uint256 amount;
    }

    address owner = ALICE_ADDRESS;

    address[] proposers;
    MintEntry[] tokenHolders;

    bool onlyListed = true;
    uint32 minApprovalRatio = 1;
    uint32 minProposalDuration = 10 days;

    function withDaoOwner(address newOwner) public returns (DaoBuilder) {
        owner = newOwner;
        return this;
    }

    function withTokenHolder(address newTokenHolder, uint256 amount) public returns (DaoBuilder) {
        tokenHolders.push(MintEntry({tokenHolder: newTokenHolder, amount: amount}));
        return this;
    }

    function withMinApprovalRatio(uint32 newApprovalRatio) public returns (DaoBuilder) {
        if (newApprovalRatio > RATIO_BASE) revert("Approval ratio above 100%");
        minApprovalRatio = newApprovalRatio;
        return this;
    }

    function withMinDuration(uint32 newMinDuration) public returns (DaoBuilder) {
        minProposalDuration = newMinDuration;
        return this;
    }

    function withProposer(address newProposer) public returns (DaoBuilder) {
        proposers.push(newProposer);
        return this;
    }

    /// @dev Creates a DAO with the given orchestration settings.
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build()
        public
        returns (DAO dao, LockToVotePlugin plugin, LockManager helper, IERC20 lockableToken, IERC20 underlyingToken)
    {
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
        underlyingToken = new TestToken();

        if (tokenHolders.length > 0) {
            for (uint256 i = 0; i < tokenHolders.length; i++) {
                TestToken(address(lockableToken)).mint(tokenHolders[i].tokenHolder, tokenHolders[i].amount);
                TestToken(address(underlyingToken)).mint(address(0x1234), tokenHolders[i].amount * 1000);
            }
        } else {
            TestToken(address(lockableToken)).mint(owner, 10 ether);
            TestToken(address(underlyingToken)).mint(address(0x1234), 10000 ether);
        }

        {
            // Plugin and helper

            helper = new LockManager(dao, LockManagerSettings(UnlockMode.STRICT), lockableToken, underlyingToken);

            LockToVoteSettings memory targetContractSettings =
                LockToVoteSettings({minApprovalRatio: minApprovalRatio, minProposalDuration: minProposalDuration});

            IPlugin.TargetConfig memory targetConfig =
                IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});
            bytes memory pluginMetadata = "";

            plugin = LockToVotePlugin(
                createProxyAndCall(
                    address(LOCK_TO_VOTE_BASE),
                    abi.encodeCall(
                        LockToVotePlugin.initialize, (dao, helper, targetContractSettings, targetConfig, pluginMetadata)
                    )
                )
            );

            dao.grant(address(helper), address(this), helper.UPDATE_SETTINGS_PERMISSION_ID());
            helper.setPluginAddress(plugin);
            dao.revoke(address(helper), address(this), helper.UPDATE_SETTINGS_PERMISSION_ID());
        }

        // The plugin can execute on the DAO
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

        if (proposers.length > 0) {
            for (uint256 i = 0; i < proposers.length; i++) {
                dao.grant(address(plugin), proposers[i], plugin.CREATE_PROPOSAL_PERMISSION_ID());
            }
        } else {
            // Ensure that at least the owner can propose
            dao.grant(address(plugin), owner, plugin.CREATE_PROPOSAL_PERMISSION_ID());
        }

        // Transfer ownership to the owner
        dao.grant(address(dao), owner, dao.ROOT_PERMISSION_ID());
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "LockToVote plugin");
        vm.label(address(helper), "Lock Manager");
        vm.label(address(lockableToken), "VotingToken");
        vm.label(address(underlyingToken), "Underlying token");

        // Moving forward to avoid proposal creations failing or getVotes() giving inconsistent values
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
