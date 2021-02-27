Working version changelog, used as a base for the changelog and the release
note.
Possibly scripts breaking changes are prefixed with ✘.
New option/command/subcommand are prefixed with ◈.

## Version
  *

## Global CLI
  *

## Init
  *

## Config Upgrade
  *

## Install
  * Don't patch twice [#4529 @rjbou]

## Remove
  *

## Switch
  * Don't exclude base packages from rebuilds (made some sense in opam 2.0
    with base packages but doesn't make sense with 2.1 switch invariants) [#4569 @dra27]

## Pin
  * Don't look for lock files for pin depends [#4511 @rjbou - fix #4505]
  * Don't ask for confirmation for pinning base packages (similarly makes no
    sense with 2.1 switch invariants) [#4571 @dra27]

## List
  *

## Show
  *

## Var
  *

## Option
  *

## Lint
  * fix W59 & E60 with conf flag handling (no url required) [#4550 @rjbou - fix #4549]

## Lock
  *

## Opamfile
  * Fix `features` parser [#4507 @rjbou]
  * Rename `hidden-version` to `avoid-version` [#4527 @dra27]

## External dependencies
  * Handle macport variants [#4509 @rjbou - fix #4297]
  * Always upgrade all the installed packages when installing a new package on Archlinux [#4556 @kit-ty-kate]

## Sandbox
  * Fix the conflict with the environment variable name used by dune [#4535 @smorimoto - fix ocaml/dune#4166]
  * Kill builds on Ctrl-C with bubblewrap [#4530 @kit-ty-kate - fix #4400]

## Repository management
  *

## VCS
  *

## Build
  * Fix opam-devel's tests on platforms without openssl, GNU-diff and a system-wide ocaml [#4500 @kit-ty-kate]
  * Restrict `extlib` and `dose` version [#4517 @kit-ty-kate]
  * Restrict to opam-file-format 2.1.2 [#4495 @rjbou]
  * Switch to newer version of MCCS (based on newer GLPK) for src_ext [#4559 @AltGr]

## Infrastructure
  * Release scripts: switch to OCaml 4.10.2 by default, add macos/arm64 builds by default [#4559 @AltGr]

## Admin
  *

## Opam installer
  *

## State
  *

# Opam file format
  *

## Solver
  * Fix Cudf preprocessing [#4534 @AltGr]

## Client
  *

## Internal
  *

## Test
  *

## Shell
  *

## Doc
  * Install page: add OSX arm64 [#4506 @eth-arm]
  * Document the default build environment variables [#4496 @kit-ty-kate]
