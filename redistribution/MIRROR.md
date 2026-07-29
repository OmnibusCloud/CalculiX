# Redistribution mirror

What OmnibusCloud hands to other people, and the source that has to travel
with it. Produced and verified by [`mirror.sh`](mirror.sh); published as the
release [`upstream-mirror-2.22`](https://github.com/OmnibusCloud/CalculiX/releases/tag/upstream-mirror-2.22).

## Why this exists

The OmnibusCloud solver shim can bundle CalculiX so that an analysis still
runs when the cloud is unreachable and the machine has no CalculiX of its own.
The binary it bundles is **upstream's official Windows build, redistributed
unmodified** — not our build. That decision is on record in `PROVENANCE.md`
and was confirmed in practice: an ordinary deck from the acceptance corpus
(`beamp`) selects PaStiX, which upstream's binary links and ours does not yet,
and an unlinked solver in `ccx` is a hard stop rather than a quiet downgrade.

Distributing it makes two things our responsibility rather than someone else's:

- **The corresponding source.** GPL-2.0 section 3 requires it to be available
  to any third party who receives the binary. Pointing at another person's web
  server is a promise about a host we do not run; mirroring it here, publicly
  and with no account wall, is what actually discharges it.
- **The release build.** A pipeline that downloads from a single personal web
  server fails on the day that server is down. The shim's installer pulls the
  kit from this mirror, with upstream as the documented origin and fallback.

## Inventory

Every file is byte-identical to what upstream published. The `Established by`
column matters: the versions of the statically linked libraries were read out
of the redistributed binary, not assumed from what a current build would use.

| File | What | Licence | SHA-256 | Established by |
|---|---|---|---|---|
| `calculix_2.22_4win.zip` | the redistributed Windows kit (`ccx_dynamic.exe` is inside it) | GPL-2.0 | `a1f91281944c96d6cd914cc020421e8ae65973b3e15d055dc63a3e3e3066d281` | upstream's published archive; the exe inside is `1c1f4ad9…`, the same file PrePoMax 2.5.0 installs |
| `ccx_2.22.src.tar.bz2` | corresponding source of CalculiX, including the makefiles that control its compilation | GPL-2.0 | `3a94dcc775a31f570229734b341d6b06301ebdc759863df901c8b9bf1854c0bc` | upstream's published source archive |
| `spooles.2.2.tgz` | SPOOLES 2.2, linked statically | public domain (Boeing) | `a84559a0e987a1e423055ef4fdf3035d55b65bbe4bf915efaa1a35bef7f8c5dd` | `FrontMtx_MT_*` symbols in the binary; upstream's README names 2.2 |
| `arpack-ng-3.9.1.tar.gz` | ARPACK-NG 3.9.1, linked statically | BSD-3-Clause | `f6641deb07fa69165b7815de9008af3ea47eb39b2bb97521fbf74c97aba6e844` | source paths embedded in the binary: `arpack-ng-3.9.1/SRC/…` |
| `hwloc-2.11.1.tar.gz` | hwloc 2.11.1, pulled in by PaStiX | BSD-3-Clause | `9f320925cfd0daeaf3a3d724c93e127ecac63750c623654dca0298504aac4c2c` | source paths embedded in the binary: `hwloc-2.11.1/hwloc/…` |

The CalculiX source is additionally committed in this repository, unmodified,
under `upstream/ccx_2.22/src`, so `git log -- upstream/` shows exactly what
upstream shipped.

### Not yet mirrored, and why

| Component | State |
|---|---|
| **PaStiX** (Dhondt's `PaStiX4CalculiX` fork) | The binary reports `Version: 6.0.1` when it runs, so the base version is known; the fork's exact commit is not recorded anywhere in the binary. Until it is established, this component is covered by the written offer in the shim's `CALCULIX-NOTICE.txt` section 2.5 rather than by a mirrored archive with a wrong-but-plausible version on it. |
| **Scotch** | `SCOTCH_*` and PT-Scotch symbols are present, but no version string is embedded and none is printed. Same treatment. |
| **Intel oneMKL** | Not GPL and not source-distributable: proprietary Intel software, redistributed as runtime libraries under the Intel Simplified Software License. Pinned by version (2022.2.1) in `build/mkl.sh` and fetched from PyPI, whose URLs are content-addressed. |

Closing the first two means either finding the version markers by a deeper
look at the binary, or asking upstream. Recording them as unknown is the
honest state; guessing a commit would make the notice worse, not better,
because a mirror that claims to be the corresponding source and is not is a
stronger misstatement than an offer to supply it.

## Following upstream

CalculiX releases are announced on <http://www.dhondt.de/>. When a new version
appears:

1. Fetch the new Windows kit and source archive and record their checksums.
2. Re-read the linked-library versions **out of the new binary** — they change
   between builds, and the whole point of the table above is that it describes
   the binary we ship rather than the one we shipped last time. The technique
   is in `PROVENANCE.md`: embedded source paths and printed banners.
3. Add a new block to `mirror.sh` and a new row set here, and publish under a
   **new** tag (`upstream-mirror-<version>`).
4. Update the pins in the shim's `Setup/Get-BundledCalculiX.ps1` and the
   checksums quoted in `Setup/Distribution/CALCULIX-NOTICE.txt`.

Never rewrite a published mirror release. Other documents cite these files by
checksum, and a shipped installer names them; an asset that changes under a
tag turns those citations into falsehoods.
