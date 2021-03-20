#!/bin/bash -xue

. .github/scripts/preamble.sh

rm -f $OPAM_LOCAL/bin/opam-bootstrap
mkdir -p $OPAM_LOCAL/bin/

os=$( (uname -s || echo unknown) | awk '{print tolower($0)}')
if [ "$os" = "darwin" ] ; then
  os=macos
fi

pushd $OPAM_LOCAL/bin &> /dev/null
git clone https://github.com/ocaml/opam.git
cd opam
./configure
make lib-ext
make
cp opam $OPAM_LOCAL/bin/opam-bootstrap
cd ..
rm -rf opam
popd &> /dev/null

#wget -q -O $OPAM_LOCAL/bin/opam-bootstrap \
#  "https://github.com/ocaml/opam/releases/download/$OPAMBSVERSION/opam-$OPAMBSVERSION-$(uname -m)-$os"
cp -f $OPAM_LOCAL/bin/opam-bootstrap $OPAM_LOCAL/bin/opam
chmod a+x $OPAM_LOCAL/bin/opam

opam --version

if [[ -d $OPAMBSROOT ]] ; then
  init-bootstrap || { rm -rf $OPAMBSROOT; init-bootstrap; }
else
  init-bootstrap
fi
