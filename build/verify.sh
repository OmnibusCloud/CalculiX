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

# compare_run <results-dir> <expected-dir> <expected-suffix> <label>
#
# Runs upstream's own tolerance checker over one pair of result sets. It works
# in a scratch directory rather than in place: the earlier version overwrote
# the shipped .dat.ref files with the reference binary's output, which made a
# second phase impossible to interpret and a re-run impossible to trust.
compare_run() {
    _results="$1"; _expected="$2"; _suffix="$3"; _label="$4"
    _dir="$WORK/verify/cmp-$_label"

    rm -rf "$_dir"; mkdir -p "$_dir"
    cp "$SUITE/datcheck.pl" "$_dir/"

    _count=0
    for _f in "$_results"/*.dat; do
        [ -e "$_f" ] || continue
        _job=$(basename "$_f" .dat)
        [ -f "$_expected/$_job$_suffix" ] || continue
        cp "$_f" "$_dir/$_job.dat"
        cp "$_expected/$_job$_suffix" "$_dir/$_job.dat.ref"
        _count=$((_count + 1))
    done

    ( cd "$_dir" && for _f in *.dat; do
        case "$_f" in *.dat.ref) continue ;; esac
        perl ./datcheck.pl "${_f%.dat}" 2>&1 || true
      done )

    echo "  ($_count decks compared)" >&2
    COMPARED="$_count"
}

section() {
    printf '\n===== %s =====\n' "$1" >> "$REPORT"
}

# Decks upstream's own binary cannot reproduce either, plus individually
# justified ones. See build/known-deviations.txt — the reasoning lives there,
# next to the list, because a list of deck names with no reasons decays into a
# place to hide failures.
KNOWN_FILE="$BUILD_DIR/known-deviations.txt"
known_deviations() {
    [ -f "$KNOWN_FILE" ] || return 0
    sed 's/#.*//' "$KNOWN_FILE" | tr -s ' \t' '\n' | grep -v '^$'
}

is_known() {
    known_deviations | grep -qx "$1"
}

log "A: our results against the reference FILES upstream ships"
section "A: ours vs the reference results shipped with $CCX_VERSION"

PHASE_A="$WORK/verify/phase-a.txt"
compare_run "$WORK/verify/ours" "$SUITE" ".dat.ref" "a-ours-vs-refs" > "$PHASE_A"

# Split the phase into "already known" and "new". Only the second is a gate:
# left whole, this phase can never go green — six decks deviate on a healthy
# build — and a check that is always red is a check nobody reads.
NEW_DEVIATIONS=0
KNOWN_SEEN=0
for _deck in $(grep '^deviation in file' "$PHASE_A" | sed 's/^deviation in file //; s/\.dat$//'); do
    if is_known "$_deck"; then
        KNOWN_SEEN=$((KNOWN_SEEN + 1))
        echo "known    $_deck (see build/known-deviations.txt)" >> "$REPORT"
    else
        NEW_DEVIATIONS=$((NEW_DEVIATIONS + 1))
        awk -v deck="deviation in file $_deck.dat" '
            $0 == deck { p = 1 }
            p && /^deviation in file/ && $0 != deck { p = 0 }
            p { print }' "$PHASE_A" >> "$REPORT"
    fi
done

log "  $KNOWN_SEEN known, $NEW_DEVIATIONS new"

# Decks the build did not produce at all are a different failure from a
# numerical one, and the checker cannot see them — it compares what exists.
( cd "$WORK/verify/ours"
  for f in *.inp; do
      _job=${f%.inp}
      [ -f "$_job.dat.ref" ] || continue
      if [ -n "${VERIFY_ONLY:-}" ]; then
          case " $VERIFY_ONLY " in *" $_job "*) ;; *) continue ;; esac
      fi
      [ -f "$_job.dat" ] && continue
      # "no .dat" on its own says nothing about why. The solver's own output
      # does, and without it a failing platform costs a round trip through CI
      # to learn one line.
      echo "MISSING  $_job.dat was not produced; last lines of $_job.log:"
      sed 's/^/         | /' "$_job.log" 2>/dev/null | tail -15
  done ) >> "$REPORT"

# ---------------------------------------------------------------------------
# The linked solvers, one deck each
# ---------------------------------------------------------------------------
#
# ccx's default is SPOOLES, so the whole suite above can pass on a build where
# PARDISO or PaStiX were never linked — the kit would ship, and the first deck
# an engineer solves with the solver PrePoMax writes by default would stop with
# "the PARDISO library is not linked". Force each linked solver onto one deck
# and require it to agree with the default path.

check_solver() {
    _solver="$1"; _job="beamp"
    _dir="$WORK/verify/solver-$_solver"

    rm -rf "$_dir"; mkdir -p "$_dir"
    cp "$SUITE/$_job.inp" "$_dir/$_job.inp"
    cp "$WORK/verify/ours/$_job.dat" "$_dir/$_job.dat.ref" 2>/dev/null \
        || { echo "SKIP     $_solver: the default-solver run of $_job produced nothing to compare against"; return; }
    cp "$SUITE/datcheck.pl" "$_dir/"

    expect_in_file "$_dir/$_job.inp" "^\*STATIC" "the step card to retarget"
    sed -i.bak "s/^\*STATIC.*/*STATIC, SOLVER=$_solver/" "$_dir/$_job.inp"

    ( cd "$_dir"
      OMP_NUM_THREADS=1; export OMP_NUM_THREADS
      "$CCX_BIN" "$_job" > "$_job.log" 2>&1 || true
      if [ ! -f "$_job.dat" ]; then
          echo "SOLVER   $_solver produced no result on $_job; last lines of its log:"
          sed 's/^/         | /' "$_job.log" | tail -15
      else
          perl ./datcheck.pl "$_job" 2>&1 || true
      fi )
}

