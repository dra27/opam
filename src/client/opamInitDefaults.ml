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
  path = "opam.ocaml.org";
  hash = None;
  backend = `http;
}

let default_compiler =
  OpamFormula.ors [
    OpamFormula.Atom (OpamPackage.Name.of_string "ocaml-system",
                      OpamFormula.Atom
                        (`Geq, OpamPackage.Version.of_string "4.01.0"));
    OpamFormula.Atom (OpamPackage.Name.of_string "ocaml-base-compiler",
                      OpamFormula.Empty);
  ]

let eval_variables = [
  OpamVariable.of_string "arch", ["uname"; "-m"],
  "Host architecture, as returned by 'uname -m'";
  OpamVariable.of_string "sys-ocaml-version", ["ocamlc"; "-vnum"],
  "OCaml version present on your system independently of opam, if any";
  OpamVariable.of_string "sys-ocaml-arch", ["sh"; "-c"; "ocamlc -config | tr -d '\\r' | grep '^architecture: ' | sed -e 's/.*: //' -e 's/i386/i686/' -e 's/amd64/x86_64/'"],
  "Target architecture of the OCaml compiler present on your system";
  OpamVariable.of_string "sys-ocaml-cc", ["sh"; "-c"; "ocamlc -config | tr -d '\\r' | grep '^ccomp_type: ' | sed -e 's/.*: //'"],
  "Host C Compiler type of the OCaml compiler present on your system";
  OpamVariable.of_string "sys-ocaml-libc", ["sh"; "-c"; "ocamlc -config | tr -d '\\r' | grep '^os_type: ' | sed -e 's/.*: //' -e 's/Win32/msvc/' -e '/^msvc$/!s/.*/libc/'"],
  "Host C Runtime Library type of the OCaml compiler present on your system";
]

let switch_variables =
  let open OpamTypes in
  let ocaml_system =
    FIdent ([Some (OpamPackage.Name.of_string "ocaml-system")], OpamVariable.of_string "installed", None)
  in
  let not_ocaml_system =
    FNot ocaml_system
  in
  let is_base_windows =
    let os = FIdent ([], OpamVariable.of_string "os", None) in
    let win32 = FString "win32" in
    fun op -> FAnd (not_ocaml_system, FOp (os, op, win32))
  in
  let switch_var_name name = OpamVariable.of_string ("switch-"^name) in
  let sys_var name description =
    ((switch_var_name name, S (Printf.sprintf "%%{sys-ocaml-%s}%%" name), description), Some ocaml_system)
  in
  let var ?(filter=not_ocaml_system) name value description =
    ((switch_var_name name, S value, description), Some filter)
  in
  [sys_var "arch" "Switch architecture (taken from system OCaml compiler)";
   sys_var "cc" "Switch C compiler type (taken from system OCaml compiler)";
   sys_var "libc" "Switch C runtime flavour (taken from system OCaml compiler)";
   var "arch" "%{arch}%" "Switch architecture";
   var "cc" "cc" "Switch C compiler type";
   var ~filter:(is_base_windows `Eq) "libc" "msvc" "Switch C runtime flavour";
   var ~filter:(is_base_windows `Neq) "libc" "libc" "Switch C runtime flavour"]

module I = OpamFile.InitConfig

let switch_defaults =
  OpamFile.SwitchDefaults.with_switch_variables switch_variables OpamFile.SwitchDefaults.empty

let init_config =
  I.empty |>
  I.with_repositories
    [OpamRepositoryName.of_string "default", (repository_url, None)] |>
  I.with_default_compiler default_compiler |>
  I.with_eval_variables eval_variables |>
  I.with_switch_defaults switch_defaults
