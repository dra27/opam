#!/bin/sh -e

V=ocaml-4.02.1
URL=http://caml.inria.fr/pub/distrib/ocaml-4.02/${V}.tar.gz
if command -v curl > /dev/null ; then
  CURL="curl -OL"
else
  CURL=wget
fi
mkdir -p bootstrap
cd bootstrap
if [ ! -e ${V}.tar.gz ]; then
  cp ../src_ext/archives/${V}.tar.gz . || ${CURL} ${URL}
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
  FV=0.34
  cd ..
  if [ ! -e flexdll-bin-${FV}.zip ]; then
    cp ../src_ext/archives/flexdll-bin-${FV}.zip . || ${CURL} http://alain.frisch.fr/flexdll/flexdll-bin-${FV}.zip
  fi
  mkdir -p bin
  unzip -od bin/ flexdll-bin-${FV}.zip
  cd ${V}
  CPREFIX=`cd .. ; pwd`/bin
  PATH="${PATH_PREPEND}:${CPREFIX}:${PATH}" Lib="${LIB_PREPEND}${Lib}" Include="${INC_PREPEND}${Include}" make -f Makefile.nt world opt opt.opt install
else
  ./configure -prefix `pwd`/../ocaml
  make world opt
  make install
fi
