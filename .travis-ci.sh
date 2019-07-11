#!/bin/bash -xue

TARGET="$1"; shift

case "$TARGET" in
  prepare)
    if [ "$TRAVIS_BUILD_STAGE_NAME" = "Hygiene" ] ; then
      exit 0
    fi

    exit 0
    ;;
  install)
    if [ "$TRAVIS_BUILD_STAGE_NAME" = "Hygiene" ] ; then
      exit 0
    fi

    exit 0
    ;;
  build)
    ;;

  *)
    echo "bad command $TARGET"; exit 1
esac

set +x
if [ "$TRAVIS_BUILD_STAGE_NAME" = "Hygiene" ] ; then
  if [ "$TRAVIS_EVENT_TYPE" = "pull_request" ] ; then
    TRAVIS_CUR_HEAD=${TRAVIS_COMMIT_RANGE%%...*}
    TRAVIS_PR_HEAD=${TRAVIS_COMMIT_RANGE##*...}
    DEEPEN=50
    while ! git merge-base "$TRAVIS_CUR_HEAD" "$TRAVIS_PR_HEAD" >& /dev/null
    do
      echo "Deepening $TRAVIS_BRANCH by $DEEPEN commits"
      git fetch origin --deepen=$DEEPEN "$TRAVIS_BRANCH"
      ((DEEPEN*=2))
    done
    TRAVIS_MERGE_BASE=$(git merge-base "$TRAVIS_CUR_HEAD" "$TRAVIS_PR_HEAD")
    if ! git diff "$TRAVIS_MERGE_BASE..$TRAVIS_PR_HEAD" --name-only --exit-code -- install.sh > /dev/null ; then
      echo "install.sh updated - checking it"
      eval $(grep '^\(VERSION\|TAG\|OPAM_BIN_URL_BASE\)=' install.sh)
      echo "TAG = $TAG"
      echo "OPAM_BIN_URL_BASE=$OPAM_BIN_URL_BASE"
      ARCHES=0
      ERROR=0
      while read -r key sha
      do
        ARCHES=1
        URL="$OPAM_BIN_URL_BASE$TAG/opam-$TAG-$key"
        echo "Checking $URL"
        check=$(curl -Ls "$URL" | sha512sum | cut -d' ' -f1)
        if [ "$check" = "$sha" ] ; then
          echo "Checksum as expected ($sha)"
        else
          echo -e "[\e[31mERROR\e[0m] Checksum downloaded: $check"
          echo -e "[\e[31mERROR\e[0m] Checksum install.sh: $sha"
          ERROR=1
        fi
      done < <(sed -ne 's/.*opam-\$TAG-\([^)]*\).*"\([^"]*\)".*/\1 \2/p' install.sh)
      if [ $ARCHES -eq 0 ] ; then
        echo "No sha512 checksums were detected in install.sh"
        echo "That can't be right..."
        exit 1
      elif [ $ERROR -eq 1 ] ; then
        exit 1
      fi
    fi
  fi
  exit 0
fi
set -x
