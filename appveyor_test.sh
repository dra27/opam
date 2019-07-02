#!/bin/bash

opam init -y -a 'git+https://github.com/dra27/opam-repository.git#windows'
eval $(opam config env)
opam install -y -v ocamlfind
