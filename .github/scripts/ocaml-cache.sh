#!/bin/bash -xue

. .github/scripts/preamble.sh

shell/msvs-detect --all

# XXX Need to select the arch properly
#eval $(shell/msvs-detect --arch=x64)
#export PATH="$MSVS_PATH$PATH"
#export LIB="$MSVS_LIB${LIB:-}"
#export INCLUDE="$MSVS_INC${INCLUDE:-}"
#echo "Using $MSVS_NAME x64"

FLEXDLL_VERSION=0.39

curl -sLO "https://caml.inria.fr/pub/distrib/ocaml-${OCAML_VERSION%.*}/ocaml-$OCAML_VERSION.tar.gz"
curl -sLO "https://github.com/alainfrisch/flexdll/archive/refs/tags/$FLEXDLL_VERSION.tar.gz"

tar -xzf "ocaml-$OCAML_VERSION.tar.gz"

cd "ocaml-$OCAML_VERSION"
tar -xzf "../$FLEXDLL_VERSION.tar.gz"
rm -rf flexdll
mv "flexdll-$FLEXDLL_VERSION" flexdll

if [[ $OPAM_TEST -ne 1 ]] ; then
  if [[ -e configure.ac ]]; then
    CONFIGURE_SWITCHES="--disable-debugger --disable-debug-runtime"
    if [ "$SOLVER" != "z3" ]; then
      CONFIGURE_SWITCHES="$CONFIGURE_SWITCHES --disable-ocamldoc"
    fi
    if [[ ${OCAML_VERSION%.*} = '4.08' ]]; then
      CONFIGURE_SWITCHES="$CONFIGURE_SWITCHES --disable-graph-lib"
    fi
    if [[ -n $HOST ]]; then
      CONFIGURE_SWITCHES="$CONFIGURE_SWITCHES --host=$HOST"
    fi
  else
    CONFIGURE_SWITCHES="-no-graph -no-debugger"
    if [ "$SOLVER" != "z3" ]; then
      CONFIGURE_SWITCHES="$CONFIGURE_SWITCHES -no-ocamldoc"
    fi
    if [[ "$OCAML_VERSION" != "4.02.3" ]] ; then
      CONFIGURE_SWITCHES="$CONFIGURE_SWITCHES -no-ocamlbuild"
    fi
  fi
fi

if ! ./configure --prefix $OCAML_LOCAL ${CONFIGURE_SWITCHES:-} ; then
  cat config.log
  exit 2
fi

make -j 4 world.opt

make install

cd ..
rm -rf "ocaml-$OCAML_VERSION"
