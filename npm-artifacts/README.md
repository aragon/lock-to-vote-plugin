# Lock to Vote plugin artifacts

This package contains the ABI of the Lock to Vote plugin for OSx, as well as the address of its plugin repository on each supported network. Install it with:

```sh
yarn add @aragon/lock-to-vote-plugin-artifacts
```

## Usage

```typescript
// ABI definitions
import {
  LockToVotePluginABI,
  LockManagerERC20ABI,
  MinVotingPowerConditionABI,
  LockToVotePluginSetupABI
} from "@aragon/lock-to-vote-plugin-artifacts";

// Plugin Repository addresses per-network
import { addresses } from "@aragon/lock-to-vote-plugin-artifacts";
```

You can also open [addresses.json](https://github.com/aragon/lock-to-vote-plugin/blob/main/npm-artifacts/src/addresses.json) directly.

## Development

### Building the package

Install the dependencies and generate the local ABI definitions.

```sh
yarn --ignore-scripts
yarn build
```

The `build` script will:
1. Move to `src`.
2. Install its dependencies.
3. Compile the contracts using Hardhat.
4. Generate their ABI.
5. Extract their ABI and embed it into on `npm-artifacts/src/abi.ts`.

### Publishing

- Access the repo's GitHub Actions panel
- Click on "Publish Artifacts"
- Select the corresponding `release-v*` branch as the source

This action will:
- Create a git tag like `v1.2`, following [package.json](./package.json)'s version field
- Publish the package to NPM

## Security

If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the issue tracker for security issues.
