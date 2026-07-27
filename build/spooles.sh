#!/bin/sh
# Build SPOOLES 2.2 statically, multithreaded, into $WORK/SPOOLES.2.2/spooles.a
#
# SPOOLES is from 1998 and predates every C standard a modern compiler
# defaults to. The flags below are what it takes to compile it as written,
# not stylistic preference:
#   -std=gnu89   K&R-era implicit declarations and old-style definitions
#   -fcommon     tentative definitions in headers, an error since GCC 10
#   -w           the resulting noise would bury real diagnostics
set -e

. "$BUILD_DIR/lib.sh"
. "$BUILD_DIR/config.sh"

SPOOLES_DIR="$WORK/SPOOLES.2.2"

if [ -f "$SPOOLES_DIR/spooles.a" ] && [ "${FORCE:-0}" != "1" ]; then
    log "SPOOLES already built"
    exit 0
fi

fetch_verify "$SPOOLES_URL" "$SPOOLES_SHA256" "$WORK/deps/spooles.2.2.tgz"

# The tarball has no top-level directory and unpacks into the current one.
rm -rf "$SPOOLES_DIR"
mkdir -p "$SPOOLES_DIR"
( cd "$SPOOLES_DIR" && tar xzf "$WORK/deps/spooles.2.2.tgz" )

# Known defect in the 2.2 distribution, called out in CalculiX's own
# README.INSTALL: the makefile lists a source file that was never shipped.
expect_in_file "$SPOOLES_DIR/Tree/src/makeGlobalLib" "drawTree.c" "the drawTree.c reference"
sed -i.bak 's/drawTree\.c/draw.c/' "$SPOOLES_DIR/Tree/src/makeGlobalLib"

cat > "$SPOOLES_DIR/Make.inc" <<EOF
CC = ${CC:-cc}
OPTLEVEL = -O2
CFLAGS = \$(OPTLEVEL) -std=gnu89 -fcommon -w -fPIC
LDFLAGS =
THREAD_LIBS = -lpthread
PURIFY =
PURIFY_GCC_VERSION =
AR = ar
ARFLAGS = rv
RANLIB = ranlib

.c.o :
	\$(CC) -c \$(CFLAGS) \$<

.c.a :
	\$(CC) -c \$(CFLAGS) \$<
	\$(AR) \$(ARFLAGS) \$@ \$*.o
	rm -f \$*.o
EOF

log "building SPOOLES (serial parts)"
( cd "$SPOOLES_DIR" && make global )

if [ "$WITH_MT" = "1" ]; then
    # The top-level makefile leaves MT/src commented out. Rather than edit a
    # third-party makefile we build that one directory directly — it appends
    # to the same archive, which is all the `global` target would have done.
    log "building SPOOLES (multithreaded parts)"
    ( cd "$SPOOLES_DIR/MT/src" && make -f makeGlobalLib )
fi

[ -f "$SPOOLES_DIR/spooles.a" ] || die "SPOOLES built without producing spooles.a"

if [ "$WITH_MT" = "1" ]; then
    # A silently serial SPOOLES would still link and still solve, just without
    # the threading the reference build has. Prove the symbol is in.
    ar t "$SPOOLES_DIR/spooles.a" | grep -q "MT_factorMT.o\|MT_solveMT.o" \
        || die "multithreaded SPOOLES was requested but its objects are not in spooles.a"
fi

log "SPOOLES ready: $SPOOLES_DIR/spooles.a"
