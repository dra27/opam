#!/bin/sh -e

GEN_CONFIG_ONLY=${GEN_CONFIG_ONLY:-0}

if command -v curl > /dev/null; then
  CURL="curl -OLSfs"
elif command -v wget > /dev/null; then
  CURL=wget
else
  echo "This script requires curl or wget"
  exit 1
fi
mkdir -p bootstrap
cd bootstrap
URL=`sed -ne 's/URL_ocaml *= *//p' ../src_ext/Makefile | tr -d '\r'`
MD5=`sed -ne 's/MD5_ocaml *= *//p' ../src_ext/Makefile | tr -d '\r'`
V=`echo ${URL}| sed -e 's|.*/\([^/]*\)\.tar\.gz|\1|'`
FV_URL=`sed -ne 's/URL_flexdll *= *//p' ../src_ext/Makefile | tr -d '\r'`
FLEXDLL=`echo ${FV_URL}| sed -e 's|.*/\([^/]*\)|\1|'`
if [ ! -e ${V}.tar.gz ]; then
  cp ../src_ext/archives/${V}.tar.gz . 2>/dev/null || ${CURL} ${URL}
fi

ACTUALMD5=`openssl md5 ${V}.tar.gz  2> /dev/null | cut -f 2 -d ' '`
if [ "$ACTUALMD5" != "$MD5" ]; then
  echo "Bad checksum for ${V}.tar.gz:"
  echo "- expected: $MD5"
  echo "- actual:   $ACTUALMD5"
  exit 2
fi

if [ ${GEN_CONFIG_ONLY} -eq 0 ] ; then
  tar -zxf ${V}.tar.gz
else
  mkdir -p ${V}
fi
V="ocaml-$V"
cd ${V}
PATH_PREPEND=
LIB_PREPEND=
INC_PREPEND=
if [ -n "$1" -a -n "${COMSPEC}" -a -x "${COMSPEC}" ] ; then
  case "$(uname -m)" in
    'i686')
      BUILD=i686-pc-cygwin
    ;;
    'x86_64')
      BUILD=x86_64-pc-cygwin
    ;;
  esac
  case "$1" in
    "mingw")
      HOST=i686-w64-mingw32
    ;;
    "mingw64")
      HOST=x86_64-w64-mingw32
    ;;
    "msvc")
      HOST=i686-pc-windows
      if ! command -v ml > /dev/null ; then
        eval `../../shell/msvs-detect --arch=x86`
        if [ -n "${MSVS_NAME}" ] ; then
          PATH_PREPEND="${MSVS_PATH}"
          LIB_PREPEND="${MSVS_LIB};"
          INC_PREPEND="${MSVS_INC};"
        fi
      fi
    ;;
    "msvc64")
      HOST=x86_64-pc-windows
      if ! command -v ml64 > /dev/null ; then
        eval `../../shell/msvs-detect --arch=x64`
        if [ -n "${MSVS_NAME}" ] ; then
          PATH_PREPEND="${MSVS_PATH}"
          LIB_PREPEND="${MSVS_LIB};"
          INC_PREPEND="${MSVS_INC};"
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
        HOST=x86_64-w64-mingw32
      elif command -v i686-w64-mingw32-gcc > /dev/null ; then
        HOST=i686-w64-mingw32
      elif [ ${TRY64} -eq 1 ] && command -v ml64 > /dev/null ; then
        HOST=x86_64-pc-windows
        PATH_PREPEND=`bash ../../shell/check_linker`
      elif command -v ml > /dev/null ; then
        HOST=i686-pc-windows
        PATH_PREPEND=`bash ../../shell/check_linker`
      else
        if [ ${TRY64} -eq 1 ] ; then
          HOST=x86_64-pc-windows
          HOST_ARCH=x64
        else
          HOST=i686-pc-windows
          HOST_ARCH=x86
        fi
        eval `../../shell/msvs-detect --arch=${HOST_ARCH}`
        if [ -z "${MSVS_NAME}" ] ; then
          echo "No appropriate C compiler was found -- unable to build OCaml"
          exit 1
        else
          PATH_PREPEND="${MSVS_PATH}"
          LIB_PREPEND="${MSVS_LIB};"
          INC_PREPEND="${MSVS_INC};"
        fi
      fi
    ;;
  esac
  if [ -n "${PATH_PREPEND}" ] ; then
    PATH_PREPEND="${PATH_PREPEND}:"
  fi
  PREFIX=`cd .. ; pwd`/ocaml
  WINPREFIX=`echo ${PREFIX} | cygpath -f - -m`
  if [ ${GEN_CONFIG_ONLY} -eq 0 ] ; then
    # --disable-ocamldoc can change to --disable-stdlib-manpages when bumped to 4.11
    PATH="${PATH_PREPEND}${PREFIX}/bin:${PATH}" Lib="${LIB_PREPEND}${Lib}" Include="${INC_PREPEND}${Include}" ./configure --prefix "$WINPREFIX" --build=$BUILD --host=$HOST --disable-ocamldoc
  fi
  cd ..
  if [ ! -e ${FLEXDLL} ]; then
    cp ../src_ext/archives/${FLEXDLL} . 2>/dev/null || ${CURL} ${FV_URL}
  fi
  cd ${V}
  if [ ${GEN_CONFIG_ONLY} -eq 0 ] ; then
    tar -xzf ../${FLEXDLL}
    rm -rf flexdll
    mv flexdll-* flexdll
    PATH="${PATH_PREPEND}${PREFIX}/bin:${PATH}" Lib="${LIB_PREPEND}${Lib}" Include="${INC_PREPEND}${Include}" make -j flexdll
    PATH="${PATH_PREPEND}${PREFIX}/bin:${PATH}" Lib="${LIB_PREPEND}${Lib}" Include="${INC_PREPEND}${Include}" make -j world.opt
    PATH="${PATH_PREPEND}${PREFIX}/bin:${PATH}" Lib="${LIB_PREPEND}${Lib}" Include="${INC_PREPEND}${Include}" make install
  fi
  OCAMLLIB=${WINPREFIX}/lib/ocaml
else
  PREFIX=`cd .. ; pwd`/ocaml
  if [ ${GEN_CONFIG_ONLY} -eq 0 ] ; then
    ./configure -prefix "${PREFIX}"
    ${MAKE:-make} world opt.opt
    ${MAKE:-make} install
  fi
  OCAMLLIB=${PREFIX}/lib/ocaml
fi

if [ ${GEN_CONFIG_ONLY} -eq 0 ] ; then
  echo "${URL} ${FV_URL}" > ../installed-tarball
fi

# Generate src_ext/Makefile.config
PATH_PREPEND=`echo "${PATH_PREPEND}" | sed -e 's/#/\\\\#/g' -e 's/\\$/$$/g'`
echo "export PATH:=${PATH_PREPEND}${PREFIX}/bin:\$(PATH)" > ../../src_ext/Makefile.config
if [ -n "${LIB_PREPEND}" ] ; then
  LIB_PREPEND=`echo ${LIB_PREPEND} | sed -e 's/#/\\\\#/g' -e 's/\\$/$$/g'`
  echo "export Lib:=${LIB_PREPEND}\$(Lib)" >> ../../src_ext/Makefile.config
fi
if [ -n "${INC_PREPEND}" ] ; then
  INC_PREPEND=`echo ${INC_PREPEND} | sed -e 's/#/\\\\#/g' -e 's/\\$/$$/g'`
  echo "export Include:=${INC_PREPEND}\$(Include)" >> ../../src_ext/Makefile.config
fi
echo "export OCAMLLIB=${OCAMLLIB}" >> ../../src_ext/Makefile.config
