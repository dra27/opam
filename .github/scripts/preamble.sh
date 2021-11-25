
CWD=$PWD
CACHE=~/.cache
CACHE=`eval echo $CACHE`
echo "Cache -> $CACHE"
OCAML_LOCAL=$CACHE/ocaml-local
OPAM_LOCAL=$CACHE/opam-local
# Obviously Windows-only. Perhaps can be done with a filter instead?
#PATH='/usr/bin:/cygdrive/c/Windows/system32:/cygdrive/c/Windows:/cygdrive/c/Windows/System32/Wbem:/cygdrive/c/Windows/System32/WindowsPowerShell/v1.0:/cygdrive/c/Windows/System32/OpenSSH'
PATH=$OPAM_LOCAL/bin:$OCAML_LOCAL/bin:$PATH; export PATH

OPAM_COLD=${OPAM_COLD:-0}
OPAM_TEST=${OPAM_TEST:-0}
OPAM_UPGRADE=${OPAM_UPGRADE:-0}

OPAM_REPO_MAIN=https://github.com/ocaml/opam-repository.git

OPAM12CACHE=`eval echo $OPAM12CACHE`
OPAMBSROOT=`eval echo $OPAMBSROOT`

OPAMBSSWITCH=opam-build

export OPAMCONFIRMLEVEL=unsafe-yes

case $GITHUB_EVENT_NAME in
  pull_request)
    BRANCH=$GITHUB_HEAD_REF
    ;;
  push)
    BRANCH=${GITHUB_REF##*/}
    ;;
  *)
  echo -e "Not handled event"
  BRANCH=master
esac

git config --global user.email "gha@example.com"
git config --global user.name "Github Actions CI"
git config --global gc.autoDetach false

# used only for TEST jobs
init-bootstrap () {
  if [ "$OPAM_TEST" = "1" ] || [ -n "$SOLVER" ]; then
    set -e
    export OPAMROOT=$OPAMBSROOT
    # The system compiler will be picked up
    if [ "$OPAM_REPO" != "$OPAM_REPO_MAIN" ] && [ "$OPAM_REPO.git" != "$OPAM_REPO_MAIN" ] ; then
      opam init --no-setup git+$OPAM_REPO_MAIN#$OPAM_REPO_SHA
    else
      opam init --no-setup git+file://$HOME/opam-repository#$OPAM_REPO_SHA
    fi
    eval $(opam env)
#    opam update
    CURRENT_SWITCH=$(opam var switch)
    if [[ $CURRENT_SWITCH != "default" ]] ; then
      opam switch default
      eval $(opam env)
      opam switch remove $CURRENT_SWITCH
    fi

    opam switch create $OPAMBSSWITCH ocaml-system
    eval $(opam env)
    # extlib is installed, since UChar.cmi causes problems with the search
    # order. See also the removal of uChar and uTF8 in src_ext/jbuild-extlib-src
    opam install . --deps-only

    rm -f "$OPAMBSROOT"/log/*
  fi
}
