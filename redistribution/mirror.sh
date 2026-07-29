#!/bin/sh
# Mirror everything OmnibusCloud redistributes, or owes as corresponding
# source, into this repository's public mirror release.
#
# Two jobs, and they are the same job:
#
#   1. GPL-2.0 section 3 requires whoever distributes a CalculiX binary to
#      make the corresponding source available to any third party. A link to
#      someone else's web server is not that: it is a promise about a host we
#      do not run. Mirroring it here, publicly and without an account wall, is
#      what actually discharges the obligation.
#
#   2. A release build that downloads from a personal web server fails on the
#      day that server is down. The shim's installer pipeline pulls the ccx
#      kit from this mirror for exactly that reason.
#
# Nothing here is taken on trust: every artefact is verified against the pin
# recorded in MIRROR.md before it is written, whether it came from upstream or
# from a cache. A checksum mismatch stops the script — it is never a reason to
# edit the pin. If upstream re-rolls an archive under the same name, that is a
# fact to investigate and record, not a build to unblock.
#
# Usage:
#   ./redistribution/mirror.sh              fetch and verify into out/
#   ./redistribution/mirror.sh --upload     ... and publish the release
#
# --upload needs `gh` authenticated with write access to this repository. It
# never overwrites an asset that is already attached: a published mirror is a
# reference other documents cite by checksum, so it is append-only. A new
# upstream version gets a NEW tag, never a rewritten one.
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_ROOT/build"
. "$BUILD_DIR/lib.sh"

MIRROR_TAG=${MIRROR_TAG:-upstream-mirror-2.22}
OUT=${OUT:-$SCRIPT_DIR/out}

# name | url | sha256
#
# The versions of the linked libraries were established from the redistributed
# binary itself — embedded source paths for arpack-ng and hwloc, the banner it
# prints for PaStiX — and not assumed. See CALCULIX-NOTICE.txt section 2.3 in
# the shim's installer, and MIRROR.md beside this script.
ARTEFACTS="
calculix_2.22_4win.zip|http://www.dhondt.de/calculix_2.22_4win.zip|a1f91281944c96d6cd914cc020421e8ae65973b3e15d055dc63a3e3e3066d281
ccx_2.22.src.tar.bz2|http://www.dhondt.de/ccx_2.22.src.tar.bz2|3a94dcc775a31f570229734b341d6b06301ebdc759863df901c8b9bf1854c0bc
spooles.2.2.tgz|https://netlib.org/linalg/spooles/spooles.2.2.tgz|a84559a0e987a1e423055ef4fdf3035d55b65bbe4bf915efaa1a35bef7f8c5dd
arpack-ng-3.9.1.tar.gz|https://github.com/opencollab/arpack-ng/archive/refs/tags/3.9.1.tar.gz|f6641deb07fa69165b7815de9008af3ea47eb39b2bb97521fbf74c97aba6e844
hwloc-2.11.1.tar.gz|https://download.open-mpi.org/release/hwloc/v2.11/hwloc-2.11.1.tar.gz|9f320925cfd0daeaf3a3d724c93e127ecac63750c623654dca0298504aac4c2c
"

need curl
mkdir -p "$OUT"

log "mirroring into $OUT"
echo "$ARTEFACTS" | while IFS='|' read -r name url sha; do
    [ -n "$name" ] || continue
    fetch_verify "$url" "$sha" "$OUT/$name"
done

# The manifest is generated from the files on disk rather than copied from the
# table above, so it states what is actually there.
( cd "$OUT" && rm -f SHA256SUMS && for f in *; do
    [ "$f" = "SHA256SUMS" ] && continue
    printf '%s  %s\n' "$(sha256_of "$f")" "$f"
  done > SHA256SUMS )

log "manifest:"
cat "$OUT/SHA256SUMS"

[ "$1" = "--upload" ] || {
    log "verified only. Re-run with --upload to publish release $MIRROR_TAG."
    exit 0
}

need gh

if gh release view "$MIRROR_TAG" >/dev/null 2>&1; then
    log "release $MIRROR_TAG exists — adding only assets that are missing"
    existing=$(gh release view "$MIRROR_TAG" --json assets --jq '.assets[].name')
else
    log "creating release $MIRROR_TAG"
    gh release create "$MIRROR_TAG" \
        --title "Upstream mirror — CalculiX 2.22 and its corresponding source" \
        --notes "Verbatim mirror of the upstream archives OmnibusCloud redistributes or owes as corresponding source under GPL-2.0 section 3. Nothing here is modified; see redistribution/MIRROR.md for the checksum of each file and for how each version was established. Append-only: a new upstream version gets a new tag."
    existing=""
fi

for f in "$OUT"/*; do
    base=$(basename "$f")
    if echo "$existing" | grep -qx "$base"; then
        log "already attached, left alone: $base"
        continue
    fi
    log "uploading $base"
    gh release upload "$MIRROR_TAG" "$f"
done

log "mirror published: $(gh release view "$MIRROR_TAG" --json url --jq .url)"
