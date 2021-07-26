#!/bin/bash -xue

. .github/scripts/preamble.sh

export OPAMYES=1

rm -rf ~/.opam
opam init default git+https://github.com/ocaml/opam-repository.git#$OPAM_REPO_SHA --bare
opam switch create build ocaml-system
opam install ocaml-secondary-compiler
