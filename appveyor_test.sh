#!/bin/bash

opam init -y -a --compiler=ocaml.4.10.0
eval $(opam config env)
opam install -y -v ocamlfind
