# Provenance

Everything this repository builds from, and everything OmnibusCloud
distributes, is listed here with the checksum it was verified against.
Recorded 2026-07-27.

## Upstream CalculiX source

The tree under [`upstream/ccx_2.22/src`](upstream/ccx_2.22/src) is the verbatim
content of the official source tarball. It is imported in its own commit, with
no edits, so that `git log -- upstream/` shows exactly what upstream shipped
and nothing else.

| Item | Value |
|---|---|
| URL | <http://www.dhondt.de/ccx_2.22.src.tar.bz2> |
| SHA-256 | `3a94dcc775a31f570229734b341d6b06301ebdc759863df901c8b9bf1854c0bc` |
| Size | 1 536 859 bytes |
| Upstream date | 2024-08-05 |
| Licence | GNU GPL version 2 (`upstream/ccx_2.22/src/gpl-2.0.txt`) |

Modifications: **none.** Should that ever change, every patch goes in
[`patches/`](patches/) and is applied by the build script, never by hand.

## The reference binary, and how the build configuration was determined

We build `ccx` ourselves rather than redistributing an upstream binary. To
build it *to the same configuration*, that configuration first had to be
established. It was recovered from the binary PrePoMax 2.5.0 ships, which
turns out to be the official upstream Windows build, unaltered:

| Item | SHA-256 |
|---|---|
| `calculix_2.22_4win.zip` (<http://www.dhondt.de/>) | `a1f91281944c96d6cd914cc020421e8ae65973b3e15d055dc63a3e3e3066d281` |
| `ccx_dynamic.exe` inside that zip | `1c1f4ad9392c0a9537e9ff1d7adaf86ea0a6193da5916abb2912ae541e530c10` |
| `Solver/ccx_dynamic.exe` in PrePoMax 2.5.0 | `1c1f4ad9392c0a9537e9ff1d7adaf86ea0a6193da5916abb2912ae541e530c10` |

The two are the same file. So the binary an engineer's PrePoMax runs today is
upstream's own build, produced by Rafał Brzegowy on 2024-08-04 with MSYS2 /
MinGW-w64 gfortran, and the flags to match are these — each one read off the
binary rather than assumed:

| Evidence in the binary | Conclusion |
|---|---|
| `FrontMtx_MT_factorInpMtx`, `FrontMtx_MT_solve`, `spooles.out` | SPOOLES built and linked **multithreaded** → `-DUSE_MT=1` |
| `dsaupd_`, `dseupd_` | ARPACK linked → `-DARPACK` |
| `matrixstorage` | `-DMATRIXSTORAGE` |
| no `network.out`, no `NETWORKOUT` | **not** built with `-DNETWORKOUT` |
| `PARDISO`, MKL single dynamic library | `-DPARDISO` against `mkl_rt` |
| `PASTIX_*`, `SCOTCH_*` symbols | `-DPASTIX`, PaStiX static with Scotch |
| no `MKL_INTERFACE_LAYER` / `mkl_set_interface_layer` | MKL LP64 → **4-byte integers**, no `-DINTSIZE64` |
| `hwloc-2.11.1` | PaStiX built against hwloc 2.11.1 |
| banner: `executable made on Sun Aug 4 19:44:24 2024` | build date of the reference |

That flag set is upstream's `Makefile_MT` plus `-DPARDISO -DPASTIX`, which is
what [`build/config.sh`](build/config.sh) encodes.

We do **not** redistribute this binary, and we do not copy it out of a PrePoMax
installation. It is used only as a comparison target: our build must agree with
it numerically on the deck corpus.

## Build dependencies, pinned

| Dependency | Version | URL | SHA-256 |
|---|---|---|---|
| SPOOLES | 2.2 | <https://netlib.org/linalg/spooles/spooles.2.2.tgz> | `a84559a0e987a1e423055ef4fdf3035d55b65bbe4bf915efaa1a35bef7f8c5dd` |
| arpack-ng | 3.9.1 | <https://github.com/opencollab/arpack-ng/archive/refs/tags/3.9.1.tar.gz> | `f6641deb07fa69165b7815de9008af3ea47eb39b2bb97521fbf74c97aba6e844` |

SPOOLES 2.2 is distributed by netlib without a licence file; its own
documentation places it in the public domain, contributed by Boeing. arpack-ng
is BSD-3-Clause. Both are linked statically into `ccx`, which is GPL-2.0 — both
licences permit that.

### Intel oneMKL (PARDISO backend)

`ccx` reaches PARDISO through Intel oneMKL's single dynamic library. MKL is
proprietary; Intel's Simplified Software License permits redistribution of the
runtime libraries, which is the basis on which we ship them.

PrePoMax 2.5.0 ships this set, and we match its version so that a fallback run
produces the same numbers as the engineer's previous local runs:

| File | File version |
|---|---|
| `mkl_rt.2.dll` | 2022.2.1 |
| `mkl_core.2.dll` | 2022.2.1 |
| `mkl_intel_thread.2.dll` | 2022.2.1 |
| `mkl_def.2.dll` | 2022.1.1 |
| `libiomp5md.dll` | 20210428 |

Note the mixed versions — that is PrePoMax's own set, reproduced deliberately,
not an oversight on our side.

**Bundle size.** `ccx` is 48.5 MB and the MKL runtime is 207 MB, so the Windows
kit is roughly **255 MB**, not the 50–100 MB estimated before measurement.

## Reproducibility

Upstream's `date.pl` rewrites `ccx_<version>.c` and `frd.c` to stamp the build
date into the banner and into the `UCOMPILETIME` line of every `.frd` file. We
**do not run it**: it would modify the source and make each build differ from
the last for no benefit. Our builds are identified by the checksums published
with each release, and the shim's `--doctor` reports the checksum of the `ccx`
it resolved.

## What OmnibusCloud distributes

| Artefact | Licence | Source |
|---|---|---|
| `ccx` binaries built here | GPL-2.0 | this repository |
| SPOOLES, arpack-ng, PaStiX, Scotch (statically linked) | public domain / BSD / LGPL-compatible | pinned above |
| Intel oneMKL runtime | Intel Simplified Software License | Intel |
| OmnibusCloud solver shim, controllers | proprietary | separate process, not linked |
