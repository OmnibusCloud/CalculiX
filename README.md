# CalculiX — OmnibusCloud build and source mirror

This repository is the **corresponding source** and the **build pipeline** for
the CalculiX CrunchiX (`ccx`) binaries that OmnibusCloud distributes.

CalculiX is free software by **Guido Dhondt** (solver) and **Klaus Wittig**
(pre- and postprocessor), licensed under the **GNU General Public License,
version 2**. We do not own it, we did not write it, and we distribute it
unmodified. See [LICENSE](LICENSE) and [PROVENANCE.md](PROVENANCE.md).

Upstream lives at <http://www.calculix.de> and <http://www.dhondt.de>.

## Why this repository exists

OmnibusCloud ships `ccx` in two places, for two different reasons — and, as of
2026-07-27, **from two different sources**:

1. **Beside the PrePoMax solver shim**, so that decks the cloud does not take
   still solve locally, out of the box, with no path hunting. Windows only,
   because PrePoMax is Windows only. **This one is upstream's own binary**,
   redistributed unmodified, not a build of ours — see below.
2. **As an asset of the CalculiX controller**, so that a compute node can run
   a full, unrestricted `ccx` job. Nodes are heterogeneous, so this one needs
   `win-x64`, `linux-x64` and `macos-arm64`, and **this is what the pipeline
   here builds**.

### Why the shim gets upstream's binary rather than ours

The shim's job is to change nothing about work the cloud does not take. The
binary already on the engineer's machine is upstream's official Windows build
(proven byte-for-byte, see [PROVENANCE.md](PROVENANCE.md)), and it links
PaStiX. Ours does not yet, and `ccx` treats an unlinked solver as a hard stop
— so anyone who had selected PaStiX in PrePoMax would meet a failure they did
not have before.

Redistributing the same binary makes that risk exactly zero rather than small:
it is not "numerically equivalent to what you had", it *is* what you had. It
also removes PaStiX from the critical path, which is the expensive dependency
in this whole repository.

Our own builds keep their reason for existing — the controller needs three
platforms and there is no upstream binary for two of them — but there the
constraint is different, because we control both ends and can decline work a
node's solver cannot do.

Distributing a GPL program obliges us to offer its complete corresponding
source, together with the scripts that control its compilation. That is this
repository: the upstream source verbatim under [`upstream/`](upstream/), every
patch we apply under [`patches/`](patches/), and the full build under
[`build/`](build/). Every binary we publish can be rebuilt from this tree
alone.

## What is built

Version **2.22** — pinned deliberately, not incidentally. PrePoMax 2.5.0 ships
`ccx` 2.22, and the moment our binary sits beside the shim it wins the solver
resolution order and starts computing the engineer's *ordinary local results*.
A different version, or a different sparse backend, would mean "after I
installed your thing my numbers moved" — precisely the harm the local fallback
exists to prevent.

The reference configuration was recovered from the binary PrePoMax ships,
which is byte-for-byte the official upstream Windows build (see
[PROVENANCE.md](PROVENANCE.md)):

| Component | Configuration |
|---|---|
| Integer width | 4-byte (`LP64`) — no `-DINTSIZE64` |
| SPOOLES 2.2 | static, **multithreaded** (`-DUSE_MT=1`) |
| ARPACK | static (arpack-ng) |
| PARDISO | Intel oneMKL, single dynamic library (`mkl_rt`) |
| PaStiX | static, with Scotch |
| Toolchain | GCC / gfortran (MSYS2 MinGW-w64 on Windows) |

`ccx`'s own default solver is SPOOLES; PARDISO and PaStiX are selected only by
an explicit `SOLVER=` on the step card. PrePoMax writes `Solver=Pardiso` by
default, so PARDISO is not optional in practice. **A solver that is not linked
in is a hard error, not a silent fallback** — which is why platform parity of
the linked set matters, and why it is stated per platform below.

## Platform matrix

| Platform | SPOOLES | ARPACK | PARDISO | PaStiX | Kit size | Notes |
|---|---|---|---|---|---|---|
| `win-x64` | ✅ MT | ✅ | ✅ | staged | 228 MB | serves both consumers; built first |
| `linux-x64` | ✅ MT | ✅ | ✅ | staged | 264 MB | controller asset |
| `macos-arm64` | ✅ MT | ✅ | ❌ | staged | 2 MB | **no Intel oneMKL exists for arm64** |

All three build green and pass upstream's acceptance suite. The size gap is the
oneMKL runtime, which is most of what a Windows or Linux kit weighs.

PaStiX is **staged everywhere and blocking nowhere**, now that the shim ships
upstream's binary. A node whose `ccx` lacks a solver a deck asks for is a
dispatch question, and the platform already answers it: controller archive
variants carry `runtimeTargets` and `requiredCapabilities`, and clients
advertise capabilities, so a variant can say which solvers its bundled `ccx`
has. Capability is the right axis, not OS — macOS lacking PARDISO is
OS-determined, but a Windows kit lacking PaStiX is not.

`macos-arm64` cannot link PARDISO — Intel oneMKL is x86-64 only. A deck that
asks for `SOLVER=PARDISO` therefore fails on a macOS node while succeeding on
the others. That is a dispatch concern for the CalculiX controller (advertise
the linked solver set per node, or normalise the keyword), not something a
build flag can fix.

## Building

```sh
build/build.sh                 # host platform, default feature set
WITH_PASTIX=1 build/build.sh   # add PaStiX (see build/README.md)
```

The build fetches its dependencies from pinned URLs and verifies every one
against a recorded SHA-256 before use. Nothing is taken from the host except
the compiler. CI runs the same script on all three platforms; see
[`.github/workflows/build.yml`](.github/workflows/build.yml).

## What we do not do

We do not modify the solver, and we do not link anything of ours into it. Our
own tools invoke `ccx` as a separate process, over its command line — mere
aggregation, not a derived work. Our tools stay proprietary; `ccx` stays GPL;
neither changes the other's licence.

We also do not lift the binary out of a PrePoMax installation. Users may point
the shim at their own `ccx` build instead, through `localSolverPath`.
