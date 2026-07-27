#!/bin/sh
# Run CalculiX's own acceptance suite against the binary we just built.
#
#   build/verify.sh                          all 610 decks vs upstream references
#   VERIFY_ONLY='beamp thermo1' build/verify.sh
#   REFERENCE_CCX=/path/to/ccx build/verify.sh
#
# Two different questions are answered here, and they are not the same one:
#
#   1. Is the build correct?   Compare our .dat/.frd against the reference
#      results upstream ships, using upstream's own tolerance checkers.
#   2. Did the numbers move?   With REFERENCE_CCX set, run the same decks
#      through the binary the engineer has today and compare against THAT.
#      This is the question the local-fallback promise actually rests on, and
#      no amount of agreement with a 2024 reference file answers it.
set -e

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$BUILD_DIR/.." && pwd)
WORK="${WORK:-$REPO_ROOT/.build}"
export BUILD_DIR REPO_ROOT WORK

. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

detect_platform

TEST_URL=http://www.dhondt.de/ccx_$CCX_VERSION.test.tar.bz2
TEST_SHA256=804c1ab099f5694b67955ddd72ad4708061019298c5d1d1788bf404d900b86fc

CCX_BIN="${CCX_BIN:-$WORK/out/ccx}"
case "$PLATFORM" in win-x64) CCX_BIN="${CCX_BIN:-$WORK/out/ccx.exe}" ;; esac
[ -x "$CCX_BIN" ] || die "no executable to verify at $CCX_BIN"

need perl

mkdir -p "$WORK/deps"
fetch_verify "$TEST_URL" "$TEST_SHA256" "$WORK/deps/ccx-test.tar.bz2"

SUITE="$WORK/test/CalculiX/ccx_$CCX_VERSION/test"
if [ ! -d "$SUITE" ] || [ "${FORCE:-0}" = "1" ]; then
    rm -rf "$WORK/test"
    mkdir -p "$WORK/test"
    tar xjf "$WORK/deps/ccx-test.tar.bz2" -C "$WORK/test"
fi
[ -d "$SUITE" ] || die "test suite did not unpack where expected: $SUITE"

# The suite writes beside its inputs, so give each run its own copy — that is
# also what lets us run ours and the reference binary over the same decks
# without either seeing the other's leftovers.
run_suite() {
    _bin="$1"; _dir="$2"
    rm -rf "$_dir"
    mkdir -p "$_dir"
    cp "$SUITE"/* "$_dir"/
    ( cd "$_dir"
      OMP_NUM_THREADS=1
      export OMP_NUM_THREADS
      for f in *.inp; do
          _job=${f%.inp}
          case "$_job" in
              # Written by other examples during the run, not inputs.
              circ10pcent.rfn|circ10p.rfn|segmentsmooth.rfn|segmentsmooth2.rfn) continue ;;
          esac
          if [ -n "${VERIFY_ONLY:-}" ]; then
              case " $VERIFY_ONLY " in *" $_job "*) ;; *) continue ;; esac
          fi
          "$_bin" "$_job" > "$_job.log" 2>&1 || true
      done )
}

log "running the suite with the build under test"
run_suite "$CCX_BIN" "$WORK/verify/ours"

FAILED=0
REPORT="$WORK/verify/report.txt"
mkdir -p "$WORK/verify"
: > "$REPORT"

log "comparing against the reference results shipped with $CCX_VERSION"
( cd "$WORK/verify/ours"
  for f in *.inp; do
      _job=${f%.inp}
      [ -f "$_job.dat.ref" ] || continue
      if [ -n "${VERIFY_ONLY:-}" ]; then
          case " $VERIFY_ONLY " in *" $_job "*) ;; *) continue ;; esac
      fi
      if [ ! -f "$_job.dat" ]; then
          echo "MISSING  $_job.dat was not produced"
          continue
      fi
      # datcheck.pl is upstream's own tolerance comparison; it prints only on
      # disagreement, which is what makes an empty report meaningful.
      perl ./datcheck.pl "$_job" 2>&1 || true
  done ) >> "$REPORT"

if [ -n "${REFERENCE_CCX:-}" ]; then
    [ -x "$REFERENCE_CCX" ] || die "REFERENCE_CCX is not executable: $REFERENCE_CCX"
    log "running the same decks with the reference binary"
    run_suite "$REFERENCE_CCX" "$WORK/verify/reference"

    log "comparing our results against the reference binary's, deck by deck"
    ( cd "$WORK/verify/ours"
      for f in *.inp; do
          _job=${f%.inp}
          if [ -n "${VERIFY_ONLY:-}" ]; then
              case " $VERIFY_ONLY " in *" $_job "*) ;; *) continue ;; esac
          fi
          _theirs="$WORK/verify/reference/$_job.dat"
          [ -f "$_theirs" ] || continue
          [ -f "$_job.dat" ] || { echo "DRIFT    $_job: we produced no .dat, the reference did"; continue; }
          cp "$_theirs" "$_job.dat.ref"
          perl ./datcheck.pl "$_job" 2>&1 || true
      done ) >> "$REPORT"
fi

if [ -s "$REPORT" ]; then
    FAILED=1
    warn "differences reported:"
    cat "$REPORT"
else
    log "no differences — every deck agreed within upstream's tolerances"
fi

exit $FAILED
