default: help
import 'lib/just-foundry/justfile'

DEPLOY_SCRIPT := "script/DeployNewPluginRepo.s.sol:DeployNewPluginRepoScript"

# Fetch submodules, scaffold .env and select the network (default: mainnet)
[group('setup')]
init network="mainnet":
    #!/usr/bin/env bash
    set -euo pipefail
    git submodule update --init --recursive
    if [ ! -f .env ] && [ -f .env.example ]; then
        cp .env.example .env
        echo "Created .env from .env.example — edit it with your settings."
    fi
    if ! command -v forge &>/dev/null; then
        echo "Error: Foundry is not installed. Run 'just setup' to install it."
        exit 1
    fi
    just switch {{ network }}

# Pin the release & build metadata to IPFS (requires PINATA_JWT)
[group('metadata')]
pin-metadata:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "build-metadata.json   -> $(just ipfs-pin script/metadata/build-metadata.json)"
    echo "release-metadata.json -> $(just ipfs-pin script/metadata/release-metadata.json)"

# Deploy dummy contracts to force source verification on the active network
[group('script')]
deploy-verify *args:
    just run script/ForceVerification.s.sol:ForceVerificationScript {{ args }}

# Regenerate src/lib/PluginUUPSUpgradeable.sol from the current osx submodule (see file header)
[group('develop')]
regenerate-plugin-wrapper:
    #!/usr/bin/env bash
    set -euo pipefail
    SRC="lib/osx/src/common/plugin/PluginUUPSUpgradeable.sol"
    DST="src/lib/PluginUUPSUpgradeable.sol"
    [ -f "$SRC" ] || { echo "Error: $SRC not found. Did you 'git submodule update --init --recursive'?" >&2; exit 1; }
    TMP=$(mktemp)
    trap 'rm -f "$TMP"' EXIT
    awk '/^pragma solidity/{exit} {print}' "$DST" > "$TMP"
    sed \
        -e 's/) public auth(SET_TARGET_CONFIG_PERMISSION_ID) {/) public virtual auth(SET_TARGET_CONFIG_PERMISSION_ID) {/' \
        -e 's|} from "\.\./|} from "@aragon/osx/common/|g' \
        -e 's|} from "\./|} from "@aragon/osx/common/plugin/|g' \
        "$SRC" | awk '/^pragma solidity/{found=1} found{print}' >> "$TMP"
    mv "$TMP" "$DST"
    trap - EXIT
    echo "Regenerated $DST from $SRC"
