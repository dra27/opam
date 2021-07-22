#!/bin/bash -xue

. .github/scripts/preamble.sh

rm -rf src_ext/archives
export PATH=~/.cache/ocaml-local/bin:$PATH
which ocaml && export OCAML=`which ocaml` || true
make -C src_ext cache-archives
ls -al src_ext/archives
