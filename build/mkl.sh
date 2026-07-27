#!/bin/sh
# Stage Intel oneMKL 2022.2.1 into $WORK/mkl, and export:
#   MKL_LINK_LIB      what to put on the link line for PARDISO (and BLAS)
#   MKL_RUNTIME_DIR   the DLLs/shared objects that must ship beside ccx
#
# Intel publishes oneMKL as Python wheels. That is the smallest pinnable form
# of exactly the version PrePoMax ships — the alternative, an oneAPI installer,
# is gigabytes and not addressable by checksum. The wheels are ordinary zip
# archives; nothing Python is used at build or run time.
set -e

. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

MKL_PREFIX="$WORK/mkl"

if [ "$WITH_PARDISO" != "1" ]; then
    log "PARDISO disabled on $PLATFORM — skipping oneMKL"
    return 0 2>/dev/null || exit 0
fi

# PyPI files are immutable per version, so a pinned URL plus its digest is a
# genuine pin and not a moving target.
case "$PLATFORM" in
    win-x64)
        MKL_RT_URL=https://files.pythonhosted.org/packages/8e/80/ad5fb0f2c9880c3d2b8df3ac508021cf5eb3a6909b250250430e66557bbd/mkl-2022.2.1-py2.py3-none-win_amd64.whl
        MKL_RT_SHA256=67f6ed435c2fd6b526d0d360259fa2be9453365ecde75f589db61c3624ef1cd8
        MKL_DEV_URL=https://files.pythonhosted.org/packages/fe/9b/e015037b87aab87eefe83f59303881be47f53c0aa389a10fe39767b35fe2/mkl_devel-2022.2.1-py2.py3-none-win_amd64.whl
        MKL_DEV_SHA256=7a000cf0d680cc6acd3c513949d2e8c50aa34cf2b618e7235f98ec1b2b9b3b09
        MKL_INC_URL=https://files.pythonhosted.org/packages/f5/97/6ab9983c7e468d0a4f58189c8d63719a25c08c9579cde170095f00d05480/mkl_include-2022.2.1-py2.py3-none-win_amd64.whl
        MKL_INC_SHA256=460874c6e4b7ce5e569fe0ec846ec4de282fc1a9556215201d57ee10c7cfbdd6
        ;;
    linux-x64)
        MKL_RT_URL=https://files.pythonhosted.org/packages/3c/13/8445ec0b958830f2342280193fd9271c261db9bbdb2f07e418dfe649ca1e/mkl-2022.2.1-py2.py3-none-manylinux1_x86_64.whl
        MKL_RT_SHA256=0cf6cbb639bc4ecf3b77e5337d4ceb2e24ef025043f764e2abcc32f6797a7138
        MKL_DEV_URL=
        MKL_INC_URL=https://files.pythonhosted.org/packages/a8/28/ee11a9b8f36dba4703dafda79ba463f9118e9f6bbea1b3258a3d9ea48c39/mkl_include-2022.2.1-py2.py3-none-manylinux1_x86_64.whl
        MKL_INC_SHA256=1af7c95646c58ce269e252cd52a2e36118d1c0df4a58fd3229297fbf11b653d1
        ;;
    *)
        die "no oneMKL pins for $PLATFORM"
        ;;
esac

if [ ! -d "$MKL_PREFIX" ] || [ "${FORCE:-0}" = "1" ]; then
    rm -rf "$MKL_PREFIX"
    mkdir -p "$MKL_PREFIX"
    need unzip

    fetch_verify "$MKL_RT_URL" "$MKL_RT_SHA256" "$WORK/deps/mkl-runtime.whl"
    unzip -q -o "$WORK/deps/mkl-runtime.whl" -d "$MKL_PREFIX/runtime"

    fetch_verify "$MKL_INC_URL" "$MKL_INC_SHA256" "$WORK/deps/mkl-include.whl"
    unzip -q -o "$WORK/deps/mkl-include.whl" -d "$MKL_PREFIX/include-pkg"

    if [ -n "$MKL_DEV_URL" ]; then
        fetch_verify "$MKL_DEV_URL" "$MKL_DEV_SHA256" "$WORK/deps/mkl-devel.whl"
        unzip -q -o "$WORK/deps/mkl-devel.whl" -d "$MKL_PREFIX/devel"
    fi
fi

# The wheels bury everything under a `<name>.data/data/` prefix whose exact
# shape differs between the Windows and Linux builds, so locate rather than
# assume.
find_one() {
    _hit=$(find "$1" -name "$2" -print 2>/dev/null | head -1)
    [ -n "$_hit" ] || die "could not find $2 under $1 — oneMKL wheel layout changed"
    echo "$_hit"
}

MKL_INCLUDE_DIR=$(dirname "$(find_one "$MKL_PREFIX/include-pkg" 'mkl.h')")

case "$PLATFORM" in
    win-x64)
        MKL_RT_DLL=$(find_one "$MKL_PREFIX/runtime" 'mkl_rt.2.dll')
        MKL_RUNTIME_DIR=$(dirname "$MKL_RT_DLL")
        # MinGW's linker takes a DLL directly and derives the import stubs, so
        # the MSVC import library is not needed. Keep the DLL path absolute:
        # it also becomes what we copy next to the executable.
        MKL_LINK_LIB="$MKL_RT_DLL"
        ;;
    linux-x64)
        MKL_RT_SO=$(find_one "$MKL_PREFIX/runtime" 'libmkl_rt.so.2')
        MKL_RUNTIME_DIR=$(dirname "$MKL_RT_SO")
        # `-lmkl_rt` needs the unversioned name to resolve at link time.
        [ -e "$MKL_RUNTIME_DIR/libmkl_rt.so" ] || ln -s libmkl_rt.so.2 "$MKL_RUNTIME_DIR/libmkl_rt.so"
        MKL_LINK_LIB="-L$MKL_RUNTIME_DIR -lmkl_rt"
        ;;
esac

export MKL_INCLUDE_DIR MKL_RUNTIME_DIR MKL_LINK_LIB

log "oneMKL $MKL_VERSION staged"
log "  link:    $MKL_LINK_LIB"
log "  runtime: $MKL_RUNTIME_DIR"
