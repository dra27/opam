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
open OpamMisc.OP
open OpamFilename.OP

let log msg = OpamGlobals.log "CURL" msg
let slog = OpamGlobals.slog

type state = {
  remote_dir          : dirname;
  local_dir           : dirname;
  remote_index_archive: OpamFilename.uri OpamFilename.link;
  local_index_archive : filename;
  local_files         : filename_set;
  remote_local        : filename filename_map;
  local_remote        : (filename * int * string) filename_map; (* file, perms, md5 *)
}

let state_cache = ref []

let index_file local_path = local_path // "urls.txt"
let index_file_save local_path = local_path // "urls.txt.0"
let index_archive local_path = local_path // "index.tar.gz"

let local_files repo =
  let all =
    OpamPath.Repository.repo repo ::
      OpamFilename.rec_files (OpamPath.Repository.packages_dir repo) @
      OpamFilename.rec_files (OpamPath.Repository.archives_dir repo) @
      OpamFilename.rec_files (OpamPath.Repository.compilers_dir repo) in
  List.filter OpamFilename.exists all

let make_state ~download_index repo =
  if List.mem_assoc repo.repo_address !state_cache then
    List.assoc repo.repo_address !state_cache
  else (
    let repo_address = OpamFilename.raw_dir (fst repo.repo_address) in
    let remote_index_file = OpamFilename.uri repo_address "urls.txt" in
    let local_index_file = index_file repo.repo_root in
    let local_index_file_save = index_file_save repo.repo_root in
    let remote_index_archive = OpamFilename.uri repo_address "index.tar.gz" in
    let local_index_archive = repo.repo_root // "index.tar.gz" in
    let index =
      if download_index then (
        if OpamFilename.exists local_index_file then
          OpamFilename.move ~src:local_index_file ~dst:local_index_file_save;
        try
	  OpamGlobals.msg "[%s] Downloading %s\n"
	    (OpamGlobals.colorise `blue
               (OpamRepositoryName.to_string repo.repo_name))
	    (OpamFilename.uri_to_string remote_index_file);
          let file =
            OpamFilename.download ~compress:true ~overwrite:false
              remote_index_file repo.repo_root in
          OpamFilename.remove local_index_file_save;
          file;
        with e ->
          if OpamFilename.exists local_index_file_save then
            OpamFilename.move ~src:local_index_file_save ~dst:local_index_file;
          raise e
      ) else
        local_index_file in
    let remote_local, local_remote, local_files =
      let urls = OpamFile.File_attributes.read index in
      let remote_local, local_remote, locals =
        OpamFilename.Attribute.Set.fold (fun r (rl, lr, locals) ->
          let base = OpamFilename.Attribute.base r in
          let perm = match OpamFilename.Attribute.perm r with
            | None  ->  0o640
            | Some p -> p in
          let digest = OpamFilename.Attribute.md5 r in
          let remote = repo_address // OpamFilename.Base.to_string base in
          let local = OpamFilename.create repo.repo_root base in
          OpamFilename.Map.add remote local rl,
          OpamFilename.Map.add local (remote,perm,digest) lr,
          OpamFilename.Set.add local locals
        ) urls
          (OpamFilename.Map.empty,
           OpamFilename.Map.empty,
           OpamFilename.Set.empty) in
      remote_local, local_remote, locals in
    let state = {
      remote_dir = repo_address;
      local_dir  = repo.repo_root;
      remote_index_archive; local_index_archive;
      local_files; remote_local; local_remote
    } in
    state_cache := (repo.repo_address, state) :: !state_cache;
    state
  )

let preload_state repo =
  ignore (make_state ~download_index:false repo)

let is_up_to_date state local_file =
  try
    let _,_,md5 = OpamFilename.Map.find local_file state.local_remote in
    OpamFilename.exists local_file &&
    not (Sys.is_directory (OpamFilename.to_string local_file))
    && md5 = OpamFilename.digest local_file
  with Not_found -> false

let get_checksum state local_file =
  try
    let _,_,expected = OpamFilename.Map.find local_file state.local_remote in
    if OpamFilename.exists local_file &&
       not (Sys.is_directory (OpamFilename.to_string local_file))
    then
      let actual = OpamFilename.digest local_file in
      Some (actual, expected)
    else None
  with Not_found -> None

module B = struct

  let repo repo_root repo_address = {
    repo_name     = OpamRepositoryName.of_string "http";
    repo_priority = 0;
    repo_kind     = `http;
    repo_root; repo_address;
  }

  let init repo =
    log "init";
    try
      (* Download urls.txt *)
      let state = make_state ~download_index:true repo in
      try
        (* Download index.tar.gz *)
	OpamGlobals.msg "[%s] Downloading %s\n"
	  (OpamGlobals.colorise `blue
             (OpamRepositoryName.to_string repo.repo_name))
	  (OpamFilename.uri_to_string state.remote_index_archive);
        let file =
          OpamFilename.download ~overwrite:true
            state.remote_index_archive state.local_dir in
        OpamFilename.extract_in file state.local_dir
      with e ->
        OpamMisc.fatal e;
        OpamGlobals.msg
          "Cannot find index.tar.gz on the OPAM repository. \
           Initialisation might take some time.\n"
    with e ->
      OpamMisc.fatal e;
      OpamGlobals.error_and_exit "%s is unavailable."
        (OpamTypesBase.string_of_address repo.repo_address)

  let curl ~remote_file ~local_file =
    log "curl";
    log "dowloading %a" (slog OpamFilename.uri_to_string) remote_file;
    (* OpamGlobals.msg "Downloading %s\n" (OpamFilename.to_string remote_file); *)
    OpamFilename.download_as ~overwrite:true remote_file local_file

  let pull_repo repo =
    log "pull-repo";
    let local_files = local_files repo in
    let state = make_state ~download_index:true repo in
    if state.local_dir <> state.remote_dir then (
      let (--) = OpamFilename.Set.diff in
      let current = OpamFilename.Set.of_list local_files in
      let to_keep = OpamFilename.Set.filter (is_up_to_date state) state.local_files in
      let to_delete = current -- to_keep in
      let new_files =
        let archives_dir = OpamPath.Repository.archives_dir repo in
        (OpamFilename.Set.filter
           (fun f -> not (OpamFilename.starts_with archives_dir f)) state.local_files)
        -- to_keep in
      log "current: %a files"
        (slog @@ OpamFilename.Set.cardinal @> string_of_int) current;
      log "to_keep: %a files"
        (slog @@ OpamFilename.Set.cardinal @> string_of_int) to_keep;
      log "to_delete: %a"
        (slog OpamFilename.Set.to_string) to_delete;
      log "new_files: %a"
        (slog OpamFilename.Set.to_string) new_files;
      OpamFilename.Set.iter OpamFilename.remove to_delete;

      if OpamFilename.Set.cardinal new_files > 4 then
        init repo
      else
        OpamFilename.Set.iter (fun local_file ->
          let remote_file,_,_ =
            OpamFilename.Map.find local_file state.local_remote in
          OpamGlobals.msg "[%s] Downloading %s\n"
            (OpamGlobals.colorise `blue
               (OpamRepositoryName.to_string repo.repo_name))
            (OpamFilename.prettify remote_file);
          curl ~remote_file:(OpamFilename.uri_of_file remote_file) ~local_file
        ) new_files;
    )

  let pull_url package dirname checksum remote_url =
    let remote_url = OpamTypesBase.string_of_address remote_url in
    log "pull-file into %a: %s"
      (slog OpamFilename.Dir.to_string) dirname
      remote_url;
    let filename = OpamFilename.of_string remote_url in
    let uri = OpamFilename.uri_of_file filename in
    let base = OpamFilename.basename filename in
    let local_file = OpamFilename.create dirname base in
    let check_sum f = match checksum with
      | None   -> false
      | Some c -> OpamFilename.digest f = c
    in
    let files = OpamFilename.files dirname in
    let uptodate =
      let found, extra =
        List.partition (fun f -> f = local_file && check_sum f) files
      in
      if extra <> [] &&
         OpamMisc.starts_with (* Just a safeguard *)
           ~prefix:(OpamFilename.Dir.to_string (OpamPath.root ()))
           (OpamFilename.Dir.to_string dirname)
      then
        (log "Removing stale files in download dir: %a"
           (slog @@ List.map OpamFilename.to_string @> OpamMisc.pretty_list)
           extra;
         List.iter OpamFilename.remove extra);
      found <> []
    in
    if uptodate then (
      OpamGlobals.msg "[%s] %s is in the local cache, using it.\n"
        (OpamGlobals.colorise `green (OpamPackage.to_string package))
        (OpamFilename.Base.to_string base);
      Result (F local_file)
    )
    else (
      OpamGlobals.msg "[%s] Downloading %s\n"
        (OpamGlobals.colorise `green (OpamPackage.to_string package))
        (OpamFilename.to_string filename);
      try
        let local_file = OpamFilename.download ~overwrite:true uri dirname in
        OpamRepository.check_digest local_file checksum;
        Result (F local_file)
      with e ->
        OpamMisc.fatal e;
        Not_available remote_url
    )

  let pull_archive repo filename =
    log "pull-archive";
    let uri = OpamFilename.uri_of_file filename in
    let state = make_state ~download_index:false repo in
    try
      let local_file = OpamFilename.Map.find filename state.remote_local in
      if is_up_to_date state local_file then
        Up_to_date local_file
      else (
	OpamGlobals.msg "[%s] Downloading %s\n"
	  (OpamGlobals.colorise `blue
             (OpamRepositoryName.to_string repo.repo_name))
	  (OpamFilename.prettify filename);
	curl ~remote_file:uri ~local_file;
        Result local_file
      )
    with Not_found ->
      Not_available (OpamFilename.to_string filename)

  let revision _ =
    None

end

let make_urls_txt ~write repo_root =
  let repo = OpamRepository.local repo_root in
  let local_index_file = OpamFilename.of_string "urls.txt" in
  log "Scanning %a" (slog OpamFilename.Dir.to_string) repo_root;
  let index =
    List.fold_left (fun set f ->
      if not (OpamFilename.exists f) then set
      else
        let attr = OpamFilename.to_attribute repo_root f in
        OpamFilename.Attribute.Set.add attr set
    ) OpamFilename.Attribute.Set.empty (local_files repo)
  in
  if write then OpamFile.File_attributes.write local_index_file index;
  index

let make_index_tar_gz repo_root =
  OpamFilename.in_dir repo_root (fun () ->
    let dirs = [ "version"; "compilers"; "packages"; "repo" ] in
    match List.filter Sys.file_exists dirs with
    | [] -> ()
    | d  -> OpamSystem.command ("tar" :: "czf" :: "index.tar.gz" :: d)
  )

let register () =
  OpamRepository.register_backend `http (module B : OpamRepository.BACKEND)
