#!/bin/sh
# Pin the parts of the MSYS2 MinGW-w64 toolchain that decide how fast the
# Windows kit runs. Run inside an MSYS2 MINGW64 shell, before build.sh.
#
# Why this exists: winpthreads 14.x (mingw-w64 14.0.0, r302 and later) turns an
# uncontended pthread mutex lock/unlock into a kernel wait plus a SetEvent. A
# static ccx.exe takes that mutex on every Fortran I/O statement through
# libgfortran, and parsing a deck is hundreds of thousands of those - on the
# reference cube a kit built on winpthreads 14 spent 52% of its single-thread
# time in NtWaitForSingleObject / NtSetEvent and ran 1.8 s where the same
# sources on winpthreads 13.0.0.r488 ran 1.0 s (upstream's own Windows build:
# 0.96 s). The compiler is not the cause: GCC 15.2 on the new runtime is just as
# slow, GCC 16.2 on the old winpthreads is fast, and the CRT / headers version
# makes no difference. Only the two winpthreads packages are pinned; see
# PROVENANCE.md, "winpthreads".
set -e
BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$BUILD_DIR/.." && pwd)
WORK="${WORK:-$REPO_ROOT/.build}"
export BUILD_DIR REPO_ROOT WORK
. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

detect_platform
[ "$PLATFORM" = "win-x64" ] || { log "toolchain pin: nothing to do on $PLATFORM"; exit 0; }
need pacman
need curl

mkdir -p "$WORK/deps"
_pkgs=""
for _entry in $WINPTHREADS_PACKAGES; do
    _name=${_entry%%=*}
    _sha=${_entry#*=}
    _file="$_name-$WINPTHREADS_VERSION-any.pkg.tar.zst"
    fetch_verify "$WINPTHREADS_REPO/$_file" "$_sha" "$WORK/deps/$_file"
    _pkgs="$_pkgs $WORK/deps/$_file"
done

_have=$(pacman -Q mingw-w64-x86_64-winpthreads 2>/dev/null | awk '{print $2}')
if [ "$_have" = "$WINPTHREADS_VERSION" ]; then
    log "winpthreads already at $WINPTHREADS_VERSION"
else
    log "pinning winpthreads $WINPTHREADS_VERSION (installed: ${_have:-none})"
    # -U installs the exact files, downgrading if the repository has moved on.
    pacman -U --noconfirm $_pkgs
fi

for _pkg in mingw-w64-x86_64-winpthreads mingw-w64-x86_64-libwinpthread; do
    _have=$(pacman -Q "$_pkg" 2>/dev/null | awk '{print $2}')
    [ "$_have" = "$WINPTHREADS_VERSION" ] \
        || die "$_pkg is $_have, expected $WINPTHREADS_VERSION - the pin did not take"
done
log "toolchain: $(gcc --version | head -1); $(pacman -Q mingw-w64-x86_64-crt mingw-w64-x86_64-winpthreads | tr '\n' ' ')"
