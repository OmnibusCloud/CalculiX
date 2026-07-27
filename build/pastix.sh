#!/bin/sh
# PaStiX support — staged, not yet implemented.
#
# Why it is staged rather than skipped:
#
#   ccx's default solver is SPOOLES, and PaStiX runs only when a deck says
#   SOLVER=PASTIX. PrePoMax writes Solver=Pardiso by default, so the common
#   path does not touch PaStiX at all. But the reference build has it, and a
#   solver that is not linked in is a hard error — so an engineer who has
#   chosen PaStiX in PrePoMax would hit a failure they did not have before.
#   That makes it a release blocker for the Windows kit, not an optional
#   extra, and it must be closed before the shim ships beside it.
#
# What it takes (upstream README.INSTALL, "PaStiX"):
#   OpenBLAS, hwloc 2.11.1, parsec, Scotch, and Dhondt's PaStiX4CalculiX fork,
#   in that order. Upstream builds these with 8-byte integers; the reference
#   Windows binary does not (it selects MKL's LP64 interface), so the 4-byte
#   path is the one to reproduce.
set -e

. "$BUILD_DIR/lib.sh"

die "WITH_PASTIX=1 was requested, but the PaStiX build is not implemented yet.
Build without it, or track the work in the repository issues. See the comment
at the top of this file for the dependency chain and why the 4-byte integer
configuration is the one to match."
