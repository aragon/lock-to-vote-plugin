# Lock to Vote Plugin

[![Built with Foundry](https://img.shields.io/badge/Built%20with-Foundry-FF6E3D?logo=ethereum)](https://book.getfoundry.sh/)

**A gas-efficient pair of governance plugins, enabling immediate voting through token locking**
Built on Aragon OSx's modular framework, LockToVote and LockToApprove redefine onchain participation by eliminating the need for token snapshots with an [IVotes](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol) compatible token. Any vanilla ERC20 can now be used to participate in DAO governance.

## Two flavours

![Overview](./img/overview.png)

### `LockToVote`

Feature rich voting with configurable modes, built for nuanced governance:
- **3 choices**: Vote Yes/No/Abstain
- **Three voting modes**:
  - **Vote Replacement**: Update your vote option mid-proposal
  - **Early Execution**: Automatically execute proposals when thresholds are mathematically secured
  - **Standard Mode**: Traditional voting with append-only allocations
- **Parameterized thresholds**: Enforce a minimum participation, a certain support threshold, and a certain approval tally

### `LockToApprove`

Simple binary approvals, designed for proposals requiring straightforward consent or veto:
- **Weighted approval**: Token holders lock funds to approve or veto proposals
- **Gas friendly tokens**: Avoids the overhead of tracking past token balances (ideal for ERC20 tokens without `IVotes` support)

## Architecture Overview

### Core Components

1. **LockManager**
   The custodial contract managing token locks and allows token holders to vote in multiple proposals with just a single lock:
   - `lock()` deposits the current ERC20 allowance and gives the user the chance to vote with it
   - `vote()`, `approve()` allow users to use the currently locked balance on a given proposal
   - Locking and voting can be batched via `lockAndApprove()` and `lockAndVote()`
   - It keeps track of the currently active proposals via `proposalCreated()` and `proposalEnded()` hooks, called by the governance plugin
   - `unlock()` clears all the active votes and withdraws the locked funds provided that the plugin's voting mode allows for it

2. **LockToVote**
   Flexible voting plugin:
   - Handles `IMajorityVoting.VoteOption` votes (Yes/No/Abstain)
   - `vote()` allocates the current voting power into the selected voite option
   - `clearApproval()`: Remove the current voting power allocation, provided that vote replacement is allowed
   - `canVote()`

3. **LockToApprove**
   Implements a binary approval logic:
   - `approve()`: Allocate the locked tokens to support the given proposal
   - `clearApproval()`: Remove the current voting power allocation, provided that vote replacement is allowed
   - `canApprove()`

### Proposal Lifecycle

```solidity
uint256 proposalId = lockToVote.createProposal(metadataUri, actions, startDate, endDate, customParams);

// The LockManager can take 0.1 ether from us and lock it
token.approve(address(lockManager), 0.1 ether);

// Lock the available tokens and vote immediately
lockManager.lockAndVote(proposalId, VoteOption.Yes);

// Or lock first and vote later
token.approve(address(lockManager), 0.5 ether);
lockManager.lock();
lockManager.vote(proposalId);

// Deposit more tokens and vote with the total new balance
token.approve(address(lockManager), 5 ether);
lockManager.lockAndVote(proposalId);

// Unlock your tokens (if the plugin is in vote replacement mode or all proposals have ended)
lockManager.unlock();
```

### Locking tokens

Locking tokens or increasing the amount locked can be done at any time. Voting power can only be added to open proposals.

### Unlocking tokens

Requests to unlock funds will only succeed provided that:
- The caller has no voting power allocated to open proposals
- Or the governance plugin is in vote replacement mode

Otherwise the transaction will revert.

## Get Started

To get started, ensure that [Foundry](https://getfoundry.sh/) and [Make](https://www.gnu.org/software/make/) are installed on your computer.

### Using the Makefile

The `Makefile` is the target launcher of the project. It's the recommended way to work with it. It manages the env variables of common tasks and executes only the steps that need to be run.

```
$ make
Available targets:

- make help               Display the available targets

- make init               Check the dependencies and prompt to install if needed
- make clean              Clean the build artifacts

Testing lifecycle:

- make test               Run unit tests, locally
- make test-fork          Run fork tests, using RPC_URL
- make test-coverage      Generate an HTML coverage report under ./report

- make sync-tests         Scaffold or sync test definitions into solidity tests
- make check-tests        Checks if the solidity test files are out of sync
- make test-tree          Generates a markdown file with the test definitions

Deployment targets:

- make predeploy          Simulate a protocol deployment
- make deploy             Deploy the protocol, verify the source code and write to ./artifacts
- make resume             Retry pending deployment transactions, verify the code and write to ./artifacts

Verification:

- make verify-etherscan   Verify the last deployment on an Etherscan (compatible) explorer
- make verify-blockscout  Verify the last deployment on BlockScout
- make verify-sourcify    Verify the last deployment on Sourcify

- make refund             Refund the remaining balance left on the deployment account
```

Initialize the repo:

```sh
cp .env.example .env
make init
```

- It ensures that Foundry is installed
- It runs a first compilation of the project

Next, customize the values of `.env`.

## Testing 🔍

Using `make`:

```
$ make
[...]
Testing lifecycle:

- make test             Run unit tests, locally
- make test-coverage    Generate an HTML coverage report under ./report
```

Run `make test` or `forge test -vvv` to check the logic's accordance to the specs.

### Writing tests

Optionally, tests with hierarchies can be described using yaml files like [MyPlugin.t.yaml](./test/MyPlugin.t.yaml), which will be transformed into solidity files by running `make sync-tests`, thanks to [bulloak](https://github.com/alexfertel/bulloak).

Create a file with `.t.yaml` extension within the `test` folder and describe a hierarchy using the following structure:

```yaml
# MyPlugin.t.yaml

MyPluginTest:
  - given: The caller has no permission
    comment: The caller needs MANAGER_PERMISSION_ID
    and:
      - when: Calling setNumber()
        then:
          - it: Should revert
  - given: The caller has permission
    and:
      - when: Calling setNumber()
        then:
          - it: It should update the stored number
  - when: Calling number()
    then:
      - it: Should return the right value
```

Nodes like `when` and `given` can be nested without limitations.

Then use `make sync-tests` to automatically sync the described branches into solidity test files.

```sh
$ make
Testing lifecycle:
# ...

- make sync-tests         Scaffold or sync test definitions into solidity tests
- make check-tests        Checks if the solidity test files are out of sync
- make test-tree          Generates a markdown file with the test definitions

$ make sync-tests
```

Each yaml file generates (or syncs) a solidity test file with functions ready to be implemented. They also generate a human readable summary in [TESTS.md](./TESTS.md).

### Deployment Checklist

When running a production deployment ceremony, you can use these steps as a reference:

- [ ] I have cloned the official repository on my computer and I have checked out the `main` branch
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment debian:bookworm-slim`
  - [ ] I have run `apt update && apt install -y make curl git vim neovim bc`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash`
  - [ ] I have run `source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `cp .env.example .env`
  - [ ] I have run `make init`
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] The `.env` file contains the correct parameters for the deployment
  - [ ] I have created a new burner wallet with `cast wallet new` and copied the private key to `DEPLOYMENT_PRIVATE_KEY` within `.env`
  - [ ] I have set the correct `RPC_URL` for the network
  - [ ] I have set the correct `CHAIN_ID` for the network
  - [ ] The value of `NETWORK_NAME` is listed within `constants.mk`, at the appropriate place
  - [ ] I have set `ETHERSCAN_API_KEY` or `BLOCKSCOUT_HOST_NAME` (when relevant to the target network)
  - [ ] I have printed the contents of `.env` to the screen
  - [ ] I am the only person of the ceremony that will operate the deployment wallet
- [ ] All the tests run clean (`make test`)
- My computer:
  - [ ] Is running in a safe location and using a trusted network
  - [ ] It exposes no services or ports
    - MacOS: `sudo lsof -iTCP -sTCP:LISTEN -nP`
    - Linux: `netstat -tulpn`
    - Windows: `netstat -nao -p tcp`
  - [ ] The wifi or wired network in use does not expose any ports to a WAN
- [ ] I have run `make predeploy` and the simulation completes with no errors
- [ ] The deployment wallet has sufficient native token for gas
  - At least, 15% more than the amount estimated during the simulation
- [ ] `make test` still runs clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch (`main`) corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last git commit on `main` and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `make deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The factory contract was deployed by the deployment address
- [ ] All the project's smart contracts are correctly verified on the reference block explorer of the target network.
- [ ] The output of the latest `logs/deployment-<network>-<date>.log` file corresponds to the console output
- [ ] A file called `artifacts/deployment-<network>-<timestamp>.json` has been created, and the addresses match those logged to the screen
- [ ] I have uploaded the following files to a shared location:
  - `logs/deployment-<network>.log` (the last one)
  - `artifacts/deployment-<network>-<timestamp>.json`  (the last one)
  - `broadcast/Deploy.s.sol/<chain-id>/run-<timestamp>.json` (the last one, or `run-latest.json`)
- [ ] The rest of members confirm that the values are correct
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `make refund`

This concludes the deployment ceremony.

## Contract source verification

When running a deployment with `make deploy`, Foundry will attempt to verify the contracts on the corresponding block explorer.

If you need to verify on multiple explorers or the automatic verification did not work, you have three `make` targets available:

```
$ make
[...]
Verification:

- make verify-etherscan   Verify the last deployment on an Etherscan (compatible) explorer
- make verify-blockscout  Verify the last deployment on BlockScout
- make verify-sourcify    Verify the last deployment on Sourcify
```

These targets use the last deployment data under `broadcast/Deploy.s.sol/<chain-id>/run-latest.json`.
- Ensure that the required variables are set within the `.env` file.
- Ensure that `NETWORK_NAME` is listed on the right section under `constants.mk`, according to the block explorer that you want to target

This flow will attempt to verify all the contracts in one go, but yo umay still need to issue additional manual verifications, depending on the circumstances.

### Routescan verification (manual)

```sh
$ forge verify-contract <address> <path/to/file.sol>:<contract-name> --verifier-url 'https://api.routescan.io/v2/network/<testnet|mainnet>/evm/<chain-id>/etherscan' --etherscan-api-key "verifyContract" --num-of-optimizations 200 --compiler-version 0.8.28 --constructor-args <args>
```

Where:
- `<address>` is the address of the contract to verify
- `<path/to/file.sol>:<contract-name>` is the path of the source file along with the contract name
- `<testnet|mainnet>` the type of network
- `<chain-id>` the ID of the chain
- `<args>` the constructor arguments
  - Get them with `$(cast abi-encode "constructor(address param1, uint256 param2,...)" param1 param2 ...)`

## Security 🔒

If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the public issue tracker to report security issues.

## Contributing 🤝

Contributions are welcome! Please read our contributing guidelines to get started.

## License 📄

This project is licensed under AGPL-3.0-or-later.
