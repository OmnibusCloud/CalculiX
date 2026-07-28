#!/bin/sh
# Compare two result sets produced by different platform builds.
#
#   build/cross-platform.sh <reference-dir> <candidate-dir> <label>
#
# Correctness and agreement are different questions, and this script answers
# only the second. Whether a build is right is settled against upstream's
# published results (phase A in verify.sh). Whether two builds of ours give the
# same answer is settled here — and for WitSweep that is the load-bearing one,
# because a sweep's output IS the difference between variants. If variant 3 ran
# on a Windows node and variant 4 on a Linux node, any disagreement between the
# two builds lands in the response table and is indistinguishable from physics.
#
# The chain that makes this honest: the Windows build is anchored to upstream's
# published results and to the binary PrePoMax ships, so anchoring the other
# platforms to Windows anchors them to both, one link further out.
set -e

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$BUILD_DIR/.." && pwd)
WORK="${WORK:-$REPO_ROOT/.build}"
export BUILD_DIR REPO_ROOT WORK

. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

REFERENCE="$1"
CANDIDATE="$2"
LABEL="${3:-candidate}"

[ -d "$REFERENCE" ] || die "reference result directory not found: $REFERENCE"
[ -d "$CANDIDATE" ] || die "candidate result directory not found: $CANDIDATE"

need perl

# datcheck.pl is upstream's tolerance comparison and lives in the test suite,
# so the suite is fetched even though nothing is solved here.
TEST_URL=http://www.dhondt.de/ccx_$CCX_VERSION.test.tar.bz2
TEST_SHA256=804c1ab099f5694b67955ddd72ad4708061019298c5d1d1788bf404d900b86fc

mkdir -p "$WORK/deps"
fetch_verify "$TEST_URL" "$TEST_SHA256" "$WORK/deps/ccx-test.tar.bz2"

SUITE="$WORK/test/CalculiX/ccx_$CCX_VERSION/test"
if [ ! -f "$SUITE/datcheck.pl" ]; then
    rm -rf "$WORK/test"
    mkdir -p "$WORK/test"
    tar xjf "$WORK/deps/ccx-test.tar.bz2" -C "$WORK/test"
fi
[ -f "$SUITE/datcheck.pl" ] || die "the test suite did not unpack where expected: $SUITE"

DIR="$WORK/cross/$LABEL"
rm -rf "$DIR"; mkdir -p "$DIR"
cp "$SUITE/datcheck.pl" "$DIR/"

COMPARED=0
MISSING=0
for f in "$CANDIDATE"/*.dat; do
    [ -e "$f" ] || continue
    job=$(basename "$f" .dat)
    if [ ! -f "$REFERENCE/$job.dat" ]; then
        MISSING=$((MISSING + 1))
        continue
    fi
    cp "$f" "$DIR/$job.dat"
    cp "$REFERENCE/$job.dat" "$DIR/$job.dat.ref"
    COMPARED=$((COMPARED + 1))
done

# A deck the reference produced and the candidate did not is a difference of a
# different kind, and the tolerance checker cannot see it — it compares what
# exists on both sides.
ONLY_REFERENCE=0
for f in "$REFERENCE"/*.dat; do
    [ -e "$f" ] || continue
    job=$(basename "$f" .dat)
    [ -f "$CANDIDATE/$job.dat" ] && continue
    ONLY_REFERENCE=$((ONLY_REFERENCE + 1))
    echo "MISSING  $job: the reference platform produced a result and $LABEL did not"
done

log "comparing $LABEL against the reference platform over $COMPARED decks"
[ "$MISSING" -gt 0 ] && warn "$MISSING deck(s) exist only for $LABEL"
[ "$ONLY_REFERENCE" -gt 0 ] && warn "$ONLY_REFERENCE deck(s) exist only for the reference platform"

REPORT="$WORK/cross/$LABEL.txt"
( cd "$DIR" && for f in *.dat; do
    case "$f" in *.dat.ref) continue ;; esac
    perl ./datcheck.pl "${f%.dat}" 2>&1 || true
  done ) > "$REPORT"

DEVIATIONS=$(grep -c '^deviation in file' "$REPORT" 2>/dev/null || echo 0)

echo
echo "===== $LABEL vs the reference platform ====="
echo "decks compared:  $COMPARED"
echo "decks deviating: $DEVIATIONS"
if [ "$DEVIATIONS" -gt 0 ]; then
    echo
    grep '^deviation in file' "$REPORT" | sed 's/^/  /'
    echo
    echo "Full detail in $REPORT"
fi

# Deviations are reported, not failed on. Two honest builds of the same source
# genuinely disagree on ill-conditioned decks — contact and complex
# eigenvalues — and a hard gate here would either be set so loose it proves
# nothing or so tight it blocks on physics. The number is the deliverable; what
# tolerance a product promises on top of it is a separate decision.
exit 0
