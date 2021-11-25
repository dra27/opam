#!/bin/bash -xue

. .github/scripts/main/preamble.sh

if [[ $1 = 'true' ]] ; then
  if [[ -e $OCAML_LOCAL/cache.tar ]] ; then
    tar -C "$OCAML_LOCAL" -pxf "$OCAML_LOCAL/cache.tar"
    rm "$OCAML_LOCAL/cache.tar"
  fi
  exit
fi

#shell/msvs-detect --all

ls -l /usr/bin/*tar*
ls -l /usr/bin/*git*

# XXX Need to select the arch properly
eval $(shell/msvs-detect --arch=x64)
export PATH="$MSVS_PATH$PATH"
export LIB="$MSVS_LIB${LIB:-}"
export INCLUDE="$MSVS_INC${INCLUDE:-}"
echo "Using $MSVS_NAME x64"

FLEXDLL_VERSION=0.40

curl -sLO "https://caml.inria.fr/pub/distrib/ocaml-${OCAML_VERSION%.*}/ocaml-$OCAML_VERSION.tar.gz"
curl -sLO "https://github.com/alainfrisch/flexdll/archive/refs/tags/$FLEXDLL_VERSION.tar.gz"

tar -xzf "ocaml-$OCAML_VERSION.tar.gz"

cd "ocaml-$OCAML_VERSION"
tar -xzf "../$FLEXDLL_VERSION.tar.gz"
rm -rf flexdll
mv "flexdll-$FLEXDLL_VERSION" flexdll

if [[ $OPAM_TEST -ne 1 ]] ; then
  if [[ -e configure.ac ]]; then
    CONFIGURE_SWITCHES="--disable-debugger --disable-debug-runtime --disable-ocamldoc --disable-installing-bytecode-programs  --disable-installing-source-artifacts"
    if [[ ${OCAML_VERSION%.*} = '4.08' ]]; then
      CONFIGURE_SWITCHES="$CONFIGURE_SWITCHES --disable-graph-lib"
    fi
    if [[ -n $HOST ]]; then
      CONFIGURE_SWITCHES="$CONFIGURE_SWITCHES --host=$HOST"
    fi
  else
    CONFIGURE_SWITCHES="-no-graph -no-debugger -no-ocamldoc"
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
echo > "$OCAML_LOCAL/bin/ocamldoc" <<"EOF"
#!/bin/sh

echo 'ocamldoc is not supposed to be called'>&2
exit 1
EOF
chmod +x "$OCAML_LOCAL/bin/ocamldoc"

cd ..
rm -rf "ocaml-$OCAML_VERSION"

# XXX Windows runners only for this!
ls -l "$OCAML_LOCAL"
which tar
cd "$OCAML_LOCAL"
tar -C "$OCAML_LOCAL" -pcf cache.tar .
