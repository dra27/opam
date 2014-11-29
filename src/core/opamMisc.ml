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

module type SET = sig
  include Set.S
  val map: (elt -> elt) -> t -> t
  val choose_one : t -> elt
  val of_list: elt list -> t
  val to_string: t -> string
  val to_json: t -> OpamJson.t
  val find: (elt -> bool) -> t -> elt
  module Op : sig
    val (++): t -> t -> t
    val (--): t -> t -> t
    val (%%): t -> t -> t
  end
end
module type MAP = sig
  include Map.S
  val to_string: ('a -> string) -> 'a t -> string
  val to_json: ('a -> OpamJson.t) -> 'a t -> OpamJson.t
  val values: 'a t -> 'a list
  val keys: 'a t -> key list
  val union: ('a -> 'a -> 'a) -> 'a t -> 'a t -> 'a t
  val of_list: (key * 'a) list -> 'a t
end
module type ABSTRACT = sig
  type t
  val of_string: string -> t
  val to_string: t -> string
  val to_json: t -> OpamJson.t
  module Set: SET with type elt = t
  module Map: MAP with type key = t
end

module type OrderedType = sig
  include Set.OrderedType
  val to_string: t -> string
  val to_json: t -> OpamJson.t
end

let debug = ref false

let string_of_list f = function
  | [] -> "{}"
  | l  ->
    let buf = Buffer.create 1024 in
    let n = List.length l in
    let i = ref 0 in
    Buffer.add_string buf "{ ";
    List.iter (fun x ->
      incr i;
      Buffer.add_string buf (f x);
      if !i <> n then Buffer.add_string buf ", ";
    ) l;
    Buffer.add_string buf " }";
    Buffer.contents buf

let string_map f s =
  let len = String.length s in
  let s' = String.create len in
  for i = 0 to len - 1 do s'.[i] <- f s.[i] done;
  s'

let rec pretty_list ?(last="and") = function
  | []    -> ""
  | [a]   -> a
  | [a;b] -> Printf.sprintf "%s %s %s" a last b
  | h::t  -> Printf.sprintf "%s, %s" h (pretty_list t)

let rec remove_duplicates = function
  | a::(b::_ as r) when a = b -> remove_duplicates r
  | a::r -> a::remove_duplicates r
  | [] -> []

let max_print = 100

module Set = struct

  module Make (O : OrderedType) = struct

    module S = Set.Make(O)

    include S

    let fold f set i =
      let r = ref i in
      S.iter (fun elt ->
          r := f elt !r
        ) set;
      !r

    let choose_one s =
      match elements s with
      | [x] -> x
      | [] -> raise Not_found
      | _  -> invalid_arg "choose_one"

    let of_list l =
      List.fold_left (fun set e -> add e set) empty l

    let to_string s =
      if not !debug && S.cardinal s > max_print then
	Printf.sprintf "%d elements" (S.cardinal s)
      else
	let l = S.fold (fun nv l -> O.to_string nv :: l) s [] in
	string_of_list (fun x -> x) (List.rev l)

    let map f t =
      S.fold (fun e set -> S.add (f e) set) t S.empty

    let find fn s =
      choose (filter fn s)

    let to_json t =
      let elements = S.elements t in
      let jsons = List.map O.to_json elements in
      `A jsons

    module Op = struct
      let (++) = union
      let (--) = diff
      let (%%) = inter
    end

  end

end

module Map = struct

  module Make (O : OrderedType) = struct

    module M = Map.Make(O)

    include M

    let fold f map i =
      let r = ref i in
      M.iter (fun key value->
          r:= f key value !r
        ) map;
      !r

    let map f map =
      fold (fun key value map ->
          add key (f value) map
        ) map empty

    let mapi f map =
      fold (fun key value map ->
          add key (f key value) map
        ) map empty

    let values map =
      List.rev (M.fold (fun _ v acc -> v :: acc) map [])

    let keys map =
      List.rev (M.fold (fun k _ acc -> k :: acc) map [])

    let union f m1 m2 =
      M.fold (fun k v m ->
        if M.mem k m then
          M.add k (f v (M.find k m)) (M.remove k m)
        else
          M.add k v m
      ) m1 m2

    let to_string string_of_value m =
      if not !debug && M.cardinal m > max_print then
	Printf.sprintf "%d elements" (M.cardinal m)
      else
	let s (k,v) = Printf.sprintf "%s:%s" (O.to_string k) (string_of_value v) in
	let l = fold (fun k v l -> s (k,v)::l) m [] in
	string_of_list (fun x -> x) l

    let of_list l =
      List.fold_left (fun map (k,v) -> add k v map) empty l

    let to_json json_of_value t =
      let bindings = M.bindings t in
      let jsons = List.map (fun (k,v) ->
          `O [ ("key"  , O.to_json k);
               ("value", json_of_value v) ]
        ) bindings in
      `A jsons

  end

end

module Base = struct
  type t = string
  let of_string x = x
  let to_string x = x
  let to_json x = `String x
  module O = struct
    type t = string
    let to_string = to_string
    let compare = compare
    let to_json = to_json
  end
  module Set = Set.Make(O)
  module Map = Map.Make(O)
end

let filter_map f l =
  let rec loop accu = function
    | []     -> List.rev accu
    | h :: t ->
      match f h with
      | None   -> loop accu t
      | Some x -> loop (x::accu) t in
  loop [] l

module OInt = struct
  type t = int
  let compare = compare
  let to_string = string_of_int
  let to_json i = `String (string_of_int i)
end

module IntMap = Map.Make(OInt)
module IntSet = Set.Make(OInt)

module OString = struct
  type t = string
  let compare = compare
  let to_string x = x
  let to_json x = `String x
end

module StringSet = Set.Make(OString)
module StringMap = Map.Make(OString)

module StringSetSet = Set.Make(StringSet)
module StringSetMap = Map.Make(StringSet)

module OP = struct

  let (@@) f x = f x

  let (|>) x f = f x

  let (@*) g f x = g (f x)

  let (@>) f g x = g (f x)

end

module Option = struct
  let map f = function
    | None -> None
    | Some x -> Some (f x)

  let iter f = function
    | None -> ()
    | Some x -> f x

  let default dft = function
    | None -> dft
    | Some x -> x

  let default_map dft = function
    | None -> dft
    | some -> some

  module Op = struct
    let (>>=) = function
      | None -> fun _ -> None
      | Some x -> fun f -> f x
    let (>>|) opt f = map f opt
    let (+!) opt dft = default dft opt
    let (++) = function
      | None -> fun opt -> opt
      | some -> fun _ -> some
  end
end

let strip str =
  let p = ref 0 in
  let l = String.length str in
  let fn = function
    | ' ' | '\t' | '\r' | '\n' -> true
    | _ -> false in
  while !p < l && fn (String.unsafe_get str !p) do
    incr p;
  done;
  let p = !p in
  let l = ref (l - 1) in
  while !l >= p && fn (String.unsafe_get str !l) do
    decr l;
  done;
  String.sub str p (!l - p + 1)

let starts_with ~prefix s =
  let x = String.length prefix in
  let n = String.length s in
  n >= x
  && String.sub s 0 x = prefix

let ends_with ~suffix s =
  let x = String.length suffix in
  let n = String.length s in
  n >= x
  && String.sub s (n - x) x = suffix

let remove_prefix ~prefix s =
  if starts_with ~prefix s then
    let x = String.length prefix in
    let n = String.length s in
    String.sub s x (n - x)
  else
    s

let remove_suffix ~suffix s =
  if ends_with ~suffix s then
    let x = String.length suffix in
    let n = String.length s in
    String.sub s 0 (n - x)
  else
    s

let cut_at_aux fn s sep =
  try
    let i = fn s sep in
    let name = String.sub s 0 i in
    let version = String.sub s (i+1) (String.length s - i - 1) in
    Some (name, version)
  with Invalid_argument _ | Not_found ->
    None

let cut_at = cut_at_aux String.index

let rcut_at = cut_at_aux String.rindex

let contains s c =
  try let _ = String.index s c in true
  with Not_found -> false

let split s c =
  Re_str.split (Re_str.regexp (Printf.sprintf "[%c]" c)) s

let split_delim s c =
  Re_str.split_delim (Re_str.regexp (Printf.sprintf "[%c]" c)) s

(* Remove from a c-separated list of string the one with the given prefix *)
let reset_env_value ~prefix c v =
  let v = split_delim v c in
  List.filter (fun v -> not (starts_with ~prefix v)) v

(* Split the list in two according to the first occurrence of the string
   starting with the given prefix.
*)
let cut_env_value ~prefix c v =
  let v = split_delim v c in
  let rec aux before =
    function
      | [] -> [], List.rev before
      | curr::after when starts_with ~prefix curr ->
        before, after
      | curr::after -> aux (curr::before) after
  in aux [] v

(* if rsync -arv return 4 lines, this means that no files have changed *)
let rsync_trim = function
  | [] -> []
  | _ :: t ->
    match List.rev t with
    | _ :: _ :: _ :: l -> List.filter ((<>) "./") l
    | _ -> []

let exact_match re s =
  try
    let subs = Re.exec re s in
    let subs = Array.to_list (Re.get_all_ofs subs) in
    let n = String.length s in
    let subs = List.filter (fun (s,e) -> s=0 && e=n) subs in
    List.length subs > 0
  with Not_found ->
    false

(* XXX: not optimized *)
let insert comp x l =
  let rec aux = function
    | [] -> [x]
    | h::t when comp h x < 0 -> h::aux t
    | l -> x :: l in
  aux l

let env = lazy (
  let e = Unix.environment () in
  List.rev_map (fun s ->
    match cut_at s '=' with
    | None   -> s, ""
    | Some p -> p
  ) (Array.to_list e)
)
let with_process_in cmd f =
  let ic = Unix.open_process_in cmd in
  try
    let r = f ic in
    ignore (Unix.close_process_in ic) ; r
  with exn ->
    ignore (Unix.close_process_in ic) ; raise exn

let uname_s () =
  try
    with_process_in "uname -s"
      (fun ic -> Some (strip (input_line ic)))
  with Unix.Unix_error _ | Sys_error _ ->
    None

type os =
    Darwin
  | Linux
  | FreeBSD
  | OpenBSD
  | NetBSD
  | DragonFly
  | Cygwin
  | Win32
  | Unix
  | Other of string

let osref = ref None

let os () =
  match !osref with
  | None ->
    let os = match Sys.os_type with
      | "Unix" -> begin
          match uname_s () with
          | Some "Darwin"    -> Darwin
          | Some "Linux"     -> Linux
          | Some "FreeBSD"   -> FreeBSD
          | Some "OpenBSD"   -> OpenBSD
          | Some "NetBSD"    -> NetBSD
          | Some "DragonFly" -> DragonFly
          | _                -> Unix
        end
      | "Win32"  -> Win32
      | "Cygwin" -> Cygwin
      | s        -> Other s in
    osref := Some os;
    os
  | Some os -> os

let getenv =
  (* Environment variables are not case-sensitive on Windows *)
  if os () = Win32 then
    let assoc l n =
      let rec assoc = function
      | [] -> raise Not_found
      | (a,b)::l -> if compare (String.lowercase a) n = 0 then b else assoc l in
      assoc l in
    fun n -> assoc (Lazy.force env) (String.lowercase n)
  else
    fun n -> List.assoc n (Lazy.force env)

let env () = Lazy.force env

external parent_putenv_stub : string -> string -> bool = "Env_parent_putenv"
external isWoW64Mismatch_stub : unit -> int = "Env_IsWoW64Mismatch"

let parent_putenv =
  let ppid =
    if os () = Win32 then
      isWoW64Mismatch_stub ()
    else
      0 in
  if ppid > 0 then
    (*
     * Expect to see opam-putenv.exe in the same directory as opam.exe, rather than the path
     *)
    let putenv_exe = Filename.concat (Filename.dirname Sys.executable_name) "opam-putenv.exe" in
    let ppid = string_of_int ppid in
    let ctrl = ref stdout in
    if Sys.file_exists putenv_exe then
      fun key value ->
        if !ctrl = stdout then begin
          let (inCh, outCh) = Unix.pipe () in
          let _ = (Unix.create_process putenv_exe [| putenv_exe; ppid |] inCh Unix.stdout Unix.stderr) in
          ctrl := (Unix.out_channel_of_descr outCh);
          set_binary_mode_out !ctrl true;
        end;
        output_string !ctrl (key ^ "\r\n");
        flush !ctrl;
        output_string !ctrl ("V" ^ value ^ "\r\n");
        flush !ctrl;
        if key = "::QUIT" then ctrl := stdout;
        true
    else
      let shownWarning = ref false in
      fun _ _ ->
        if not !shownWarning then begin
          shownWarning := true;
          Printf.eprintf "opam-putenv was not found - OPAM is unable to alter environment variables\n%!";
          false
        end else
          false
  else
    parent_putenv_stub

type 'a registry =
  | REG_SZ : string registry

(*
 * These constants are used by the C module, so the order is important.
 *)
type regroot = HKEY_CLASSES_ROOT
             | HKEY_CURRENT_USER
             | HKEY_LOCAL_MACHINE
             | HKEY_USERS

let string_of_regroot = function
| HKEY_CLASSES_ROOT  -> "HKEY_CLASSES_ROOT"
| HKEY_CURRENT_USER  -> "HKEY_CURRENT_USER"
| HKEY_LOCAL_MACHINE -> "HKEY_LOCAL_MACHINE"
| HKEY_USERS         -> "HKEY_USERS"

let regroot_of_string = function
| "HKCR"
| "HKEY_CLASSES_ROOT"  -> HKEY_CLASSES_ROOT
| "HKCU"
| "HKEY_CURRENT_USER"  -> HKEY_CURRENT_USER
| "HKLM"
| "HKEY_LOCAL_MACHINE" -> HKEY_LOCAL_MACHINE
| "HKU"
| "HKEY_USERS"         -> HKEY_USERS
| _                    -> failwith "regroot_of_string"

external writeRegistry : regroot -> string -> string -> 'a registry -> 'a -> unit = "Env_WriteRegistry"

type ('a, 'b, 'c) winmessage =
  | WM_SETTINGCHANGE : (int, string, int) winmessage

external sendMessageTimeout : int -> int -> int -> ('a, 'b, 'c) winmessage -> 'a -> 'b -> int * 'c = "Env_SendMessageTimeout_byte" "Env_SendMessageTimeout"

let persistHomeDirectory home =
  (* Update our environment (largely cosmetic, as [env] already initialised) *)
  Unix.putenv "HOME" home;
  (* Update our parent's environment *)
  ignore (parent_putenv "HOME" home);
  (* Persist our user's environment *)
  writeRegistry HKEY_CURRENT_USER "Environment" "HOME" REG_SZ home;
  (* Broadcast the change (or a reboot would be required) *)
  (* HWND_BROADCAST = 0xffff; SMTO_ABORTIFHUNG = 0x2 (WinUser.h) *)
  ignore (sendMessageTimeout 0xffff 5000 0x2 WM_SETTINGCHANGE 0 "Environment")

let indent_left s ?(visual=s) nb =
  let nb = nb - String.length visual in
  if nb <= 0 then
    s
  else
    s ^ String.make nb ' '

let indent_right s ?(visual=s) nb =
  let nb = nb - String.length visual in
  if nb <= 0 then
    s
  else
    String.make nb ' ' ^ s

let sub_at n s =
  if String.length s <= n then
    s
  else
    String.sub s 0 n

(** To use when catching default exceptions: ensures we don't catch fatal errors
    like C-c *)
let fatal e = match e with
  | Sys.Break -> prerr_newline (); raise e
  | Assert_failure _ | Match_failure _ -> raise e
  | _ -> ()

let register_backtrace, get_backtrace =
  let registered_backtrace = ref None in
  (fun e ->
     registered_backtrace :=
       match !registered_backtrace with
       | Some (e1, _) as reg when e1 == e -> reg
       | _ -> Some (e, Printexc.get_backtrace ())),
  (fun e ->
     match !registered_backtrace with
     | Some(e1,bt) when e1 == e -> bt
     | _ -> Printexc.get_backtrace ())

let pretty_backtrace e =
  match get_backtrace e with
  | "" -> ""
  | b  ->
    let b = String.concat "\n  " (split b '\n') in
    Printf.sprintf "Backtrace:\n  %s\n" b

let default_columns = 100

let get_terminal_columns () =
  try           (* terminfo *)
    with_process_in "tput cols"
      (fun ic -> int_of_string (input_line ic))
  with Unix.Unix_error _ | Sys_error _ | Failure _ | End_of_file ->
    try (* GNU stty *)
      with_process_in "stty size"
        (fun ic ->
          match split (input_line ic) ' ' with
          | [_ ; v] -> int_of_string v
          | _ -> failwith "stty")
    with Unix.Unix_error _ | Sys_error _ | Failure _  | End_of_file ->
      try (* shell envvar *)
        int_of_string (getenv "COLUMNS")
      with Not_found | Failure _ ->
        default_columns

let terminal_columns =
  let v = Lazy.lazy_from_fun get_terminal_columns in
  fun () ->
    if Unix.isatty Unix.stdout
    then Lazy.force v
    else 80

let uname_m () =
  try
    with_process_in "uname -m"
      (fun ic -> Some (strip (input_line ic)))
  with Unix.Unix_error _ | Sys_error _ ->
    None

let shell_of_string = function
  | "tcsh"
  | "csh"  -> `csh
  | "zsh"  -> `zsh
  | "bash" -> `bash
  | "fish" -> `fish
  | _      ->
      if os () = Win32 then
        `cmd
    else
      `sh

let guess_shell_compat () =
  try shell_of_string (Filename.basename (getenv "SHELL"))
  with Not_found -> if os () = Win32 then `cmd else `sh

let guess_dot_profile shell =
  let home f =
    try Filename.concat (getenv "HOME") f
    with Not_found -> f in
  match shell with
  | `fish -> List.fold_left Filename.concat (home ".config") ["fish"; "config.fish"]
  | `zsh  -> home ".zshrc"
  | `bash ->
    let bash_profile = home ".bash_profile" in
    let bashrc = home ".bashrc" in
    if Sys.file_exists bash_profile then
      bash_profile
    else
      bashrc
  | `cmd ->
      (* The Command Processor doesn't have an equivalent of .profile, but we can update AutoRun.
       *)
      "HKCU\\Software\\Microsoft\\Command Processor\\AutoRun"
  | _     -> home ".profile"

let prettify_path s =
  let aux ~short ~prefix =
    let prefix = Filename.concat prefix "" in
    if starts_with ~prefix s then
      let suffix = remove_prefix ~prefix s in
      Some (Filename.concat short suffix)
    else
      None in
  try
    match aux ~short:"~" ~prefix:(getenv "HOME") with
    | Some p -> p
    | None   -> s
  with Not_found -> s

let registered_at_exit = ref []
let at_exit f =
  Pervasives.at_exit f;
  registered_at_exit := f :: !registered_at_exit
let exec_at_exit () =
  List.iter
    (fun f -> try f () with _ -> ())
    !registered_at_exit
