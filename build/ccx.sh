#!/bin/sh
# Compile CalculiX itself and stage the distributable kit into $WORK/out.
set -e

. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

SRC_IN="$REPO_ROOT/upstream/ccx_$CCX_VERSION/src"
SRC_BUILD="$WORK/ccx-src"
OUT="$WORK/out"

[ -d "$SRC_IN" ] || die "upstream source missing: $SRC_IN"

# Build out of a copy so the imported upstream tree stays pristine — `git
# status` on upstream/ must always be empty, that is what makes it citable as
# the corresponding source.
rm -rf "$SRC_BUILD"
mkdir -p "$SRC_BUILD"
cp -R "$SRC_IN"/. "$SRC_BUILD"/

# Patches, if we ever have any, are applied here and nowhere else.
if [ -d "$REPO_ROOT/patches" ]; then
    for p in "$REPO_ROOT"/patches/*.patch; do
        [ -e "$p" ] || continue
        log "applying patch $(basename "$p")"
        ( cd "$SRC_BUILD" && patch -p1 --forward < "$p" ) || die "patch failed: $p"
    done
fi

# Deliberately NOT running upstream's date.pl: it rewrites the sources to stamp
# a build date into the banner and into every .frd's UCOMPILETIME line, which
# would make each build differ from the last for no benefit. Builds are
# identified by their published checksum instead. See PROVENANCE.md.

cp "$BUILD_DIR/Makefile.ccx" "$SRC_BUILD/Makefile.ccx"

CFLAGS="$(ccx_cflags)"
FFLAGS="$(ccx_fflags)"
MAIN_CFLAGS="$(ccx_main_cflags)"

# SPOOLES is found through a relative path baked into the CFLAGS by upstream
# convention (-I ../SPOOLES.2.2), which is why the build tree puts the two
# trees side by side under $WORK.
[ -d "$WORK/SPOOLES.2.2" ] || die "SPOOLES not built"

LIBS="$WORK/SPOOLES.2.2/spooles.a"
if [ "$WITH_ARPACK"  = "1" ]; then LIBS="$LIBS $WORK/arpack/lib/libarpack.a"; fi
if [ "$WITH_PASTIX"  = "1" ]; then LIBS="$LIBS $PASTIX_LIBS"; fi
if [ "$WITH_PARDISO" = "1" ]; then LIBS="$LIBS $MKL_LINK_LIB"; fi
LIBS="$LIBS -lpthread -lm"

case "$PLATFORM" in
    macos-*)
        LIBS="$LIBS -framework Accelerate"
        ;;
    linux-x64)
        # The oneMKL shared object ships beside the executable, so look there
        # first and do not depend on the machine having MKL installed.
        #
        # $ORIGIN has to survive two expansions to reach the linker intact: the
        # doubled $ gets through make's expansion of a command-line variable,
        # and the single quotes stop the recipe's shell from expanding what is
        # left into nothing. Getting only the first of those right produces a
        # binary that links and then cannot find its own libraries.
        LIBS="$LIBS -Wl,-rpath,'\$\$ORIGIN'"
        ;;
esac

log "building CalculiX $CCX_VERSION for $PLATFORM"
log "  CFLAGS: $CFLAGS"
log "  LIBS:   $LIBS"

CCX_OUTPUT=ccx
case "$PLATFORM" in win-x64) CCX_OUTPUT=ccx.exe ;; esac

( cd "$SRC_BUILD" && make -f Makefile.ccx \
    CCX_VERSION="$CCX_VERSION" \
    CC="${CC:-cc}" FC="${FC:-gfortran}" \
    CFLAGS="$CFLAGS" FFLAGS="$FFLAGS" MAIN_CFLAGS="$MAIN_CFLAGS" \
    LIBS="$LIBS" CCX_OUTPUT="$CCX_OUTPUT" \
    -j "$(cpu_count)" )

[ -f "$SRC_BUILD/$CCX_OUTPUT" ] || die "the build produced no executable"

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$SRC_BUILD/$CCX_OUTPUT" "$OUT/"

if [ "$WITH_PARDISO" = "1" ]; then
    log "staging the oneMKL runtime beside the executable"
    case "$PLATFORM" in
        win-x64)   find "$MKL_RUNTIME_ROOT" -name '*.dll' -exec cp {} "$OUT/" \; ;;
        linux-x64) find "$MKL_RUNTIME_ROOT" -name 'lib*.so*' -exec cp -P {} "$OUT/" \; ;;
    esac

    # A kit that ships oneMKL without its OpenMP runtime links, starts, and
    # then produces nothing.
    case "$PLATFORM" in
        win-x64)   ls "$OUT"/libiomp5md.dll >/dev/null 2>&1 || die "the Intel OpenMP runtime was not staged" ;;
        linux-x64) ls "$OUT"/libiomp5.so >/dev/null 2>&1 || die "the Intel OpenMP runtime was not staged" ;;
    esac
fi

# Cheapest possible proof that the kit is self-contained: start it, from its
# own directory, with nothing else on the library path, and require its own
# output. A binary that links but cannot find its shared libraries fails here,
# at the end of the build, rather than as silent "no result" lines later.
#
# Not by exit code: with no arguments ccx prints its usage and calls the
# Fortran stop routine, which exits 201 — measured against the reference binary
# as well, so 201 is the SUCCESS case here. The banner is the real evidence
# that our code ran at all.
log "checking that the staged executable starts"
_banner=$( cd "$OUT" && ./"$CCX_OUTPUT" 2>"$WORK/start.err" || true )
case "$_banner" in
    *Usage*) log "  starts and reports: $_banner" ;;
    *) die "the staged executable did not run:
$(cat "$WORK/start.err" 2>/dev/null)" ;;
esac

cp "$REPO_ROOT/LICENSE" "$OUT/LICENSE.CalculiX.GPL-2.0.txt"
cp "$REPO_ROOT/PROVENANCE.md" "$OUT/PROVENANCE.md"

{
    echo "CalculiX CrunchiX $CCX_VERSION"
    echo "platform:  $PLATFORM"
    echo "solvers:   SPOOLES$([ "$WITH_MT" = 1 ] && echo ' (multithreaded)')$([ "$WITH_ARPACK" = 1 ] && echo ', ARPACK')$([ "$WITH_PARDISO" = 1 ] && echo ', PARDISO')$([ "$WITH_PASTIX" = 1 ] && echo ', PaStiX')"
    echo "cflags:    $CFLAGS"
    echo "built by:  OmnibusCloud/CalculiX ${GITHUB_SHA:-local}"
    echo
    echo "CalculiX is free software by Guido Dhondt and Klaus Wittig, licensed"
    echo "under the GNU General Public License version 2. It is distributed here"
    echo "unmodified. The complete corresponding source, and the scripts that"
    echo "control its compilation, are at https://github.com/OmnibusCloud/CalculiX"
    echo
    echo "sha256:"
} > "$OUT/BUILDINFO.txt"
( cd "$OUT" && for f in *; do
    [ "$f" = "BUILDINFO.txt" ] && continue
    printf '  %s  %s\n' "$(sha256_of "$f")" "$f"
done ) >> "$OUT/BUILDINFO.txt"

log "kit staged in $OUT"
ls -la "$OUT"
