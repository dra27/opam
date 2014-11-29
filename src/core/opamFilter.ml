(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2013 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved.This file is distributed under the terms of the   *)
(*  GNU Lesser General Public License version 3.0 with linking            *)
(*  exception.                                                            *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE.See the GNU General Public        *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

open OpamTypes
open OpamTypesBase

type env = full_variable -> variable_contents option

let rec to_string = function
  | FBool b    -> string_of_bool b
  | FString s  -> Printf.sprintf "%S" s
  | FIdent i   -> i
  | FOp(e,s,f) ->
    Printf.sprintf "%s %s %s"
      (to_string e) (string_of_relop s) (to_string f)
  | FAnd (e,f) -> Printf.sprintf "%s & %s" (to_string e) (to_string f)
  | FOr (e,f)  -> Printf.sprintf "%s | %s" (to_string e) (to_string f)
  | FNot e     -> Printf.sprintf "!%s" (to_string e)

(* Return the contents of a fully qualified variable *)
let contents_of_variable env v =
  let name = OpamVariable.Full.package v in
  let var = OpamVariable.Full.variable v in
  let name_str = OpamPackage.Name.to_string name in
  let names =
    try OpamMisc.split name_str '+'
    with e -> OpamMisc.fatal e; [name_str] in
  let names =
    try List.rev_map OpamPackage.Name.of_string names
    with Failure _ -> [] in
  let results =
    List.map (fun name ->
        env (OpamVariable.Full.create name var)
      ) names in
  let rec compose x y = match x,y with
    | S "enable" , S "enable"  -> S "enable"
    | S "disable", S "enable"
    | S "enable" , S "disable"
    | S "disable", S "disable" -> S "disable"
    | B b1       , B b2        -> B (b1 && b2)
    | S b, r     | r, S b      ->
      if b = "true" then compose (B true) r
      else if b = "false" then compose (B false) r
      else
        OpamGlobals.error_and_exit
          "Cannot compose %s and %s"
          (OpamVariable.string_of_variable_contents x)
          (OpamVariable.string_of_variable_contents y) in
  let compose_opt x y = match x, y with
    | Some x, Some y -> Some (compose x y)
    | None, _ | _, None -> None
  in
  match results with
  | [] -> None
  | h::t -> List.fold_left compose_opt h t

let contents_of_variable_exn env var =
  match contents_of_variable env var with
  | None  ->
    OpamGlobals.error "%s is not a valid variable."
      (OpamVariable.Full.to_string var);
    raise Not_found
  | Some c -> c

let substitute_ident env i =
  try
    let v = OpamVariable.Full.of_string i in
    contents_of_variable_exn env v
  with e ->
    OpamMisc.fatal e;
    OpamGlobals.warning "Invalid variable %s in filter" i;
    S i

(* Substitute the file contents *)
let substitute_file env f =
  let f = OpamFilename.of_basename f in
  let src = OpamFilename.add_extension f "in" in
  let contents = OpamFile.Subst.read src in
  let newcontents =
    OpamFile.Subst.replace contents
      (fun v ->
         try contents_of_variable_exn env v
         with Not_found ->
           OpamGlobals.msg "In %s" (OpamFilename.to_string OpamFilename.Native f);
           OpamVariable.S ("%{"^OpamVariable.Full.to_string v^"}%")) in
  OpamFile.Subst.write f newcontents

(* Substitue the string contents *)
let substitute_string env s =
  OpamFile.Subst.replace_string s (contents_of_variable_exn env)

exception Filter_type_error

let filter_type_error f actual expected =
  OpamGlobals.error
    "\'%s\' has type %s, but a env element of type %s was expected."
    (to_string f) actual expected;
  raise Filter_type_error

let string_of_variable_contents ident = function
  | S s -> s
  | B _ -> filter_type_error (FIdent ident) "bool" "string"

let bool_of_variable_contents ident = function
  | B b -> b
  | S _ -> filter_type_error (FIdent ident) "string" "bool"

let eval_to_string env = function
  | FString s -> substitute_string env s
  | FIdent s  -> string_of_variable_contents s (substitute_ident env s)
  | f         -> filter_type_error f "bool" "string"

let rec eval env v =
  try match v with
  | FBool b    -> b
  | FString s  -> substitute_string env s = "true"
  | FIdent s   -> bool_of_variable_contents s (substitute_ident env s)
  | FOp(e,s,f) ->
    (* We are supposed to compare version strings *)
    OpamFormula.check_relop s
      (Debian.Version.compare (eval_to_string env e) (eval_to_string env f))
  | FOr(e,f)  -> eval env e || eval env f
  | FAnd(e,f) -> eval env e && eval env f
  | FNot e    -> not (eval env e)
  with Not_found -> false (* XXX: need to implement correct "undef" value *)

let eval_opt env = function
  | None   -> true
  | Some f ->
    try eval env f
    with Not_found -> false

let arg env (a,f) =
  if eval_opt env f then
    try match a with
      | CString s -> Some (substitute_string env s)
      | CIdent i  ->
        Some (string_of_variable_contents i (substitute_ident env i))
    with e ->
      OpamMisc.fatal e;
      None
  else
    None

let command env (l, f) =
  if eval_opt env f then
    match OpamMisc.filter_map (arg env) l with
    | [] -> None
    | l  -> Some l
  else
    None

let commands env l =
  OpamMisc.filter_map (command env) l
