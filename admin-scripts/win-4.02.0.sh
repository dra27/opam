#!/bin/bash

PREFIX=$(cygpath -m "$3" | sed -e "s/[\/&]/\\\\&/g")
LIB=$(cygpath -m "$4" | sed -e "s/[\/&]/\\\\&/g")

# Configure for Windows
#   1. Set PREFIX (obviously)
#   2. Set IFLEXDIR to point to the OPAM location of flexdll.h (flexdll:lib)
#   3. Change LIBDIR to install to $PREFIX/lib/ocaml (default for Windows is just lib)
sed -e "s/^PREFIX=.*/PREFIX=$PREFIX/" -e "s/^\(IFLEXDIR=-I.\).*\(.\)/\1$LIB\2/" -e "s/\/lib$/&\/ocaml/" config/Makefile.$2 > config/Makefile
mv config/s-nt.h config/s.h
mv config/m-nt.h config/m.h

# This disables the installation of README, LICENCE and CHANGES files to the Cygwin root!
sed -i -e "/INSTALL_DISTRIB/d" Makefile.nt

# Copy Makefile.nt to Makefile - means that the commands don't have to be invoked as make -f Makefile.nt
make -f Makefile.nt patches
cp -f Makefile.nt Makefile
