# Patches

Empty, and that is the point: the CalculiX we distribute is upstream's,
unmodified.

If that ever stops being true, every change lands here as a `*.patch` file
applied by `build/ccx.sh` against a copy of `upstream/`, never by editing the
imported tree. Two reasons:

- `git log -- upstream/` must keep showing exactly what upstream shipped and
  nothing else, so the tree stays citable as the corresponding source.
- A GPL distributor has to be able to say precisely what it changed. A
  directory of patches answers that; a modified tree does not.

Fixes to third-party dependencies (SPOOLES has one, a source file its own
makefile lists but never shipped) are applied by the dependency's build script
with a guard that fails the build if upstream's layout moves — see
`expect_in_file` in `build/lib.sh`.
