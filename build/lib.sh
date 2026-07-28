# Shared helpers. Sourced, never executed.
# POSIX sh with bash extensions kept out on purpose: this runs under MSYS2,
# Ubuntu and macOS, and the three do not agree on much beyond POSIX.

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m--> %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m*** %s\033[0m\n' "$*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || die "required tool not on PATH: $1"
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        die "no sha256sum and no shasum — cannot verify downloads"
    fi
}

# fetch_verify <url> <sha256> <dest>
#
# Downloads once and refuses to proceed on a checksum mismatch. Every input to
# a redistributed binary goes through here; nothing is taken on trust.
fetch_verify() {
    _url="$1"; _sha="$2"; _dest="$3"
    if [ -f "$_dest" ]; then
        _have=$(sha256_of "$_dest")
        if [ "$_have" = "$_sha" ]; then
            log "cached, checksum ok: $(basename "$_dest")"
            return 0
        fi
        warn "cached file has the wrong checksum, refetching: $(basename "$_dest")"
        rm -f "$_dest"
    fi
    log "fetching $(basename "$_dest")"
    # netlib and dhondt.de are single hosts with no CDN behind them, and a
    # build that dies because one of them blinked is a build people learn to
    # re-run rather than trust. Retry harder, on connection errors too, and say
    # plainly that the failure was the network.
    curl -fsSL --retry 5 --retry-delay 5 --retry-all-errors \
         --connect-timeout 20 --max-time 900 \
         -o "$_dest.part" "$_url" \
        || die "download failed after retries: $_url
This is a network failure, not a build failure — the file is pinned by
checksum, so re-running is safe."
    _have=$(sha256_of "$_dest.part")
    [ "$_have" = "$_sha" ] || die "checksum mismatch for $_url
  expected $_sha
  got      $_have"
    mv "$_dest.part" "$_dest"
}

# expect_in_file <file> <pattern> <what>
#
# Guards every in-place edit we make to a third-party build. If upstream
# changes shape, the build stops instead of silently skipping the fix.
expect_in_file() {
    grep -q "$2" "$1" || die "expected to find $3 in $1 — upstream layout changed, fix the build script"
}

cpu_count() {
    if command -v nproc >/dev/null 2>&1; then nproc
    elif command -v sysctl >/dev/null 2>&1; then sysctl -n hw.ncpu
    else echo 2
    fi
}
