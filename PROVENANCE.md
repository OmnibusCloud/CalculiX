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

### Agreement measured over the whole suite

Run 2026-07-27: `win-x64`, both binaries over the same 605–606 decks,
single-threaded, on a machine that built neither of them.

| Phase | Question | Deviations |
|---|---|---|
| **A** | our build vs the reference **files** upstream ships | **6** of 605 |
| **B** | the reference **binary** vs those same files | **9** of 605 |
| **C** | our build vs the reference **binary** | **3** of 606 |

311 of the 606 `.dat` files are **byte-identical** between the two binaries.

Phase B is the reason phase A is readable at all. Parts of this suite are
ill-conditioned enough that upstream's own binary does not reproduce upstream's
own published results either, so "we deviate on six decks" means nothing until
you know the incumbent deviates on nine.

- Both deviate: `acou1`, `beamfsh1`, `beamptied5`, `beamptied6`.
- **Only we do:** `acou2`, `rotor2`.
- **Only the incumbent does:** `beamt6`, `contact15`, `contact17`, `load1`,
  `truss2`.

And all three phase-C decks — `contact15`, `contact17`, `load1` — come from
that last group. On those, upstream's published result, the incumbent and our
build are three different answers, and ours is the one that matches what
upstream published.

What the deviations are, by kind:

- `acou2` is a **sign flip on an eigenvector component**: `-9.999949e-02`
  against `+9.999949e-02`, seven digits of agreement in magnitude. Eigenvector
  phase is arbitrary; this is not an error.
- `rotor2` is `*COMPLEX FREQUENCY` — 13% on one value. Complex eigenvalues run
  through ARPACK, and ARPACK runs on whichever LAPACK it was linked against;
  ours is oneMKL, the reference's was OpenBLAS.
- `contact15`, `contact17` are `*DYNAMIC` with contact, `load1` is `*STATIC`
  with contact. Active-set problems can converge to different states from
  arithmetic ordering alone, which is also why the incumbent misses the
  published values on them.

**None of them is conduction or plain linear statics** — the deviations sit in
contact, complex eigenvalue and acoustic analyses.

**Consequence for WitSweep, which runs full `ccx` on heterogeneous nodes:** on
contact problems the achievable agreement between two honest builds is percent,
not round-off. Determinism there has to be stated as a tolerance and measured,
not assumed.

### Thread count changes results, and that is worse than build differences

Measured on one machine, one binary, varying nothing but `OMP_NUM_THREADS`, on
`rotor2` (`*COMPLEX FREQUENCY` with Coriolis):

| Threads | Output length | Mode 18 |
|---|---|---|
| 1 | 622 lines | `0.1029336E+06` |
| 2 | 597 lines | `0.1187708E+06` |
| 4 | 597 lines | `0.1187708E+06` |
| 8 | 597 lines | `0.1187708E+06` |

Not a tolerance question — a **different number of modes converged**, so the
files are not even the same length. The same deck also produced 680 and 708
lines on CI machines at one thread, and forcing MKL's kernel (`SSE4_2`, `AVX`,
`AVX2`, `AVX512`) changes nothing, which rules out kernel dispatch: the
eigensolver converges elsewhere whenever the arithmetic path shifts at all.

Two consequences worth carrying:

- Upstream's published reference for this deck agrees with the **multithreaded**
  runs, while upstream's own `compare` script runs the suite at one thread. The
  reference was produced under conditions other than the ones it is checked
  under, which is why it looks like a defect and is not one.
- **For a parameter sweep this outranks build-to-build differences.** Nodes
  with different core counts will not agree on an ill-conditioned deck even
  when they run the identical binary. A sweep that wants comparable variants
  has to pin the thread count for the whole sweep, not leave it to each node.

Reproduce with:

```sh
REFERENCE_CCX='…/PrePoMax v2.5.0/Solver/ccx_dynamic.exe' build/verify.sh
```

### All three platforms, and how far apart they sit

Run 2026-07-28, `full_verify`, the whole suite on each platform:

| Platform | Decks compared | Known deviations | **New** |
|---|---|---|---|
| `win-x64` | 599 | 11 | **0** |
| `linux-x64` | 600 | 10 | **0** |
| `macos-arm64` | 600 | 11 | **0** |

And each platform against `win-x64`, deck by deck:

| Comparison | Compared | Deviating | Not comparable |
|---|---|---|---|
| `linux-x64` vs `win-x64` | 605 | **0** | 1 (`rotor2`) |
| `macos-arm64` vs `win-x64` | 605 | **0** | 1 (`rotor2`) |

**605 of 606 decks agree exactly across all three platforms**, within upstream's
own tolerances. The 606th is `rotor2`, the deck with no stable answer — it is
not comparable by length, for the reason measured above.

Windows is the reference for the cross-platform comparison because it is the
only platform anchored twice: against upstream's published results and against
the binary PrePoMax ships. Anchoring the others to it puts them one link from
both.

What this does and does not establish: agreement across platforms bounds the
*scatter* a heterogeneous fleet can produce. It does not establish correctness
— all three could be wrong together. Correctness is what the table above it
answers, against upstream's published results. Both are needed.

### Linked solvers, and where we differ from the reference

| Solver | Reference | Ours (`win-x64`) |
|---|---|---|
| SPOOLES (multithreaded, the ccx default) | ✅ | ✅ |
| PARDISO (what PrePoMax writes by default) | ✅ | ✅ |
| ARPACK (`*FREQUENCY`, `*BUCKLE`) | ✅ | ✅ |
| PaStiX | ✅ | ❌ **not yet** |

Measured, not assumed — forcing each solver onto `beamp` with our build:

```
SPOOLES  exit=0    result written
PARDISO  exit=0    result written
PASTIX   exit=201  *ERROR in linstatic: the PASTIX library is not linked
```

PrePoMax exposes PaStiX in its solver list (`SolverType` in `CaeModel.dll`
carries `Spooles`, `Pardiso`, `PaStiX`), so this is reachable by an ordinary
user, and **an unlinked solver in ccx is a hard stop, not a fallback**. Anyone
who has chosen PaStiX would meet a failure they did not have before — which is
why PaStiX blocks the Windows kit rather than merely postponing a feature.

Worth knowing for whatever consumes the output: the failed run still leaves a
45-byte `.dat` behind. Presence of the file is not evidence of a result.

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
