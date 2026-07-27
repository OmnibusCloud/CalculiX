#!/bin/sh
# Build arpack-ng statically into $WORK/arpack/lib/libarpack.a
#
# CalculiX's own Makefile expects the historical Rice ARPACK, whose library
# carried its own BLAS/LAPACK subset. arpack-ng does not: it links an external
# one. We give it the BLAS that platform already has for another reason —
# oneMKL where PARDISO is linked anyway, Accelerate on macOS — so that a build
# never ends up with two competing BLAS implementations in one process.
set -e

. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

ARPACK_PREFIX="$WORK/arpack"

if [ -f "$ARPACK_PREFIX/lib/libarpack.a" ] && [ "${FORCE:-0}" != "1" ]; then
    log "arpack-ng already built"
    exit 0
fi

need cmake
fetch_verify "$ARPACK_URL" "$ARPACK_SHA256" "$WORK/deps/arpack-ng-$ARPACK_VERSION.tar.gz"

rm -rf "$WORK/arpack-src" "$ARPACK_PREFIX"
mkdir -p "$WORK/arpack-src"
tar xzf "$WORK/deps/arpack-ng-$ARPACK_VERSION.tar.gz" -C "$WORK/arpack-src" --strip-components=1

BLA_ARGS=""
case "$PLATFORM" in
    macos-*)
        BLA_ARGS="-DBLA_VENDOR=Apple"
        ;;
    *)
        if [ "$WITH_PARDISO" = "1" ]; then
            BLA_ARGS="-DBLAS_LIBRARIES=$MKL_LINK_LIB -DLAPACK_LIBRARIES=$MKL_LINK_LIB"
        else
            warn "no oneMKL in this configuration — arpack-ng will use whatever BLAS cmake finds"
        fi
        ;;
esac

log "configuring arpack-ng $ARPACK_VERSION"
# shellcheck disable=SC2086
cmake -S "$WORK/arpack-src" -B "$WORK/arpack-build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$ARPACK_PREFIX" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DEXAMPLES=OFF \
    -DTESTS=OFF \
    -DMPI=OFF \
    -DICB=OFF \
    $BLA_ARGS \
    ${CMAKE_EXTRA_ARGS:-}

log "building arpack-ng"
cmake --build "$WORK/arpack-build" --parallel "$(cpu_count)"
cmake --install "$WORK/arpack-build"

[ -f "$ARPACK_PREFIX/lib/libarpack.a" ] || die "arpack-ng built without producing libarpack.a"

# CalculiX calls exactly these; a library missing them links and then fails at
# the first *FREQUENCY step, which is the worst place to find out.
for sym in dsaupd_ dseupd_; do
    nm "$ARPACK_PREFIX/lib/libarpack.a" 2>/dev/null | grep -q "T $sym\|T _$sym" \
        || die "arpack-ng does not export $sym"
done

log "arpack-ng ready: $ARPACK_PREFIX/lib/libarpack.a"
