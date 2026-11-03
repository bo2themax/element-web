#!/bin/bash
#
# Build a local macOS release of Element Desktop (ad-hoc signed, not notarised).
# Produces apps/desktop/dist/Element-<version>-arm64.dmg and -arm64-mac.zip.
#
# Usage: apps/desktop/scripts/build-release-mac.sh [--skip-install] [--skip-web]
#   --skip-install  don't run pnpm install
#   --skip-web      reuse the existing apps/web/webapp bundle instead of rebuilding it

set -euo pipefail

SKIP_INSTALL=0
SKIP_WEB=0
for arg in "$@"; do
    case "$arg" in
        --skip-install) SKIP_INSTALL=1 ;;
        --skip-web) SKIP_WEB=1 ;;
        -h|--help) sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WEB="$ROOT/apps/web"
DESKTOP="$ROOT/apps/desktop"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [ "$SKIP_INSTALL" = 0 ]; then
    step "Installing dependencies"
    # Scripts must run: the git-hosted @element-hq/element-call-component builds its dist in `prepare`.
    (cd "$ROOT" && pnpm install --frozen-lockfile)
fi

# An install with --ignore-scripts leaves the Element Call component without its dist, which only surfaces
# later as an ENOENT from the web build's webpack config.
EC_DIR="$WEB/node_modules/@element-hq/element-call-component"
if [ ! -d "$EC_DIR/dist" ]; then
    echo "@element-hq/element-call-component has no dist/ ($EC_DIR)." >&2
    echo "It was probably installed with --ignore-scripts; reinstall it with scripts enabled." >&2
    exit 1
fi

if [ "$SKIP_WEB" = 0 ]; then
    step "Building web app"
    # Start clean so stale hashed bundles don't pile up in the asar.
    (cd "$WEB" && rm -rf webapp && pnpm build)
fi

if [ ! -d "$WEB/webapp" ]; then
    echo "No web bundle at $WEB/webapp; run without --skip-web." >&2
    exit 1
fi

step "Packing webapp.asar"
(cd "$DESKTOP" && rsync -a --delete "$WEB/webapp/" webapp/ && rm -f webapp.asar && pnpm asar-webapp)

step "Packaging desktop app"
# Skip the nx cache so a cached dist from another build isn't restored instead of a fresh package.
(cd "$DESKTOP" && NX_SKIP_NX_CACHE=true pnpm build)

step "Done"
ls -lh "$DESKTOP"/dist/*.dmg "$DESKTOP"/dist/*.zip 2>/dev/null || ls -lh "$DESKTOP/dist"
