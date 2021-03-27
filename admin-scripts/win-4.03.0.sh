#!/bin/bash

PREFIX=$(cygpath -m "$3" | sed -e "s/[\/&]/\\\\&/g")

# Configure for Windows
#   1. Set PREFIX (obviously)
#   2. Change LIBDIR to install to $PREFIX/lib/ocaml (default for Windows is just lib)
#   3. Remove the detection for a system flexlink to force bootstrapping
sed -e "s/^PREFIX=.*/PREFIX=$PREFIX/" -e "s/\/lib$/&\/ocaml/" -e "s/:=.*/=/" config/Makefile.$2 > config/Makefile
mv config/s-nt.h config/s.h
mv config/m-nt.h config/m.h

# Copy the FlexDLL sources ready for bootstrapping
mkdir -p flexdll
cp $(cygpath -m "$4")/* flexdll/

# This disables the installation of README, LICENCE and CHANGES files to the switch root
# This has altered in trunk, future versions should instead pass INSTALL_DISTRIB= to make install
# or possibly set DISTRIB to be something else in config/Makefile
sed -i -e "/INSTALL_DISTRIB/d" Makefile.nt

# Copy Makefile.nt to Makefile - means that the commands don't have to be invoked as make -f Makefile.nt
make -f Makefile.nt patches
cp -f Makefile.nt Makefile
