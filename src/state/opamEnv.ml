(**************************************************************************)
(*                                                                        *)
(*    Copyright 2012-2015 OCamlPro                                        *)
(*    Copyright 2012 INRIA                                                *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

open OpamTypes
open OpamStateTypes
open OpamTypesBase
open OpamFilename.Op

let log fmt = OpamConsole.log "ENV" fmt

(* - Environment and updates handling - *)

let apply_env_update_op ?(inplace_match = fun _ -> false) op arg prev_value =
  let sep = OpamStd.Sys.path_sep () in
  let split_value () = OpamStd.String.split_delim prev_value sep in
  let join_value = String.concat (String.make 1 sep) in
  let colon_eq = function (* prepend a, but keep ":"s *)
    | [] -> [arg; ""]
    | "" :: l -> "" :: arg :: l (* keep leading colon *)
    | l -> arg :: l
  in
  match op with
  | Eq -> arg
  | PlusEq -> if arg = "" then prev_value else join_value (arg :: split_value ())
  | EqPlus -> if arg = "" then prev_value else join_value (split_value () @ [arg])
  | EqPlusEq ->
    let l = split_value () in
    let rec update acc = function
      | [] -> arg :: l (* prepend by default *)
      | x::r ->
        if inplace_match x then List.rev_append acc (arg::r)
        else update (x::acc) r
    in
    join_value (update [] l)
  | ColonEq -> join_value (colon_eq (split_value ()))
  | EqColon -> join_value (List.rev (colon_eq (List.rev (split_value ()))))

(** Undoes previous updates done by opam, useful for not duplicating already
    done updates; this is obviously not perfect, as all operators are not
    reversible.

    Arguments starting with OPAMROOT are treated as corresponding, to allow
    reverting updates with different paths (e.g. PATH updated for different
    switches.

    None is returned if the variable should be unset (or has a previously
    unknown value anyway); not correspondig reverts are ignored. If [=+=] is
    used and a matching value is found, it is replaced by [inplace_holder], or
    removed if unset. *)
let reverse_env_update ?inplace_holder op arg cur_value =
  let matches_arg =
    let root = OpamFilename.Dir.to_string OpamStateConfig.(!r.root_dir) in
    if OpamStd.String.starts_with ~prefix:root arg then
      OpamStd.String.starts_with ~prefix:root
    else
    fun s -> s = arg
  in
  let sep = OpamStd.Sys.path_sep () in
  let str_sep = String.make 1 sep in
  let rec rem_first_instance ?(f=fun x -> x) acc = function
    | [] -> None
    | x::r ->
      if matches_arg x then Some (List.rev_append acc (f r))
      else rem_first_instance (x::acc) r
  in
  let split () = OpamStd.String.split_delim cur_value sep in
  match op with
  | Eq -> if arg = cur_value then None else Some (cur_value)
  | PlusEq ->
    (match rem_first_instance [] (split ()) with
     | Some [] -> None
     | Some sl -> Some (String.concat str_sep sl)
     | None -> Some cur_value)
  | EqPlus ->
    (match rem_first_instance [] (List.rev (split ())) with
     | Some [] -> Some ""
     | Some sl -> Some (String.concat str_sep (List.rev sl))
     | None -> Some cur_value)
  | EqPlusEq ->
    let f r = match inplace_holder with None -> r | Some p -> p::r in
    (match rem_first_instance ~f [] (split ()) with
     | Some [] -> Some ""
     | Some sl -> Some (String.concat str_sep sl)
     | None -> Some cur_value)
  | ColonEq ->
    (match rem_first_instance [] (split ()) with
     | Some ([] | [""]) -> Some ""
     | Some sl -> Some (String.concat str_sep sl)
     | None -> Some cur_value)
  | EqColon ->
    (match rem_first_instance [] (List.rev (split ())) with
     | Some ([] | [""]) -> Some ""
     | Some sl -> Some (String.concat str_sep (List.rev sl))
     | None -> Some cur_value)

let expand_update ?inplace_match (ident, op, string, comment) value =
  ident,
  apply_env_update_op ?inplace_match op string value,
  comment

let expand ?rev_updates (updates: env_update list) : env =
  let rev_updates = OpamStd.Option.default updates rev_updates in
  let inplace_holder =
    Printf.sprintf "placeholder_%Ld" (Random.int64 Int64.max_int)
  in
  (* Reverse all updates, in reverse order, on current environment *)
  let defs =
    List.fold_right (fun (var, op, arg, _) defs ->
        let v_opt, defs = OpamStd.List.pick_assoc var defs in
        let v =
          OpamStd.Option.Op.((v_opt >>+ fun () -> OpamStd.Env.getopt var) +! "")
        in
        match reverse_env_update ~inplace_holder op arg v with
        | Some v -> (var, v)::defs
        | None -> defs)
      rev_updates []
  in
  (* And re-apply them *)
  let env =
    List.fold_left (fun env ((var, _, _, _) as upd) ->
        let v =
          let f, var = if OpamStd.Sys.(os () = Win32) then String.uppercase, String.uppercase var else (fun x -> x), var in
          try List.find (fun (v, _, _) -> f v = var) env |> fun (_, v, _) -> v
          with Not_found ->
          try let (_, r) = List.find (fun (v, _) -> f v = var) defs in r
          with Not_found -> ""
        in
        expand_update ~inplace_match:(fun s -> s = inplace_holder) upd v :: env)
      [] updates
  in
  let exists (var, value) =
    let f =
      if OpamStd.Sys.(os () = Win32) then
        String.uppercase
      else
        fun x -> x
    in
    let v' = f var in
    if List.exists (fun (v, _, _) -> f v = v') env then
      None
    else
      Some (var, value, None)
  in
  List.rev_append env (OpamStd.List.filter_map exists defs)

let add ?rev_updates (env: env) (updates: env_update list) =
  let env =
    if OpamStd.(Sys.os () = Sys.Win32) then
      (*
       * Environment variable names are case insensitive on Windows
       *)
      let updates = List.rev_map (fun (u,_,_,_) -> (String.uppercase u, "", "", None)) updates in
      List.filter (fun (k,_,_) -> let k = String.uppercase k in List.for_all (fun (u,_,_,_) -> u <> k) updates) env
    else
      List.filter (fun (k,_,_) -> List.for_all (fun (u,_,_,_) -> u <> k) updates)
        env
  in
  env @ expand ?rev_updates updates

let compute_updates st =
  (* Todo: put these back into their packages !
  let perl5 = OpamPackage.Name.of_string "perl5" in
  let add_to_perl5lib =  OpamPath.Switch.lib t.root t.switch t.switch_config perl5 in
  let new_perl5lib = "PERL5LIB", "+=", OpamFilename.Dir.to_string add_to_perl5lib in
  let toplevel_dir =
    "OCAML_TOPLEVEL_PATH", "=",
    OpamFilename.Dir.to_string (OpamPath.Switch.toplevel t.root t.switch t.switch_config) in
*)
  let fenv ?opam v =
    try OpamPackageVar.resolve st ?opam v
    with Not_found ->
      log "Undefined variable: %s" (OpamVariable.Full.to_string v);
      None
  in
  let man_path =
    let open OpamStd.Sys in
    match os () with
    | OpenBSD | NetBSD | FreeBSD ->
      [] (* MANPATH is a global override on those, so disabled for now *)
    | _ ->
      ["MANPATH", EqColon,
       OpamFilename.Dir.to_string
         (OpamPath.Switch.man_dir
            st.switch_global.root st.switch st.switch_config),
      Some "Current opam switch man dir"]
  in
  let switch_pfx =
    "OPAM_SWITCH_PREFIX", Eq,
    OpamFilename.Dir.to_string
      (OpamPath.Switch.root st.switch_global.root st.switch),
    Some "Prefix of the current opam switch"
  in
  let pkg_env = (* XXX: Does this need a (costly) topological sort ? *)
    let sep = OpamStd.Sys.path_sep () in
    OpamPackage.Set.fold (fun nv acc ->
        let opam = OpamSwitchState.opam st nv in
        (List.map (fun (name,op,str,cmt) ->
            let s =
              OpamFilter.expand_string ~default:(fun _ -> "") (fenv ~opam) str
            in
            let items =
            match op with
            | Eq
            | EqPlusEq -> [s]
            | PlusEq
            | EqPlus
            | ColonEq
            | EqColon -> OpamStd.String.split_delim s sep
            in
            OpamStd.List.filter_map (fun s -> if s = "" then None else Some (name, op, s, cmt)) items)
          (OpamFile.OPAM.env opam) |>
        List.flatten)
        @ acc)
      st.installed []
  in
  let root =
    let current = st.switch_global.root in
    let default = OpamStateConfig.(default.root_dir) in
    let current_string = OpamFilename.Dir.to_string current in
    let env = OpamStd.Env.getopt "OPAMROOT" in
    if current <> default || (env <> None && env <> Some current_string)
    then [ "OPAMROOT", Eq, current_string, None ]
    else []
  in
  man_path @ root @ switch_pfx :: pkg_env

let updates ~opamswitch ?(force_path=false) st =
  let root = st.switch_global.root in
  let update =
    let fn = OpamPath.Switch.environment root st.switch in
    match OpamFile.Environment.read_opt fn with
    | Some env -> env
    | None -> compute_updates st
  in
  let add_to_path = OpamPath.Switch.bin root st.switch st.switch_config in
  let new_path =
    "PATH",
    (if force_path then PlusEq else EqPlusEq),
    OpamFilename.Dir.to_string add_to_path,
    Some "Current opam switch binary dir" in
  let switch =
    if opamswitch then
      [ "OPAMSWITCH", Eq, OpamSwitch.to_string st.switch, None ]
    else [] in
  new_path :: switch @ update

let get_current_reverse st =
  try
    (* Reverse changes made in the current environment - for this, use OPAM_SWITCH_PREFIX rather than any parameters *)
    let environment_switch =
      Filename.basename (OpamStd.Env.get "OPAM_SWITCH_PREFIX")
    in
    let reverse_switch = OpamSwitch.of_string environment_switch in
    if not (List.mem reverse_switch (OpamFile.Config.installed_switches st.switch_global.config)) then begin
      OpamConsole.warning "The environment appears to have been configured for %s, but this switch no longer exists:\nYou may wish to reload your shell to clear out any OPAM changes to the environment." environment_switch;
      raise Not_found
    end;
    let add_to_path =
      OpamSwitchState.with_ `Lock_none ~switch:reverse_switch st.switch_global @@ fun st -> OpamPath.Switch.bin st.switch_global.root reverse_switch st.switch_config in
    let new_path =
      "PATH",
      PlusEq,
      OpamFilename.Dir.to_string add_to_path,
      Some "Current opam switch binary dir" in
    OpamFile.Environment.read_opt (OpamPath.Switch.environment st.switch_global.root reverse_switch) |> OpamStd.Option.map (fun env -> new_path::env)
  with Not_found -> None

(* This function is used by 'opam config env' and 'opam switch' to
   display the environment variables. We have to make sure that
   OPAMSWITCH is always the one being reported in '~/.opam/config'
   otherwise we can have very weird results (as the inability to switch
   between compilers).

   Note: when we do the later command with --switch=SWITCH, this mean
   we really want to get the environment for this switch. *)
let get_opam ~force_path st =
  let opamswitch = OpamStateConfig.(!r.switch_from <> `Default) in
  let rev_updates = get_current_reverse st in
  add ?rev_updates [] (updates ~opamswitch ~force_path st)

let get_reverse_opam ~force_path st =
  let opamswitch = OpamStateConfig.(!r.switch_from <> `Default) in
  let rev_updates = updates ~opamswitch ~force_path st in
  add ~rev_updates [] []

let get_full ?(opamswitch=true) ~force_path st =
  let env0 = List.map (fun (v,va) -> v,va,None) (OpamStd.Env.list ()) in
  let rev_updates = get_current_reverse st in
  add ?rev_updates env0 (updates ~opamswitch ~force_path st)

let path ~force_path root switch =
  let bindir =
    OpamPath.Switch.bin root switch
      (OpamFile.Dot_config.safe_read
         (OpamPath.Switch.global_config root switch))
  in
  let _, path, _ =
    let prefix = OpamFilename.Dir.to_string OpamStateConfig.(!r.root_dir) in
    expand_update
      ~inplace_match:(OpamStd.String.starts_with ~prefix)
      ("PATH",
       (if force_path then PlusEq else EqPlusEq),
       OpamFilename.Dir.to_string bindir,
       Some "Current opam switch binary dir")
      (OpamStd.Option.default "" (OpamStd.Env.getopt "PATH"))
  in
  path

let full_with_path ~force_path root switch =
  let env0 = List.map (fun (v,va) -> v,va,None) (OpamStd.Env.list ()) in
  add env0 [
    "PATH",
    (if force_path then PlusEq else EqPlusEq),
    path ~force_path root switch,
    None
  ]

let is_up_to_date st =
  let changes =
    List.filter
      (fun (s, v, _) -> Some v <>
                        try Some (OpamStd.Env.get s) with Not_found -> None)
      (get_opam ~force_path:false st) in
  log "Not up-to-date env variables: [%s]"
    (String.concat " " (List.map (fun (v, _, _) -> v) changes));
  changes = []

let eval_string gt switch =
  let root =
    let opamroot_cur = OpamFilename.Dir.to_string gt.root in
    let opamroot_env =
      OpamStd.Option.Op.(
        OpamStd.Env.getopt "OPAMROOT" +!
        OpamFilename.Dir.to_string OpamStateConfig.(default.root_dir)
      ) in
    if opamroot_cur <> opamroot_env then
      Printf.sprintf " --root=%s" opamroot_cur
    else
      "" in
  let switch =
    match switch with
    | None -> ""
    | Some sw ->
      let sw_cur = OpamSwitch.to_string sw in
      let sw_env =
        OpamStd.Option.Op.(
          OpamStd.Env.getopt "OPAMSWITCH" ++
          (OpamFile.Config.switch gt.config >>| OpamSwitch.to_string)
        )
      in
      if Some sw_cur <> sw_env then Printf.sprintf " --switch=%s" sw_cur
      else ""
  in
  match OpamStd.Sys.guess_shell_compat () with
  | `fish ->
    Printf.sprintf "eval (opam config env%s%s)" root switch
  | `clink
  | `cmd ->
      "opam config env"
  | _ ->
    Printf.sprintf "eval `opam config env%s%s`" root switch



(* -- Shell and init scripts handling -- *)

let switch_eval_sh  = "switch_eval.sh"
let switch_eval_cmd = "switch_eval.cmd"
let complete_sh     = "complete.sh"
let complete_zsh    = "complete.zsh"
let complete_clink  = "complete.lua"
let variables_sh    = "variables.sh"
let variables_csh   = "variables.csh"
let variables_fish  = "variables.fish"
let variables_cmd   = "variables.cmd"
let variables_clink = "opam config env --clink"
let init_sh         = "init.sh"
let init_zsh        = "init.zsh"
let init_csh        = "init.csh"
let init_fish       = "init.fish"
let init_cmd        = "init.cmd"
let init_clink      = "init.lua"
let init_file = function
  | `sh   -> init_sh
  | `csh  -> init_csh
  | `zsh  -> init_zsh
  | `bash -> init_sh
  | `fish -> init_fish
  | `cmd  -> init_cmd
  | `clink -> init_clink

let source root ~shell ?(interactive_only=false) f =
  let file f = OpamFilename.to_string (OpamPath.init root // f) in
  let s =
    match shell with
    | `csh ->
      Printf.sprintf "source %s >& /dev/null || true\n" (file f)
    | `fish ->
      Printf.sprintf "source %s > /dev/null 2> /dev/null; or true\n" (file f)
    | `cmd ->
      Printf.sprintf "opam config env --autorun"
    | `clink ->
       (* @@DRA Not sure if the use of %S is totally safe - need escaped backslash characters! *)
       Printf.sprintf "dofile(%S)" (file f)
    | _ ->
      Printf.sprintf "test -x %s && . %s > /dev/null 2> /dev/null || true\n"
        (file f) (file f)
  in
  if interactive_only then
    match shell with
    | `csh ->
      Printf.sprintf "if (tty -s >&/dev/null) then\n  %sendif\n" s
    | `fish ->
      Printf.sprintf "if tty -s >/dev/null 2>&1\n %send\n" s
    | `clink ->
        s
    | _ ->
      Printf.sprintf "if tty -s >/dev/null 2>&1; then\n  %sfi\n" s
  else s

let string_of_update st shell updates =
  let fenv = OpamPackageVar.resolve st in
  let make_comment comment_opt =
    OpamStd.Option.to_string (Printf.sprintf "# %s\n") comment_opt
  in
  let sh _   (k,v,comment) =
    Printf.sprintf "%s%s=%S; export %s;\n"
      (make_comment comment) k v k in
  let csh _  (k,v,comment) =
    Printf.sprintf "%sif ( ! ${?%s} ) setenv %s \"\"\nsetenv %s %S\n"
      (make_comment comment) k k k v in
  let fish _ (k,v,comment) =
    (* Fish converts some colon-separated vars to arrays, which have to be treated differently.
     * Opam only changes PATH and MANPATH but we handle CDPATH for completeness. *)
    let fish_array_vars = ["PATH"; "MANPATH"; "CDPATH"] in
    let fish_array_derefs = List.map (fun s -> "$" ^ s) fish_array_vars in
    if not (List.mem k fish_array_vars) then
      (* Regular string variables *)
      Printf.sprintf "%sset -gx %s %S;\n"
        (make_comment comment) k v
    else
      (* The MANPATH and CDPATH have default "values" if they are unset and we
       * must be sure that we preserve these defaults when "appending" to them.
       * This because Fish has trouble dealing with the case where we want to
       * have a colon at the start or at the end of the string that gets exported.
       *  - MANPATH: ""  (default system manpages)
       *  - CDPATH:  "." (current directory) *)
      let init_array = match k with
        | "PATH"    -> "" (* PATH is always set *)
        | "MANPATH" -> "if [ 0 -eq (count $MANPATH) ]; set -gx MANPATH \"\"; end;\n"
        | "CDPATH"  -> "if [ 0 -eq (count $CDPATH) ]; set -gx CDPATH \".\"; end;\n"
        | _         -> assert false in
      (* Opam assumes that `v` is a string with colons in the middle so we have
       * to convert that to an array assignment that fish understands.
       * We also have to pay attention so we don't quote array expansions - that
       * would replace some colons by spaces in the exported string *)
      let vs = OpamStd.String.split_delim v ':' in
      let to_arr_element v =
        if List.mem v fish_array_derefs then v else Printf.sprintf "%S" v in
      let set_array =
        Printf.sprintf "%sset -gx %s %s;\n"
          (make_comment comment)
          k (OpamStd.List.concat_map " " to_arr_element vs) in
      (init_array ^ set_array) in
  let cmd  p (k,v,_) = Printf.sprintf "%sset %s=%s\n" p k v in
  let export = match shell with
    | `zsh | `sh  -> sh
    | `fish -> fish
    | `csh -> csh
    | `clink
    | `cmd -> cmd in
  let aux (ident, symbol, string, comment) =
    let string = OpamFilter.expand_string ~default:(fun _ -> "") fenv string in
    let prefix, string =
      if OpamStd.Sys.(os () = Win32) && ident = "MANPATH" then
        (Printf.sprintf "for /f \"delims=\" %%%%D in ('cygpath \"%s\"') do " string, "%%D")
      else
        ("", string) in
    let key, value, skip =
      let separator = match ident with
      | "PATH" | "CAML_LD_LIBRARY_PATH" | "PERL5LIB" ->
          OpamStd.Sys.path_sep ()
      | _ ->
          ':' in
      let retrieve () ident =
        if OpamStd.Sys.(os () = Win32) then
          Printf.sprintf "%%%s%%" ident
        else
          "$" ^ ident in
      match symbol with
      | Eq  -> ident, string, false
      | PlusEq | ColonEq | EqPlusEq ->
          ident, Printf.sprintf "%s%c%a" string separator retrieve ident, (string = "")
      | EqColon | EqPlus ->
        ident, (match shell with `csh -> Printf.sprintf "${%s}:%s" ident string
                               | _ -> Printf.sprintf "%a%c%s" retrieve ident separator string), (string = "")
    in
    if skip then
      ""
    else
      export prefix (key, value, comment) in
  OpamStd.List.concat_map "" aux updates

let rem = function
  `cmd ->
    "rem"
| `clink ->
    "--"
| _ ->
    "#"

let init_script root ~switch_eval ~completion ~shell
    (variables_sh, switch_eval_sh, complete_sh) =
  let variables =
    match shell with
      `cmd ->
        Some "opam config env"
    | `clink ->
        Some "os.execute(\"opam config env --clink\")"
    | _ ->
        Some (source root ~shell variables_sh) in
  let switch_eval =
    if switch_eval then
      OpamStd.Option.map (source root ~shell ~interactive_only:true)
        switch_eval_sh
    else
      None in
  let complete =
    if completion then
      OpamStd.Option.map (source root ~shell ~interactive_only:true) complete_sh
    else
      None in
  let buf = Buffer.create 128 in
  let append name = function
    | None   -> ()
    | Some c ->
      Printf.bprintf buf "%s %s\n%s\n" (rem shell) name c in
  append "Load the environment variables" variables;
  append "Load the auto-complete scripts" complete;
  append "Load the opam-switch-eval script" switch_eval;
  Buffer.contents buf

let write_script root (name, body) =
  let file = OpamPath.init root // name in
  try OpamFilename.write file body
  with e ->
    OpamStd.Exn.fatal e;
    OpamConsole.error "Could not write %s" (OpamFilename.to_string file)

let write_static_init_scripts root ~switch_eval ~completion =
  let scripts =
    let shells =
      (* The shell scripts have been intentionally disabled for Windows, the idea being that they'll
       * be selectively re-integrated by someone who actually tests them...
       *)
      if OpamStd.Sys.(os () = Win32) then
        [
          `cmd, init_cmd, (variables_cmd, None, None);
          `clink, init_clink, (variables_clink, None, Some complete_clink);
        ]
      else
        [
          `sh, init_sh, (variables_sh, Some switch_eval_sh, Some complete_sh);
          `zsh, init_zsh, (variables_sh, Some switch_eval_sh, Some complete_zsh);
          `csh, init_csh, (variables_csh, None, None);
          `fish, init_fish, (variables_fish, None, None);
        ] in
    let scripts =
      if OpamStd.Sys.(os () = Win32) then
        [
          switch_eval_cmd, OpamScript.switch_eval_cmd;
          complete_clink, OpamScript.complete_lua;
        ]
      else
        [
          complete_sh, OpamScript.complete;
          complete_zsh, OpamScript.complete_zsh;
          switch_eval_sh, OpamScript.switch_eval;
        ] in
    List.map (fun (shell, init, scripts) ->
        init, init_script root ~shell ~switch_eval ~completion scripts) shells @ scripts
  in
  List.iter (write_script root) scripts

let write_dynamic_init_scripts st =
  let updates = updates ~opamswitch:false st in
  let scripts =
    if OpamStd.Sys.(os () = Win32) then
      [
        variables_cmd, string_of_update st `cmd updates;
      ]
    else
      [
        variables_sh, string_of_update st `sh updates;
        variables_csh, string_of_update st `csh updates;
        variables_fish, string_of_update st `fish updates;
      ] in
  try
    OpamFilename.with_flock_upgrade `Lock_write ~dontblock:true
      st.switch_global.global_lock
    @@ fun _ ->
    List.iter (write_script st.switch_global.root) scripts
  with OpamSystem.Locked ->
    OpamConsole.warning
      "Global shell init scripts not installed (could not acquire lock)"

let status_of_init_file root init_sh =
  let init_sh = OpamPath.init root // init_sh in
  if OpamFilename.exists init_sh then (
    let init = OpamFilename.read init_sh in
    if OpamFilename.exists init_sh then
      let complete_sh = OpamStd.String.contains ~sub:complete_sh init in
      let complete_zsh = OpamStd.String.contains ~sub:complete_zsh init in
      let switch_eval_sh = OpamStd.String.contains ~sub:switch_eval_sh init in
      Some (complete_sh, complete_zsh, switch_eval_sh)
    else
      None
  ) else
    None

let dot_profile_needs_update root dot_profile shell =
  if not (OpamFilename.exists dot_profile) || shell = `cmd then `yes else
  let body = OpamFilename.read dot_profile in
  let escape =
    if shell = `clink then
      fun x ->
        let x = Printf.sprintf "%S" x in
        String.sub x 1 (String.length x - 2)
    else
      fun id -> id in
  let pattern1 = "opam config env" in
  let pattern2 = escape @@ OpamFilename.to_string (OpamPath.init root // "init") in
  let pattern3 =
    escape @@ OpamStd.String.remove_prefix ~prefix:(OpamFilename.Dir.to_string root)
      pattern2
  in
  let uncommented_re patts =
    Re.(compile (seq [bol; rep (diff any (set "#:"));
                      alt (List.map str patts)]))
  in
  if Re.execp (uncommented_re [pattern1; pattern2]) body then `no
  else if Re.execp (uncommented_re [pattern3]) body then `otherroot
  else `yes

let update_dot_profile root dot_profile shell =
  let pretty_dot_profile = OpamFilename.prettify dot_profile in
  match dot_profile_needs_update root dot_profile shell with
  | `no        -> OpamConsole.msg "  %s is already up-to-date.\n" pretty_dot_profile; false
  | `otherroot ->
    OpamConsole.msg
      "  %s is already configured for another OPAM root.\n"
      pretty_dot_profile; false
  | `yes       ->
    let init_file = init_file shell in
    let body =
      if OpamFilename.exists dot_profile then
        OpamFilename.read dot_profile
      else
        "" in
    OpamConsole.msg "  Updating %s.\n" pretty_dot_profile;
    let body =
      Printf.sprintf
        "%s\n\n\
         %s OPAM configuration\n\
         %s"
        (OpamStd.String.strip body) (rem shell) (source root ~shell init_file) in
    OpamFilename.write dot_profile body; true

(* A little bit of remaining OCaml specific stuff. Can we find another way ? *)
let ocamlinit () =
  try
    let file = Filename.concat (OpamStd.Sys.home ()) ".ocamlinit" in
    Some (OpamFilename.of_string file)
  with Not_found ->
    None

let ocamlinit_needs_update () =
  match ocamlinit () with
  | None      -> true
  | Some file ->
    if OpamFilename.exists file then (
      let body = OpamFilename.read file in
      let sub = "OCAML_TOPLEVEL_PATH" in
      not (OpamStd.String.contains ~sub body)
    ) else
      true

let update_ocamlinit () =
  if ocamlinit_needs_update () then (
    match ocamlinit () with
    | None      -> ()
    | Some file ->
      let body =
        if not (OpamFilename.exists file) then ""
        else OpamFilename.read file in
      if body = "" then
        OpamConsole.msg "  Generating ~%s.ocamlinit.\n" Filename.dir_sep
      else
        OpamConsole.msg "  Updating ~%s.ocamlinit.\n" Filename.dir_sep;
      try
        let header =
          "(* Added by OPAM. *)\n\
           let () =\n\
          \  try Topdirs.dir_directory (Sys.getenv \"OCAML_TOPLEVEL_PATH\")\n\
          \  with Not_found -> ()\n\
           ;;\n\n" in
        let oc = open_out_bin (OpamFilename.to_string file) in
        output_string oc (header ^ body);
        close_out oc;
      with e ->
        OpamStd.Exn.fatal e;
        OpamSystem.internal_error "Cannot write ~%s.ocamlinit." Filename.dir_sep
  ) else
    OpamConsole.msg "  ~%s.ocamlinit is already up-to-date.\n" Filename.dir_sep

let update_user_setup_aux root ~ocamlinit ?dot_profile shell =
  if ocamlinit || dot_profile <> None then (
    OpamConsole.msg "User configuration:\n";
    if ocamlinit then update_ocamlinit ();
    let f f =
      if shell = `cmd then
        let value = source root ~shell (init_file shell) in
          let f = OpamFilename.to_string f in
          OpamStd.Win32.(writeRegistry RegistryHive.HKEY_CURRENT_USER (Filename.dirname f) (Filename.basename f) RegistryHive.REG_SZ value);
          false
      else
        update_dot_profile root f shell in
    match dot_profile with
      Some x -> f x
    | None -> false
  ) else
    false

let update_user_setup root ~ocamlinit ?dot_profile shell = ignore @@ update_user_setup_aux root ~ocamlinit ?dot_profile shell

let display_setup root ~dot_profile shell =
  let print (k,v) = OpamConsole.msg "  %-25s - %s\n" k v in
  let not_set = "not set" in
  let ok      = "string is already present so file unchanged" in
  let error   = "error" in
  let user_setup =
    let ocamlinit_status =
      if ocamlinit_needs_update () then not_set else ok in
    let dot_profile_status =
      match dot_profile_needs_update root dot_profile shell with
      | `no        -> ok
      | `yes       -> not_set
      | `otherroot -> error in
    [ (Printf.sprintf "~%s.ocamlinit" Filename.dir_sep, ocamlinit_status);
      (OpamFilename.prettify dot_profile, dot_profile_status); ]
  in
  let init_file = init_file shell in
  let pretty_init_file = OpamFilename.prettify (OpamPath.init root // init_file) in
  let global_setup =
    match status_of_init_file root init_file with
    | None -> [pretty_init_file, not_set ]
    | Some(complete_sh, complete_zsh, switch_eval_sh) ->
      let completion =
        if not complete_sh
        && not complete_zsh then
          not_set
        else ok in
      let switch_eval =
        if switch_eval_sh then
          ok
        else
          not_set in
      [ ("init-script"     , Printf.sprintf "%s" pretty_init_file);
        ("auto-completion" , completion);
        ("opam-switch-eval", switch_eval);
      ]
  in
  OpamConsole.msg "User configuration:\n";
  List.iter print user_setup;
  OpamConsole.msg "Global configuration:\n";
  List.iter print global_setup

let print_env_warning_at_init gt ~ocamlinit ?dot_profile shell =
    let (env_needed, profile_index, ocamlinit_index) =
      if shell <> `cmd && shell <> `clink then
        (true, "2.", "3.")
      else
        (false, "1.", "2.") in
  let profile_string = match dot_profile with
    | None -> ""
    | Some f ->
        if shell = `cmd then
          let command =
            let command = source gt.root ~shell:shell (init_file shell) in
            String.sub command 0 (String.length command - 1) in
          Printf.sprintf
            "%s To correctly configure OPAM for subsequent use, update\n\
            \   HKCU\\Software\\Microsoft\\Command Processor\\AutoRun to the following:\n\
             \n\
            \      %s\n\
             \n\
            \   for example, by running:\n\
             \n\
            \      reg add \"HKCU\\Software\\Microsoft\\Command Processor\" /v AutoRun /d \"%s\"\n\n"
            (OpamConsole.colorise `yellow profile_index)
            command command
        else
          Printf.sprintf
            "%s To correctly configure OPAM for subsequent use, add the following\n\
            \   line to your profile file (for instance %s):\n\
             \n\
            \      %s\n"
            (OpamConsole.colorise `yellow profile_index)
            (OpamFilename.prettify f)
            (source gt.root ~shell (init_file shell))
  in
  let ocamlinit_string =
    if not ocamlinit then "" else
      OpamConsole.colorise `yellow ocamlinit_index ^ Printf.sprintf
      " To avoid issues related to non-system installations of `ocamlfind`\n\
      \   add the following lines to ~%s.ocamlinit (create it if necessary):\n\
       \n\
      \      let () =\n\
      \        try Topdirs.dir_directory (Sys.getenv \"OCAML_TOPLEVEL_PATH\")\n\
      \        with Not_found -> ()\n\
      \      ;;\n\n" Filename.dir_sep
  in
  let line =
    OpamConsole.colorise `cyan
      "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\
       =-=-="
  in
  let env_line = Printf.sprintf
    "%s To configure OPAM in the current shell session, you need to run:\n\
     \n\
    \      %s\n"
    (OpamConsole.colorise `yellow "1.") (eval_string gt None)
  in
  OpamConsole.msg
    "\n%s\n\n\
     %s%s%s%s\n\n"
    line (if env_needed then env_line else "")
    profile_string ocamlinit_string
    line

let set_cmd_env env =
  List.iter (fun (k, v, _) -> log "parent-putenv: %s->%S" k v; ignore (OpamStd.Win32.parent_putenv k v)) env

let check_and_print_env_warning st =
  if (OpamSwitchState.is_switch_globally_set st ||
      OpamStateConfig.(!r.switch_from <> `Command_line)) &&
     not (is_up_to_date st) then
       if OpamStd.Sys.(os () = Win32) then
         set_cmd_env (get_opam ~force_path:false st)
       else
         OpamConsole.formatted_msg
           "# Run %s to update the current shell environment\n"
           (OpamConsole.colorise `bold (eval_string st.switch_global
                                          (Some st.switch)))

let setup_interactive root ~dot_profile shell =
  let update dot_profile =
    OpamConsole.msg "\n";
    if update_user_setup_aux root ~ocamlinit:(dot_profile <> None) ?dot_profile shell && shell = `clink then
      OpamConsole.msg
        "\n\
         OPAM has installed auto-completion scripts for clink\n\
         In order to enable them in this and any other existing sessions, please press CTRL+Q\n\
        \  (or whichever key sequence you have rebound %s to)" (OpamConsole.colorise `bold "reload-lua-state");
    write_static_init_scripts root ~switch_eval:true ~completion:true;
    dot_profile <> None in

  OpamConsole.msg "\n";

  let has_clink = (OpamStd.Sys.clink_scripts () <> None) in
  let will_autorun = shell = `cmd || shell = `clink && not has_clink in
  let pretty_dot_profile =
    (*
     * It might be better to check to see if there's an existing value already there, but
     * AutoRun is not commonly used at *user* level (and HKLM AutoRun would be unaffected)
     *)
    if will_autorun then
      "HKCU\\" ^ OpamFilename.prettify dot_profile
    else
      OpamFilename.prettify dot_profile in

  let dot_profile_msg =
    if will_autorun then
      Printf.sprintf
        "  - %s to set the right\n\
        \    environment variables for the Command Prompt on startup.\n"
        (OpamConsole.colorise `cyan @@ ("HKCU\\" ^ OpamFilename.prettify dot_profile))
    else
      if has_clink then
        Printf.sprintf
          "  - %s (or a file you specify) to set the right environment\n\
          \    variables and to load the auto-completion scripts for your shell (CMD/Clink)\n\
          \    on startup. Specifically, it checks for and appends the following line:\n"
          (OpamConsole.colorise `cyan @@ OpamFilename.prettify dot_profile)
      else
        Printf.sprintf
          "\n  - %s (or a file you specify) to set the right environment\n\
          \    variables and to load the auto-completion scripts for your shell (%s)\n\
          \    on startup. Specifically, it checks for and appends the following line:\n"
          (OpamConsole.colorise `cyan @@ pretty_dot_profile)
          (OpamConsole.colorise `bold @@ OpamTypesBase.string_of_shell shell) in

  match OpamConsole.read
      "In normal operation, OPAM only alters files within ~%s.opam.\n\
       \n\
       During this initialisation, you can allow OPAM to add information to two\n\
       other %s for best results. You can also make these additions manually\n\
       if you wish.\n\
       \n\
       If you agree, OPAM will modify:\n\n%s\
      \    %s\
      \n\
      \  - %s to ensure that non-system installations of `ocamlfind`\n\
      \    (i.e. those installed by OPAM) will work correctly when running the\n\
      \    OCaml toplevel. It does this by adding $OCAML_TOPLEVEL_PATH to the list\n\
      \    of include directories.\n\
      \n\
       If you choose to not configure your system now, you can either configure\n\
       OPAM manually (instructions will be displayed) or launch the automatic setup\n\
       later by running:\n\
      \n\
       \   opam config setup -a\n\
       \n\
      \n\
       Do you want OPAM to modify %s and ~%s.ocamlinit?\n\
       (default is 'no'%s)\n\
      \    [N/y%s]"
      Filename.dir_sep
      (if will_autorun then "places" else "files")
      dot_profile_msg
      (source root ~shell (init_file shell))
      (OpamConsole.colorise `cyan @@ Printf.sprintf "~%s.ocamlinit" Filename.dir_sep)
      pretty_dot_profile
      Filename.dir_sep
      (if will_autorun then "" else Printf.sprintf ", use 'f' to name a file other than %s" (OpamFilename.prettify dot_profile))
      (if will_autorun then "" else "/f")
  with
  | None when OpamCoreConfig.(!r.answer <> None) -> update (Some dot_profile)
  | Some ("y" | "Y" | "yes"  | "YES" ) -> update (Some dot_profile)
  | Some ("f" | "F" | "file" | "FILE") when shell <> `cmd ->
    begin match OpamConsole.read "  Enter the name of the file to update:" with
      | None   ->
        OpamConsole.msg "-- No filename: skipping the auto-configuration step --\n";
        false
      | Some f -> update (Some (OpamFilename.of_string f))
    end
  | _ -> update None
