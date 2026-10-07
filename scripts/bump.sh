#!/usr/bin/env bash
# Pin the latest T3 Code nightly: tag, source hash and pnpm deps hash.
# Prints changed=true|false to $GITHUB_OUTPUT when set.
set -euo pipefail
cd "$(dirname "$0")/.."

out() { echo "$1" >> "${GITHUB_OUTPUT:-/dev/null}"; }

current=$(jq -r .tag pins.json)
latest=$(gh api 'repos/pingdotgg/t3code/releases?per_page=30' \
  --jq '[.[] | select(.tag_name | test("-nightly\\."))][0].tag_name')

if [[ "$latest" == "$current" ]]; then
  echo "Already on $current"
  out changed=false
  exit 0
fi
echo "Bumping $current -> $latest"
out "tag=$latest"

src_hash=$(nix flake prefetch --json "github:pingdotgg/t3code/$latest" | jq -r .hash)
fake=sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
jq --arg t "$latest" --arg s "$src_hash" --arg p "$fake" \
  '.tag = $t | .srcHash = $s | .pnpmDepsHash = $p' pins.json > pins.json.tmp
mv pins.json.tmp pins.json

# Fail before the long build if the patches no longer apply.
src=$(nix build --no-link --print-out-paths .#unwrapped.src)
for patch in patches/*.patch; do
  patch --dry-run --quiet -p1 -d "$src" < "$patch" \
    || { echo "::error::$patch does not apply to $latest"; out patch_failed=true; exit 1; }
done

pnpm_hash=$(nix build --no-link .#unwrapped.pnpmDeps 2>&1 | awk '/got:/ {print $2}' || true)
if [[ -z "$pnpm_hash" ]]; then
  echo "::error::could not determine pnpmDeps hash"
  exit 1
fi
jq --arg p "$pnpm_hash" '.pnpmDepsHash = $p' pins.json > pins.json.tmp
mv pins.json.tmp pins.json
out changed=true
