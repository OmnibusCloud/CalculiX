# Pins and platform configuration. Sourced, never executed.
#
# Every version here is a decision, not a default. See PROVENANCE.md for how
# the reference configuration was established and why it is matched.

CCX_VERSION=2.22
CCX_SRC_SHA256=3a94dcc775a31f570229734b341d6b06301ebdc759863df901c8b9bf1854c0bc

SPOOLES_URL=https://netlib.org/linalg/spooles/spooles.2.2.tgz
SPOOLES_SHA256=a84559a0e987a1e423055ef4fdf3035d55b65bbe4bf915efaa1a35bef7f8c5dd

ARPACK_VERSION=3.9.1
ARPACK_URL=https://github.com/opencollab/arpack-ng/archive/refs/tags/3.9.1.tar.gz
ARPACK_SHA256=f6641deb07fa69165b7815de9008af3ea47eb39b2bb97521fbf74c97aba6e844

# Matches the runtime PrePoMax 2.5.0 ships, so that a fallback run reproduces
# the engineer's previous local numbers rather than merely resembling them.
MKL_VERSION=2022.2.1

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------

detect_platform() {
    _s=$(uname -s)
    _m=$(uname -m)
    case "$_s" in
        Linux)   PLATFORM=linux-x64 ;;
        Darwin)  case "$_m" in
                     arm64)  PLATFORM=macos-arm64 ;;
                     x86_64) PLATFORM=macos-x64 ;;
                     *) die "unsupported macOS architecture: $_m" ;;
                 esac ;;
        MINGW64*|MSYS_NT*|CYGWIN*) PLATFORM=win-x64 ;;
        *) die "unsupported host: $_s" ;;
    esac
}

# ---------------------------------------------------------------------------
# Feature set
# ---------------------------------------------------------------------------
#
# PARDISO is on wherever Intel oneMKL exists at all, which is x86-64 only.
# On macOS arm64 it is not a choice we are making — there is no such library.
#
# PaStiX is staged: ccx's own default solver is SPOOLES, and PaStiX runs only
# when a deck names it explicitly. It is the most expensive dependency by a
# wide margin (Scotch, hwloc, parsec), so it is built when asked for and the
# build says plainly, in the banner, whether it is in.

configure_features() {
    case "$PLATFORM" in
        macos-arm64)
            : "${WITH_PARDISO:=0}" ;;
        *)
            : "${WITH_PARDISO:=1}" ;;
    esac
    : "${WITH_PASTIX:=0}"
    : "${WITH_ARPACK:=1}"
    : "${WITH_MT:=1}"

    if [ "$WITH_PARDISO" = "1" ] && [ "$PLATFORM" = "macos-arm64" ]; then
        die "PARDISO was requested on macos-arm64, where Intel oneMKL does not exist"
    fi
}

# ---------------------------------------------------------------------------
# Compiler flags
# ---------------------------------------------------------------------------
#
# -DARCH="Linux" everywhere is not a mistake: it selects the trailing-underscore
# Fortran symbol convention in CalculiX.h, which gfortran uses on all three
# platforms, MinGW included. Upstream's own Windows build does the same.
#
# Integer width stays 4-byte. The reference binary selects MKL's LP64
# interface, so anything wider would be a different program.

ccx_cflags() {
    _f="-Wall -O2 -fopenmp -I ../SPOOLES.2.2 -DARCH=\"Linux\" -DSPOOLES -DMATRIXSTORAGE"
    [ "$WITH_MT"      = "1" ] && _f="$_f -DUSE_MT=1"
    [ "$WITH_ARPACK"  = "1" ] && _f="$_f -DARPACK"
    [ "$WITH_PARDISO" = "1" ] && _f="$_f -DPARDISO -I$MKL_INCLUDE_DIR"
    [ "$WITH_PASTIX"  = "1" ] && _f="$_f -DPASTIX -I$PASTIX_PREFIX/include"
    echo "$_f"
}

ccx_fflags() {
    echo "-Wall -O2 -fopenmp"
}

# Extra flags for the two entry-point translation units only.
#
# ccx_<v>.c and ccx_<v>step.c open with, at FILE SCOPE:
#
#     #ifdef __WIN32
#     _set_output_format(_TWO_DIGIT_EXPONENT);
#     #endif
#
# which is not a call — a statement cannot execute at file scope — but a
# declaration, and one that now collides with MinGW's own prototype. Older GCC
# let it through as implicit-int; GCC 14 does not, and the Windows build stops
# there. Undefining __WIN32 for these two files removes a construct that never
# had a runtime effect, and leaves it defined for getSystemCPUs.c, which is the
# only place it means anything.
#
# Confirmed against the reference binary's output, which writes two-digit
# exponents (E+00) — exactly what a build where that statement never ran does.
# Link flags.
#
# On Windows the compiler runtime is linked STATICALLY. Without this the
# executable imports libgfortran-5.dll, libgcc_s_seh-1.dll, libgomp-1.dll and
# libwinpthread-1.dll from the MSYS2 installation that built it, and starts
# only on a machine that has one — everywhere else it dies with
# STATUS_DLL_NOT_FOUND before printing a line. The reference binary imports
# nothing but KERNEL32, msvcrt, psapi and mkl_rt, which is what this matches.
#
# oneMKL stays dynamic: it is a DLL by design, and shipping it beside the
# executable is deliberate.
# On Linux a fully static link against glibc brings its own problems, so the
# compiler runtime is linked statically where that is safe and whatever
# remains is staged beside the executable and found through -rpath $ORIGIN. A
# compute node has no reason to have gfortran installed.
ccx_ldflags() {
    case "$PLATFORM" in
        win-x64)   echo "-static" ;;
        linux-x64) echo "-static-libgcc -static-libgfortran" ;;
        *)         echo "" ;;
    esac
}

ccx_main_cflags() {
    case "$PLATFORM" in
        win-x64) echo "-U__WIN32" ;;
        *)       echo "" ;;
    esac
}
