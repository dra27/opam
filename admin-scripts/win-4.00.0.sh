#!/bin/bash

PREFIX=$(cygpath -m "$3" | sed -e "s/[\/&]/\\\\&/g")
LIB=$(cygpath -m "$4" | sed -e "s/[\/&]/\\\\&/g")
TK_DEFS=$(cygpath -m "$5" | sed -e "s/[\/&]/\\\\&/g")
TK_VER=${6%.*}
TK_VER=${TK_VER/./}
if [ "$7" = "a" ] ; then
  TK_LINK="-L$TK_DEFS -ltk$TK_VER -ltcl$TK_VER"
else
  TK_LINK="$TK_DEFS\\/tk$TK_VER.lib $TK_DEFS\\/tcl$TK_VER.lib"
fi

# Configure for Windows
#   1. Set PREFIX (obviously)
#   2. Set IFLEXDIR to point to the OPAM location of flexdll.h (flexdll:lib) - up to OCaml 4.03.0
#   3. Change LIBDIR to install to $PREFIX/lib/ocaml (default for Windows is just lib)
#   4. Change DISTRIB to install to the build directory (i.e. don't install) - up to OCaml 4.02.0
#   5. Configure Tcl/Tk
sed -e "s/^PREFIX=.*/PREFIX=$PREFIX/" -e "s/^\(IFLEXDIR=-I.\).*\(.\)/\1$LIB\2/" -e "s/\/lib$/&\/ocaml/" -e "s/DISTRIB=.*/DISTRIB=config/" -e "s/^TK_DEFS=.*/TK_DEFS=-I$TK_DEFS/" -e "s/^TK_LINK=.*/TK_LINK=$TK_LINK/" config/Makefile.$2 > config/Makefile
#if [ "${2/64/}" = "mingw" ] ; then
if [ "$2" = "mingw" ] ; then
  sed -i -e "s/FLEXLINK=.*/& -link -static-libgcc/" config/Makefile
fi
mv config/s-nt.h config/s.h
mv config/m-nt.h config/m.h

# Copy Makefile.nt to Makefile - means that the commands don't have to be invoked as make -f Makefile.nt
make -f Makefile.nt patches
cp -f Makefile.nt Makefile
