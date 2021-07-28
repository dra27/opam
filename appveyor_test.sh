#!/bin/bash

opam init -y -a --compiler=ocaml.4.12.0 git+https://github.com/ocaml/opam-repository.git#$OPAM_TEST_REPO_SHA
eval $(opam config env)
opam install -y -v ocamlfind