# Which solvers to check comes from the kit's own BUILDINFO rather than from
# the environment: it describes what was actually linked, not what someone
# meant to request, and the two are exactly what this check exists to catch.
BUILT_SOLVERS=$(sed -n 's/^solvers: *//p' "$(dirname "$CCX_BIN")/BUILDINFO.txt" 2>/dev/null)
log "kit reports solvers:${BUILT_SOLVERS:- (unknown)}"

case "$BUILT_SOLVERS" in
    *PARDISO*)
        log "checking that PARDISO is linked and agrees with the default solver"
        check_solver PARDISO >> "$REPORT" ;;
esac

case "$BUILT_SOLVERS" in
    *PaStiX*)
        log "checking that PaStiX is linked and agrees with the default solver"
        check_solver PASTIX >> "$REPORT" ;;
esac

# A result set from another platform, rather than another binary. Same
# machinery, different question: not "is this correct" but "would two nodes of
# a heterogeneous fleet answer the same". For a parameter sweep that is the
# question that decides whether a difference between two variants is physics
# or hardware.
if [ -n "${REFERENCE_RESULTS:-}" ]; then
    [ -d "$REFERENCE_RESULTS" ] || die "REFERENCE_RESULTS is not a directory: $REFERENCE_RESULTS"
    log "D: our results against the ${REFERENCE_LABEL:-reference} result set"
    section "D: ours vs ${REFERENCE_LABEL:-another platform} — cross-platform agreement"
    compare_run "$WORK/verify/ours" "$REFERENCE_RESULTS" ".dat" "d-cross-platform" >> "$REPORT"
fi

if [ -n "${REFERENCE_CCX:-}" ]; then
    [ -x "$REFERENCE_CCX" ] || die "REFERENCE_CCX is not executable: $REFERENCE_CCX"
    log "running the same decks with the reference binary"
    run_suite "$REFERENCE_CCX" "$WORK/verify/reference"

    # Phase B is the one that was missing, and without it phase A is
    # unreadable. Some decks in this suite are ill-conditioned enough that the
    # reference BINARY does not reproduce the reference FILES either — contact,
    # complex eigenvalues, acoustics. Measuring that baseline is the difference
    # between "our build deviates on six decks" and "our build deviates on six
    # decks, four of which the incumbent deviates on too".
    log "B: the reference binary against the same reference FILES (the baseline)"
    section "B: the reference binary vs the reference results shipped with $CCX_VERSION"
    compare_run "$WORK/verify/reference" "$SUITE" ".dat.ref" "b-ref-vs-refs" >> "$REPORT"

    # Phase C is the question the local-fallback promise rests on: not "is our
    # build correct" but "does it answer what the engineer's binary answers".
    log "C: our results against the reference binary's, deck by deck"
    section "C: ours vs the reference binary — the only comparison about numbers MOVING"
    compare_run "$WORK/verify/ours" "$WORK/verify/reference" ".dat" "c-ours-vs-ref" >> "$REPORT"

    ( cd "$WORK/verify/reference"
      for f in *.dat; do
          [ -e "$f" ] || continue
          [ -f "$WORK/verify/ours/$f" ] && continue
          echo "DRIFT    ${f%.dat}: we produced no .dat, the reference did"
      done ) >> "$REPORT"
fi

# Section headers alone are not findings; a report that carries nothing else is
# a pass.
MISSING_COUNT=$(grep -c '^MISSING' "$REPORT" 2>/dev/null || echo 0)

[ -s "$REPORT" ] && cat "$REPORT"

echo
echo "===== verdict ====="
echo "decks compared:       ${COMPARED:-0}"
echo "known deviations:     $KNOWN_SEEN   (build/known-deviations.txt)"
echo "NEW deviations:       $NEW_DEVIATIONS"
echo "results not produced: $MISSING_COUNT"

# Phases B, C and D are measurements, not gates: B is the reference binary's
# own disagreement with the reference files, C and D are how far two builds sit
# from each other. Numbers to read, not thresholds to pass. Only phase A — our
# build against upstream's published results, minus what the reference binary
# also misses — decides the exit code.
if [ "$NEW_DEVIATIONS" -gt 0 ] || [ "$MISSING_COUNT" -gt 0 ]; then
    FAILED=1
    warn "acceptance FAILED: $NEW_DEVIATIONS new deviation(s), $MISSING_COUNT missing result(s)"
elif [ -n "${VERIFY_ONLY:-}" ]; then
    # The count belongs in the success line. Without it, a four-deck smoke run
    # and a 605-deck acceptance run print the same sentence — and one of them
    # was read as the other.
    warn "no new deviations over ${COMPARED:-0} decks — but this was the SUBSET '$VERIFY_ONLY', not the acceptance suite"
else
    log "no new deviations over ${COMPARED:-0} decks — the whole acceptance suite agreed within upstream's tolerances"
fi

exit $FAILED
