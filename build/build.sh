#!/bin/sh
# Build CalculiX for the host platform.
#
#   build/build.sh
#   WITH_PASTIX=1 build/build.sh
#   FORCE=1 build/build.sh          rebuild dependencies too
#
# Everything lands in .build/ (gitignored); the distributable kit is in
# .build/out.
set -e

BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$BUILD_DIR/.." && pwd)
WORK="${WORK:-$REPO_ROOT/.build}"
export BUILD_DIR REPO_ROOT WORK

. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

need curl
need make
need tar

detect_platform
configure_features
export PLATFORM WITH_PARDISO WITH_PASTIX WITH_ARPACK WITH_MT

log "CalculiX $CCX_VERSION for $PLATFORM"
log "  SPOOLES  yes$([ "$WITH_MT" = 1 ] && echo ' (multithreaded)')"
log "  ARPACK   $([ "$WITH_ARPACK" = 1 ] && echo yes || echo no)"
log "  PARDISO  $([ "$WITH_PARDISO" = 1 ] && echo yes || echo no)"
log "  PaStiX   $([ "$WITH_PASTIX" = 1 ] && echo yes || echo no)"

mkdir -p "$WORK/deps"

# oneMKL first: arpack-ng links against it for BLAS/LAPACK, so its paths have
# to exist before that build is configured.
. "$BUILD_DIR/mkl.sh"

sh "$BUILD_DIR/spooles.sh"

if [ "$WITH_ARPACK" = "1" ]; then
    sh "$BUILD_DIR/arpack.sh"
fi

if [ "$WITH_PASTIX" = "1" ]; then
    sh "$BUILD_DIR/pastix.sh"
fi

sh "$BUILD_DIR/ccx.sh"

log "done"
