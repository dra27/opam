#/usr/bin/env sh

OPAMROOT="${OPAMROOT:-$HOME/.opam}"

OPAM2=1
if command -v opam > /dev/null 2>&1 ; then
  case "$(opam --version)" in
  1.2.2)
    echo "opam 1.2.2 found" >&2
    OPAM2=0
    ;;
  1.2.*)
    echo "WARNING! opam 1.2 prior to 1.2.2 found - you should upgrade to at least 1.2.2" >&2
    OPAM2=0
    ;;
  1.*)
    echo "WARNING! Your version of opam is too old for this scan - please upgrade it to at least 1.2.2" >&2
    exit 2
    ;;
  2.*)
    echo "opam 2.x found" >&2
    ;;
  *)
    echo "Unable to identify the version of opam - aborting" >&2
    exit 2
    ;;
  esac
else
  if [ -d $OPAMROOT ] ; then
    echo "WARNING! opam command not found, but \"$OPAMROOT\" exists - will check anyway." >&2
  else
    echo "opam does not appear to be installed or initialised." >&2
    exit 2
  fi
fi

echo "Scanning $HOME for opam roots..." >&2
find $HOME -type f -name config -exec sh -c '
  export OPAMROOT="{}"
  if grep -q " *switch *:" "$OPAMROOT" ; then
    if grep -qx " *opam-version *: *\"1\.2\" *" "$OPAMROOT" ; then
      cd "$(dirname "$OPAMROOT")"
      echo ". opam 1.2 root found in $PWD" >&2
      if grep -qxF "camlp5 7.03" "system/installed" 2>/dev/null ; then
        echo ".. The system switch of this root HAS camlp5 7.03 installed" >&2
        if grep -q "make \"uninstall\"" repo/*/packages/camlp5/camlp5.7.03/opam 2>/dev/null ; then
          export OPAMROOT="$PWD"
          eval $(opam config env --switch=system --shell=sh)
          echo ".. At least one package repository appears to contain a faulty camlp5.7.03 package" >&2
          if [ $(ocamlc -version) = "4.06.1" ] ; then
            echo "... The system compiler is OCaml 4.06.1" >&2
            echo "... DO NOT RUN ANY opam COMMANDS WITH THIS ROOT" >&2
            echo "... Please see http://somewhere.com for more information" >&2
          else
            echo "... The system compiler is not OCaml 4.06.1" >&2
            echo "... You should run opam update for this root" >&2
          fi
        else
          echo ".. No camlp5.7.03 packages seem to contain the unguarded make \"uninstall\"" >&2
        fi
      else
        echo ".. The system switch of this root appears not to have camlp5 7.03 installed" >&2
      fi
    elif grep -q " *opam-version *: *\"2\." "$OPAMROOT" ; then
      OPAMROOT=$(dirname "$OPAMROOT")
      echo ". opam 2.0 root found in $OPAMROOT" >&2
    fi
  fi
' \;
