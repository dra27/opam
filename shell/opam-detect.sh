#/usr/bin/env sh

OPAMROOT="${OPAMROOT:-$HOME/.opam}"

IS_OPAM2=1
if command -v opam > /dev/null 2>&1 ; then
  case "$(opam --version)" in
  1.2.2)
    echo "opam 1.2.2 found" >&2
    IS_OPAM2=0
    ;;
  1.2.*)
    echo "WARNING! opam 1.2 prior to 1.2.2 found - you should upgrade to at least 1.2.2" >&2
    IS_OPAM2=0
    ;;
  1.*)
    echo "WARNING! Your version of opam is too old for this scan - please upgrade it to at least 1.2.2" >&2
    exit 2
    ;;
  2.*)
    echo "opam 2.x found" >&2
    IS_OPAM2=1
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

export IS_OPAM2

echo "Scanning $HOME for opam roots..." >&2
find $HOME -type f -name config -exec sh -c '
  export OPAMROOT="$1"
  if grep -q " *switch *:" "$OPAMROOT" ; then
    if grep -qx " *opam-version *: *\"1\.2\" *" "$OPAMROOT" ; then
      cd "$(dirname "$OPAMROOT")"
      echo "opam 1.2 root found in $PWD" >&2
      if [ $(ocamlc -version) = "4.06.1" ] ; then
        OCAML4061=1
      else
        OCAML4061=0
      fi
      if grep -q "make \"uninstall\"" repo/*/packages/camlp5/camlp5.7.03/opam 2>/dev/null ; then
        export OPAMROOT="$PWD"
        eval $(opam config env --switch=system --shell=sh)
        CAMLP5_FAULTY=1
      else
        CAMLP5_FAULTY=0
      fi
      if grep -qxF "camlp5 7.03" "system/installed" 2>/dev/null ; then
        CAMLP5_INSTALLED=1
      else
        CAMLP5_INSTALLED=0
      fi
      CODE=$OCAML4061$CAMLP5_FAULTY$CAMLP5_INSTALLED
      # The following codes:
      # 000 - unaffected
      # 001 - unaffected
      # 010 - updatable (or opam2 format upgrade)
      # 011 - updatable (or opam2 format upgrade)
      # 100 - unaffected
      # 101 - unaffected
      # 110 - updatable (or opam2 format upgrade)
      # 111 - CRITICAL (or opam2 format upgrade)
      case $CODE in
        010)
          echo "camlp5 is faulty, but not installed in the system switch" >&2
          echo "" >&2
          if [ $IS_OPAM2 -eq 1 ] ; then
            echo "You are running opam 2 so you could just upgrade this root to opam 2 format" >&2
            echo "OPAM 1.2.2 is able to update this root, however" >&2
          else
            echo "You SHOULD run opam update on this root as soon as possible" >&2
          fi
          ;;
        011)
          echo "camlp5 is faulty and installed in the system switch" >&2
          echo "The system compiler is NOT OCaml 4.06.1" >&2
          echo "" >&2
          if [ $IS_OPAM2 -eq 1 ] ; then
            echo "You are running opam 2 so you could just upgrade this root to opam 2 format" >&2
            echo "OPAM 1.2.2 is able to update this root, however" >&2
          else
            echo "You SHOULD run opam update on this root as soon as possible" >&2
          fi
          ;;
        110)
          echo "camlp5 is faulty but not installed in the system" >&2
          echo "The system compiler is OCaml 4.06.1" >&2
          echo "" >&2
          if [ $IS_OPAM2 -eq 1 ] ; then
            echo "You are running opam 2 so you could just upgrade this root to opam 2 format" >&2
            echo "OPAM 1.2.2 is able to update this root, however" >&2
          else
            echo "Installing camlp5 in your system switch WILL ATTEMPT TO ERASE YOUR MACHINE" >&2
            echo "You SHOULD run opam update on this root as soon as possible" >&2
          fi
          ;;
        111)
          echo "camlp5 is faulty AND installed AND the system compiler is OCaml 4.06.1" >&2
          echo "" >&2
          if [ $IS_OPAM2 -eq 0 ] ; then
            echo "THIS ROOT CANNOT BE UPDATED OR UPGRADED. DO NOT ALLOW OPAM TO UPGRADE THE SYSTEM" >&2
            echo "COMPILER. DOING SO WILL ATTEMPT TO ERASE YOUR MACHINE" >&2
            echo "Please see https://github.com/ocaml/opam/issues/3322 for more information" >&2
          else
            echo "This root cannot be updated or upgraded by OPAM 0.2.2, but you are running opam2" >&2
            echo "You SHOULD upgrade this root to opam 2 format" >&2
            echo "OPAM 1.2.2 IS NOT ABLE TO UPDATE THIS ROOT" >&2
            echo "Please see https://github.com/ocaml/opam/issues/3322 for more information" >&2
          fi
          ;;
        *)
          echo "This root is NOT affected by this issue" >&2
          ;;
      esac
      echo ""
       # echo "... DO NOT RUN ANY opam COMMANDS WITH THIS ROOT" >&2
       # echo "... You should run opam update for this root" >&2
    elif grep -q " *opam-version *: *\"2\." "$OPAMROOT" ; then
      OPAMROOT=$(dirname "$OPAMROOT")
      echo ". opam 2.0 root found in $OPAMROOT" >&2
      echo ". opam 2.0 is NOT affected by this issue" >&2
    fi
  fi
' opam-detect.sh '{}' \;
