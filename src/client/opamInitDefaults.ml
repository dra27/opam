(**************************************************************************)
(*                                                                        *)
(*    Copyright 2016 OCamlPro                                             *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

let repository_url = {
  OpamUrl.
  transport = "https";
  path = "github.com/dra27/opam-repository";
  hash = Some "windows";
  backend = `git;
}

let default_compiler =
  OpamFormula.ors [
    OpamFormula.Atom (OpamPackage.Name.of_string "ocaml-system",
                      OpamFormula.Atom
                        (`Geq, OpamPackage.Version.of_string "4.02.3"));
    OpamFormula.Atom (OpamPackage.Name.of_string "ocaml-base-compiler",
                      OpamFormula.Empty);
  ]

let eval_variables = [
  OpamVariable.of_string "sys-ocaml-version", ["ocamlc"; "-vnum"],
  "OCaml version present on your system independently of opam, if any";
  OpamVariable.of_string "sys-ocaml-arch", ["sh"; "-c"; "ocamlc -config | tr -d '\\r' | grep '^architecture: ' | sed -e 's/.*: //' -e 's/i386/i686/' -e 's/amd64/x86_64/'"],
  "Target architecture of the OCaml compiler present on your system";
  OpamVariable.of_string "sys-ocaml-cc", ["sh"; "-c"; "ocamlc -config | tr -d '\\r' | grep '^ccomp_type: ' | sed -e 's/.*: //'"],
  "Host C Compiler type of the OCaml compiler present on your system";
  OpamVariable.of_string "sys-ocaml-libc", ["sh"; "-c"; "ocamlc -config | tr -d '\\r' | grep '^os_type: ' | sed -e 's/.*: //' -e 's/Win32/msvc/' -e '/^msvc$/!s/.*/libc/'"],
  "Host C Runtime Library type of the OCaml compiler present on your system";
]

module I = OpamFile.InitConfig

let switch_defaults =
  OpamFile.SwitchDefaults.empty

let init_config =
  I.empty |>
  I.with_repositories
    [OpamRepositoryName.of_string "default", (repository_url, None)] |>
  I.with_default_compiler default_compiler |>
  I.with_eval_variables eval_variables |>
  I.with_switch_defaults switch_defaults
