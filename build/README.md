# Build

```sh
build/build.sh          # host platform
build/verify.sh         # acceptance suite against the result
```

Output lands in `.build/out`: the executable, the oneMKL runtime it needs,
the GPL text, `PROVENANCE.md`, and a `BUILDINFO.txt` recording the flags and
the checksum of every file in the kit.

## Files

| File | What it does |
|---|---|
| `build.sh` | orchestrator: detect platform, choose features, run the rest |
| `config.sh` | every pinned version and every compiler flag, with the reasoning |
| `lib.sh` | fetch-and-verify, guarded edits, logging |
| `spooles.sh` | SPOOLES 2.2, static, multithreaded |
| `arpack.sh` | arpack-ng, static |
| `mkl.sh` | stages Intel oneMKL for PARDISO |
| `pastix.sh` | staged; see the file |
| `Makefile.ccx` | compilation control; includes upstream's object lists verbatim |
| `verify.sh` | upstream's 610-deck acceptance suite, plus reference-binary diff |

## Knobs

| Variable | Default | Meaning |
|---|---|---|
| `WITH_PARDISO` | 1, except macOS arm64 | link Intel oneMKL PARDISO |
| `WITH_PASTIX` | 0 | link PaStiX |
| `WITH_ARPACK` | 1 | link ARPACK (needed by `*FREQUENCY`, `*BUCKLE`) |
| `WITH_MT` | 1 | multithreaded SPOOLES, matching the reference build |
| `FORCE` | 0 | rebuild dependencies rather than reuse `.build` |
| `WORK` | `.build` | build tree location |
| `VERIFY_ONLY` | — | space-separated job names, for a quick run |
| `REFERENCE_CCX` | — | a second `ccx` to compare results against |

## The check that matters

Agreement with the `.dat.ref` files upstream ships proves the build is
*correct*. It does not prove the build is *the same as the one already on the
engineer's machine* — and that is the promise the local fallback makes, since
the moment our binary sits beside the shim it wins the resolution order and
starts producing their ordinary results.

So before a Windows kit ships, run:

```sh
REFERENCE_CCX='/c/Workspace/OutWit/@Tools/PrePoMax v2.5.0/Solver/ccx_dynamic.exe' \
    build/verify.sh
```

which runs both binaries over the same 610 decks and compares ours to theirs
directly. An empty report is the release gate.
