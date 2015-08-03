#!/bin/sh -e

V=ocaml-4.04.0
URL=http://caml.inria.fr/pub/distrib/ocaml-4.04/${V}.tar.gz
if command -v curl > /dev/null; then
  CURL="curl -OL"
elif command -v wget > /dev/null; then
  CURL=wget
else
  echo "This script requires curl or wget"
  exit 1
fi
mkdir -p bootstrap
cd bootstrap
if [ ! -e ${V}.tar.gz ]; then
  cp ../src_ext/archives/${V}.tar.gz . 2>/dev/null || ${CURL} ${URL}
fi
tar -zxf ${V}.tar.gz
cd ${V}
if [ -n "$1" -a -n "${COMSPEC}" -a -x "${COMSPEC}" ] ; then
  PATH_PREPEND=
  LIB_PREPEND=
  INC_PREPEND=

  case "$1" in
    "mingw"|"mingw64")
      BUILD=$1
    ;;
    "msvc")
      BUILD=$1
      if ! command -v ml > /dev/null ; then
        eval `../../shell/findwinsdk x86`
        if [ -n "${SDK}" ] ; then
          PATH_PREPEND="${SDK}"
          LIB_PREPEND="${SDK_LIB};"
          INC_PREPEND="${SDK_INC};"
        fi
      fi
    ;;
    "msvc64")
      BUILD=$1
      if ! command -v ml64 > /dev/null ; then
        eval `../../shell/findwinsdk x64`
        if [ -n "${SDK}" ] ; then
          PATH_PREPEND="${SDK}"
          LIB_PREPEND="${SDK_LIB};"
          INC_PREPEND="${SDK_INC};"
        fi
      fi
    ;;
    *)
      if [ "$1" != "auto" ] ; then
        echo "Compiler architecture $1 not recognised -- mingw64, mingw, msvc64, msvc (or auto)"
      fi
      if [ -n "${PROCESSOR_ARCHITEW6432}" -o "${PROCESSOR_ARCHITECTURE}" = "AMD64" ] ; then
        TRY64=1
      else
        TRY64=0
      fi

      if [ ${TRY64} -eq 1 ] && command -v x86_64-w64-mingw32-gcc > /dev/null ; then
        BUILD=mingw64
      elif command -v i686-w64-mingw32-gcc > /dev/null ; then
        BUILD=mingw
      elif [ ${TRY64} -eq 1 ] && command -v ml64 > /dev/null ; then
        BUILD=msvc64
        PATH_PREPEND=`bash ../../shell/check_linker`
      elif command -v ml > /dev/null ; then
        BUILD=msvc
        PATH_PREPEND=`bash ../../shell/check_linker`
      else
        if [ ${TRY64} -eq 1 ] ; then
          BUILD=msvc64
          BUILD_ARCH=x64
        else
          BUILD=msvc
          BUILD_ARCH=x86
        fi
        eval `../../shell/findwinsdk ${BUILD_ARCH}`
        if [ -z "${SDK}" ] ; then
          echo "No appropriate C compiler was found -- unable to build OCaml"
          exit 1
        else
          PATH_PREPEND="${SDK}"
          LIB_PREPEND="${SDK_LIB};"
          INC_PREPEND="${SDK_INC};"
        fi
      fi
    ;;
  esac
  if [ -n "${PATH_PREPEND}" ] ; then
    PATH_PREPEND="${PATH_PREPEND}:"
  fi
  PREFIX=`cd .. ; pwd | cygpath -f - -m | sed -e 's/\\//\\\\\\//g'`
  sed -e "s/^PREFIX=.*/PREFIX=${PREFIX}/" config/Makefile.${BUILD} > config/Makefile
  mv config/s-nt.h config/s.h
  mv config/m-nt.h config/m.h
  FV=0.35
  cd ..
  if [ ! -e flexdll-${FV}.tar.gz ]; then
    cp ../src_ext/archives/flexdll-${FV}.tar.gz . 2>/dev/null || ${CURL} http://alain.frisch.fr/flexdll/flexdll-${FV}.tar.gz
  fi
  cd ${V}
  tar -xzf ../flexdll-${FV}.tar.gz
  rm -rf flexdll
  mv flexdll-${FV} flexdll
  CPREFIX=`cd .. ; pwd`/bin
  PATH="${PATH_PREPEND}:${CPREFIX}:${PATH}" Lib="${LIB_PREPEND}${Lib}" Include="${INC_PREPEND}${Include}" make -f Makefile.nt flexdll world.opt install
  echo "export PATH:=${PATH_PREPEND}:${CPREFIX}:\$(PATH)" > ../../src_ext/Makefile.config
  echo "export Lib:=${LIB_PREPEND}\$(Lib)" >> ../../src_ext/Makefile.config
  echo "export Include:=${INC_PREPEND}\$(Include)" >> ../../src_ext/Makefile.config
  echo "export OCAMLLIB=" >> ../../src_ext/Makefile.config
else
  ./configure -prefix "`pwd`/../ocaml"
  make world opt
  make install
fi
