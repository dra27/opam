#!/bin/bash

BUILD_VER=${1//./}
PORT=$2
PREFIX=$(cygpath -m "$3" | sed -e "s/[\/&]/\\\\&/g")
WINPREFIX=$(echo $3| sed -e "s/\\\\/\\\\\\\\\\\\\\\\/g")
if (( BUILD_VER < 4030 )) ; then
  FLEXDIR=$(cygpath -m "$4" | sed -e "s/[\/&]/\\\\&/g")
  if (( BUILD_VER < 4020 )) ; then
    TK_DEFS=$(cygpath -m "$5" | sed -e "s/[\/&]/\\\\&/g")
    TK_VER=${6%.*}
    TK_VER=${TK_VER/./}
    if [ "$7" = "a" ] ; then
      TK_LINK="-L$TK_DEFS -ltk$TK_VER -ltcl$TK_VER"
    else
      TK_LINK="$TK_DEFS\\/tk$TK_VER.lib $TK_DEFS\\/tcl$TK_VER.lib"
    fi
    shift 3
  fi
else
  FLEXDLL_PATH=$4
fi
shift 4

RUNTIMED=noruntimed
FLAMBDA=false
SAFE_STRING=false
while : ; do
  case "$1" in
    "")
      break
      ;;
    -with-debug-runtime|--with-debug-runtime)
      RUNTIMED=runtimed
      ;;
    -flambda|--flambda)
      FLAMBDA=true
      ;;
    -safe-string|--safe-string)
      SAFE_STRING=true
      ;;
    *)
      echo "Unknown option \"$1\"">&2
      exit 2
      ;;
  esac
  shift
done

# Configure for Windows
#   1. Set PREFIX (obviously)
#   2. Set IFLEXDIR to point to the OPAM location of flexdll.h (flexdll:lib) - up to OCaml 4.03.0
#   3. Change LIBDIR to install to $PREFIX/lib/ocaml (default for Windows is just lib)
#   4. Change DISTRIB to install to the build directory (i.e. don't install) - up to OCaml 4.02.0
#   5. Configure Tcl/Tk - up to OCaml 4.02.0
#   6. Include -static-libgcc for mingw port - up to OCaml 4.02.0
#   7. Remove the detection for a system flexlink to force bootstrapping - OCaml 4.03.0 only
TRANSFORMS=(-e "s/^PREFIX=[^\r]*/PREFIX=$PREFIX/" \
            -e "s/\(\/lib\)\(\r\)\?$/\1\/ocaml\2/" \
            -e "s/^RUNTIMED=[^\r]*/RUNTIMED=$RUNTIMED/" \
            -e "s/^FLAMBDA=[^\r]*/FLAMBDA=$FLAMBDA/" \
            -e "s/^SAFE_STRING=[^\r]*/SAFE_STRING=$SAFE_STRING/")
if (( BUILD_VER < 4030 )) ; then
  TRANSFORMS+=(-e "s/^\\(IFLEXDIR=-I.\\).*\\([^\r]\r\?\\)/\\1$FLEXDIR\2/")
  if (( BUILD_VER < 4020 )) ; then
    TRANSFORMS+=(-e "s/DISTRIB=[^\r]*/DISTRIB=config/")
    TRANSFORMS+=(-e "s/^TK_DEFS=[^\r]*/TK_DEFS=-I$TK_DEFS/" \
                  -e "s/^TK_LINK=[^\r]*/TK_LINK=$TK_LINK/")
    if [[ $PORT = "mingw" ]] ; then
      TRANSFORMS+=(-e "s/FLEXLINK=[^\r]*/& -link -static-libgcc/")
    fi
  fi
elif (( BUILD_VER == 4030 )) ; then
  TRANSFORMS+=(-e "s/:=[^\r]*/=/")
fi
sed "${TRANSFORMS[@]}" config/Makefile.$PORT > config/Makefile

mv config/s-nt.h config/s.h
mv config/m-nt.h config/m.h

if (( BUILD_VER < 4000 )) ; then
  # Patches to ocamltopwin:
  #   1. Install OCamlWin.exe to BINDIR instead of PREFIX
  #   2. Disable the use of the registry to store the location of ocaml.exe
  #   3. Hardcode the location of ocaml.exe and ocaml:lib
  sed -i -e "s/PREFIX/BINDIR/" win32caml/Makefile
  sed -i -e "/GetOcamlPath/d" \
         -e "s/OcamlPath.*[^;]/& = \"$WINPREFIX\\\\\\\\bin\\\\\\\\ocaml.exe\"/" \
         -e "s/LibDir.*[^;]/& = \"$WINPREFIX\\\\\\\\lib\\\\\\\\ocaml\"/" win32caml/ocaml.c
fi

if (( BUILD_VER >= 4020 )) ; then
  if (( BUILD_VER <= 4030 )) ; then
    # This disables the installation of README, LICENCE and CHANGES files to the switch root
    sed -i -e "/INSTALL_DISTRIB/d" Makefile.nt
  fi
  if (( BUILD_VER >= 4030 )) ; then
    # Copy the FlexDLL sources ready for bootstrapping
    mkdir -p flexdll
    cp $(cygpath -m "$FLEXDLL_PATH")/* flexdll/
  fi
fi

# Activate GPR#465
make -f Makefile.nt patches

# Copy Makefile.nt to Makefile so that commands don't have to be invoked as make -f Makefile.nt
cp -f Makefile.nt Makefile
