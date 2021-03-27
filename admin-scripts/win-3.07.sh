#!/bin/bash

PREFIX=$(cygpath -m "$2" | sed -e "s/[\/&]/\\\\&/g")
TK_DEFS=$(cygpath -m "$3" | sed -e "s/[\/&]/\\\\&/g")
TK_VER=${4%.*}
TK_VER=${TK_VER/./}
if [ "$5" = "a" ] ; then
  TK_LINK="-L$TK_DEFS -ltk$TK_VER -ltcl$TK_VER"
else
  TK_LINK="$TK_DEFS\\/tk$TK_VER.lib $TK_DEFS\\/tcl$TK_VER.lib"
fi

# Configure for Windows
#   1. Set PREFIX (obviously)
#   2. Change LIBDIR to install to $PREFIX/lib/ocaml (default for Windows is just lib)
#   3. Change DISTRIB to install to the build directory (i.e. don't install)
#   4. Configure Tcl/Tk
sed -e "s/^PREFIX=.*/PREFIX=$PREFIX/" -e "s/\/lib$/&\/ocaml/" -e "s/DISTRIB=.*/DISTRIB=config/" -e "s/^TK_DEFS=.*/TK_DEFS=-I$TK_DEFS/" -e "s/^TK_LINK=.*/TK_LINK=$TK_LINK/" config/Makefile.$1 > config/Makefile
mv config/s-nt.h config/s.h
mv config/m-nt.h config/m.h

# Patches to ocamltopwin:
#   1. Install OCamlWin.exe to BINDIR instead of PREFIX
#   2. Disable the use of the registry to store the location of ocaml.exe
#   3. Hardcode the location of ocaml.exe and ocaml:lib
sed -i -e "s/PREFIX/BINDIR/" win32caml/Makefile
sed -i -e "/GetOcamlPath/d" \
       -e "s/OcamlPath.*[^;]/& = \"$(echo $2| sed -e "s/\\\\/\\\\\\\\\\\\\\\\/g")\\\\\\\\bin\\\\\\\\ocaml.exe\"/" \
       -e "s/LibDir.*[^;]/& = \"$(echo $2| sed -e "s/\\\\/\\\\\\\\\\\\\\\\/g")\\\\\\\\lib\\\\\\\\ocaml\"/" win32caml/ocaml.c

# Copy Makefile.nt to Makefile - means that the commands don't have to be invoked as make -f Makefile.nt
make -f Makefile.nt patches
cp -f Makefile.nt Makefile
