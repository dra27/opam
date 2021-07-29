(**************************************************************************)
(*                                                                        *)
(*    Copyright 2021 David Allsopp Ltd.                                   *)
(*                                                                        *)
(*  All rights reserved. This file is distributed under the terms of the  *)
(*  GNU Lesser General Public License version 2.1, with the special       *)
(*  exception on linking described in the file LICENSE.                   *)
(*                                                                        *)
(**************************************************************************)

(* Generator script for the GitHub Actions workflows. Primary aim is to
   eliminate duplicated YAML steps (e.g. the build step for a cache miss)
   and duplicated jobs between workflows. *)

let fprintf = Printf.fprintf

type platform = MacOS | Linux | Windows

let name_of_platform = function
| MacOS -> "macOS"
| Linux -> "Linux"
| Windows -> "Windows"

let runner_of_platform = function
| MacOS -> "macos"
| Linux -> "ubuntu"
| Windows -> "windows"

(* Prints an `env:` block *)
let emit_env ~oc ?(indent=4) env =
  let indent = String.make indent ' ' in
  fprintf oc "%senv:\n" indent;
  let emit_value (key, value) =
    let value = if value = "" then "" else " " ^ value in
    fprintf oc "%s  %s:%s\n" indent key value
  in
  List.iter emit_value env

(* Prints a string list field (not printed if value = []) *)
let emit_yaml_list ?(indent=4) ?(force_list=false) ~oc name value =
  if value <> [] then
    let indent = String.make indent ' ' in
    match value with
    | [elt] when not force_list ->
        fprintf oc "%s%s: %s\n" indent name elt
    | elts ->
        fprintf oc "%s%s: [ %s ]\n" indent name (String.concat ", " elts)

(* Prints a strategy block for a job *)
let emit_strategy ~oc (fail_fast, matrix) =
  output_string oc
{|    strategy:
      matrix:
|};
  let print_matrix (key, elts) = emit_yaml_list ~oc ~indent:8 ~force_list:true key elts in
  List.iter print_matrix matrix;
  fprintf oc "      fail-fast: %b\n" fail_fast

(* Entry point for a workflow. Workflows are specified as continuations where
   each job is passed as a continuation to the [workflow], terminated with
   {!end_workflow}. *)
let workflow ~oc ~platform ~env f =
  fprintf oc
{|name: %s

on: [ push, pull_request ]
|} (name_of_platform platform);
  if env <> [] then begin
    output_char oc '\n';
    emit_env ~oc ~indent:0 env
  end;
  output_string oc
{|
defaults:
  run:
    shell: bash

jobs:
|};
  f ~oc ~platform

let end_workflow ~oc ~platform = ()

(* Continuation for a job. Steps are specified as continuations as for
   the jobs within the workflow, terminated with {!end_job}. *)
let job ?section ?(needs = []) ?matrix ?env name ~oc ~platform f =
  output_char oc '\n';
  let emit_section =
    fprintf oc
{|####
# %s
####
|} in
  Option.iter emit_section section;
  fprintf oc
{|  %s:
    runs-on: %s-latest
|} name (runner_of_platform platform);
  emit_yaml_list ~oc "needs" needs;
  Option.iter (emit_strategy ~oc) matrix;
  Option.iter (emit_env ~oc) env;
  output_string oc "    steps:\n";
  f ~oc ~platform ~job:name

(* Prints the given yaml steps *)
let steps yaml =
  let process yaml ~oc ~platform ~job f =
    output_string oc yaml;
    f ~oc ~platform ~job
  in
  Printf.ksprintf process yaml

let end_job ~oc ~platform ~job f = f ~oc ~platform

let continue_steps ~oc ~platform ~job f = f ~oc ~platform ~job

let skip_job ~oc ~platform f = f ~oc ~platform

(* [only_on platform job] skips [job] if the workflow being generated is not
   [platform]. *)
let only_on plat job ~oc ~platform =
  if platform = plat then
    job ~oc ~platform
  else
    skip_job ~oc ~platform

(* Left-associative version of (@@) which allows combining jobs and steps
   without parentheses. *)
let (++) = (@@)

(* Prints the [if:] clause for a cache miss *)
let on_cache_miss ~oc =
  Option.iter (fprintf oc "      if: steps.%s.outputs.cache-hit != 'true'\n")

let checkout ?cache_name () ~oc ~platform ~job f =
  output_string oc "    - uses: actions/checkout@v2\n";
  on_cache_miss ~oc cache_name;
  f ~checkout:() ~oc ~platform ~job

let ocamls =
  let ocamls =
    ["4.03.0"; "4.04.2"; "4.05.0"; "4.06.1"; "4.07.1"; (* Legacy *)
     "4.08.1"; "4.09.1"; "4.10.2"; "4.11.2"; "4.12.0"] in        (* Current *)
  List.map (fun v -> Scanf.sscanf v "%u.%u.%u" (fun major minor _ -> ((major, minor), v))) ocamls

let rec drop_while f = function
| [] -> []
| (h::tl) as l -> if f h then drop_while f tl else l

let rec take_until f = function
| [] -> []
| h::tl -> if f h then h::take_until f tl else []

let platform_ocaml_matrix ?(dir=drop_while) platform ~fail_fast start_version =
  (fail_fast,
   [("os", [name_of_platform platform]);
    ("ocamlv", List.map snd (dir (fun ocaml -> fst ocaml < start_version) ocamls))])

let archives_cache ~checkout ~oc ~platform ~job f =
  fprintf oc
{|    - name: src ext archives cache
      id: archives
      uses: actions/cache@v2
      with:
        path: |
          src_ext/archives
          ~/opam-repository
        key: archives-${{ runner.os }}-${{ hashFiles('src_ext/Makefile.sources', 'src_ext/Makefile') }}-${{ env.OPAM_REPO_SHA }}
    - name: Retrieve archives
      if: steps.archives.outputs.cache-hit != 'true'
      run: bash -exu .github/scripts/archives-cache.sh
|};
  f ~archives:() ~oc ~platform ~job

let archives_cache_job ~archives_job_name ~oc ~platform =
  job ~oc ~platform ~section:"Caches" archives_job_name
    ++ checkout () (fun ~checkout ->
         archives_cache ~checkout (fun ~archives -> continue_steps)
       )
    ++ end_job

let retrieve_legacy_cache ~oc ~platform ~job f =
  fprintf oc
{|    - name: legacy cache
      id: legacy
      uses: actions/cache@v2
      with:
        path: ~/.opam
        key: legacy-${{ runner.os }}-${{ env.OPAM_REPO_SHA }}
|};
  f ~legacy_cache:"legacy" ~oc ~platform ~job

let install_platform_package = function
| Linux -> Printf.sprintf "sudo apt install %s"
| _ -> assert false

let install_sys_sandbox ?cache_name () ~oc ~platform ~job f =
  if platform = Linux then begin
    output_string oc "    - name: install deps\n";
    on_cache_miss ~oc cache_name;
    fprintf oc "      run: %s\n" (install_platform_package platform "bubblewrap");
  end;
  f ~sandbox:() ~oc ~platform ~job

let install_sys_opam ?cache_name () ~oc ~platform ~job f =
  output_string oc "    - name: install deps\n";
  on_cache_miss ~oc cache_name;
  fprintf oc "      run: %s\n" (install_platform_package platform "opam");
  f ~opam:() ~sandbox:() ~oc ~platform ~job

let build_legacy_cache ~opam ~ocaml ~checkout ~legacy_cache ~oc =
  output_string oc
{|    - name: Build ocaml-secondary-compiler
      if: steps.legacy.outputs.cache-hit != 'true'
      run: bash -exu .github/scripts/legacy-cache.sh
|};
  continue_steps ~oc

let bootstrap_cache ~checkout ?(prefix="") ~oc ~platform ~job f =
  fprintf oc
{|    - name: opam bootstrap cache
      id: opam-bootstrap
      uses: actions/cache@v2
      with:
        path: |
          ${{ env.OPAMBSROOT }}/**
          ~/.cache/opam-local/bin/**
        key: opam-%s${{ runner.os }}-${{ env.OPAMBSVERSION }}-${{ matrix.ocamlv }}-${{ env.OPAM_REPO_SHA }}-${{ hashFiles ('.github/scripts/opam-bs-cache.sh', '.github/scripts/preamble.sh') }}
    - name: opam root cache
      if: steps.opam-bootstrap.outputs.cache-hit != 'true'
      run: bash -exu .github/scripts/opam-bs-cache.sh
|} prefix;
  f ~opam_bs:() ~oc ~platform ~job

let ocaml_cache ?(suffix="") ?cache_name version ~checkout ~oc ~platform ~job f =
  fprintf oc
{|    - name: ocaml %s cache
|} version;
  on_cache_miss ~oc cache_name;
  let cache = Option.value ~default:"" @@ Option.map (Printf.sprintf " && steps.%s.outputs.cache-hit != 'true'") cache_name in
  fprintf oc
{|      id: ocaml-cache
      uses: actions/cache@v2
      with:
        path: ${{ env.GH_OCAML_CACHE }}
        key: ${{ runner.os }}-ocaml-%s-${{ hashFiles ('.github/scripts/ocaml-cache.sh', '.github/scripts/preamble.sh') }}%s
    - name: Building ocaml %s cache
      if: steps.ocaml-cache.outputs.cache-hit != 'true'%s
      env:
        OCAML_VERSION: %s
      run: bash -exu .github/scripts/ocaml-cache.sh ocaml
|} version suffix version cache version;
  f ~ocaml:version ~oc ~platform ~job

let legacy_cache_job ~legacy_job_name ~oc ~platform =
  job ~oc ~platform legacy_job_name
    ++ retrieve_legacy_cache (fun ~legacy_cache ->
         install_sys_opam ~cache_name:legacy_cache () (fun ~opam ~sandbox ->
           checkout ~cache_name:legacy_cache () (fun ~checkout ->
             ocaml_cache ~cache_name:legacy_cache "4.03.0" ~checkout (fun ~ocaml ->
               build_legacy_cache ~opam ~ocaml ~checkout ~legacy_cache
             )
           )
         )
       )
    ++ end_job

let main_build_job ~archives_job_name ~build_job_name ~start_version ~oc ~platform =
  (* Intentionally fail fast, no need to run all build if there is a
   * problem in a given version; usually it is functions not defined in lower
   * versions of OCaml. *)
  let matrix = platform_ocaml_matrix platform ~fail_fast:true start_version in
  job ~section:"Build" ~oc ~platform ~needs:[archives_job_name] ~matrix build_job_name
    ++ install_sys_sandbox () (fun ~sandbox ->
         checkout () (fun ~checkout ->
           archives_cache ~checkout (fun ~archives ->
             ocaml_cache "${{ matrix.ocamlv }}" ~checkout (fun ~ocaml ->
               steps
{|    - name: Build
      env:
        OCAML_VERSION: ${{ matrix.ocamlv }}
      run: bash -exu .github/scripts/main.sh
|}
             )
           )
         )
       )
    ++ end_job

let build_legacy ~oc =
  output_string oc
{|    - name: Build
      env:
        OCAML_VERSION: ${{ matrix.ocamlv }}
      run: bash -exu .github/scripts/legacy.sh
|};
  continue_steps ~oc

let legacy_build_job ~legacy_job_name ~start_version ~oc ~platform =
  (* Intentionally fail fast, no need to run all build if there is a
   * problem in a given version; usually it is functions not defined in lower
   * versions of OCaml. *)
  let matrix = platform_ocaml_matrix ~dir:take_until platform ~fail_fast:true start_version in
  job ~section:"Legacy" ~oc ~platform ~needs:[legacy_job_name] ~matrix "legacy"
    ++ install_sys_opam () (fun ~opam ~sandbox ->
         checkout () (fun ~checkout ->
           retrieve_legacy_cache (fun ~legacy_cache ->
             ocaml_cache "${{ matrix.ocamlv }}" ~checkout (fun ~ocaml ->
               build_legacy_cache ~opam ~ocaml ~checkout ~legacy_cache
             )
           )
         )
       )
    ++ build_legacy
    ++ end_job

let single_ocaml version = ("ocamlv", [snd @@ List.find (fun (v, _) -> v = version) ocamls])

let tests_job ~archives_job_name ~build_job_name ~version ~oc ~platform =
  let matrix = (false, [("os", [name_of_platform platform]); single_ocaml version]) in
  job ~section:"Opam tests" ~oc ~platform ~needs:[build_job_name; archives_job_name] ~matrix ~env:[("OPAM_TEST", "1")] "test"
    ++ checkout () (fun ~checkout ->
         install_sys_sandbox () (fun ~sandbox ->
           archives_cache ~checkout (fun ~archives ->
             ocaml_cache ~suffix:"-test" "${{ matrix.ocamlv }}" ~checkout (fun ~ocaml ->
               bootstrap_cache ~checkout (fun ~opam_bs ->
                 steps
{|    - name: opam-rt cache
      uses: actions/cache@v2
      with:
        path: ~/.cache/opam-rt/**
        key: ${{ runner.os }}-opam-rt-${{ matrix.ocamlv }}
    - name: Test
      env:
        OCAML_VERSION: ${{ matrix.ocamlv }}
      run: bash -exu .github/scripts/main.sh
|}
              )
             )
           )
         )
       )
    ++ end_job

let cold_job ~archives_job_name ~build_job_name ~version ~oc ~platform =
  let matrix = (false, [("os", [name_of_platform platform]); single_ocaml version]) in
  job ~section:"Opam cold" ~oc ~platform ~needs:[build_job_name; archives_job_name] ~matrix "cold"
    ++ install_sys_sandbox () (fun ~sandbox ->
         checkout () (fun ~checkout ->
           archives_cache ~checkout (fun ~archives ->
             steps
{|    - name: Cold
      env:
        OCAML_VERSION: ${{ matrix.ocamlv }}
        OPAM_COLD: 1
      run: |
        make compiler
        make lib-pkg
        bash -exu .github/scripts/main.sh
|}
           )
         )
       )
    ++ end_job

let solvers_job ~archives_job_name ~build_job_name ~version ~oc ~platform =
  let opambsroot = "~/.cache/opam.${{ matrix.solver }}.cached" in
  let matrix = (false, [("os", [name_of_platform platform]);
                        single_ocaml version;
                        ("solver", ["z3"; "0install"])]) in
  let env = [("SOLVER", "${{ matrix.solver }}");
             ("OPAMBSROOT", opambsroot)] in
  job ~section:"Compile solver backends" ~oc ~platform ~needs:[build_job_name; archives_job_name] ~matrix ~env "solvers"
    ++ checkout () (fun ~checkout ->
         install_sys_sandbox () (fun ~sandbox ->
           ocaml_cache ~suffix:"-test" "${{ matrix.ocamlv }}" ~checkout (fun ~ocaml ->
             archives_cache ~checkout (fun ~archives ->
               bootstrap_cache ~checkout ~prefix:"${{ matrix.solver }}-" (fun ~opam_bs ->
                 steps
{|    - name: Compile
      env:
        OCAML_VERSION: ${{ matrix.ocamlv }}
      run: bash -exu .github/scripts/solvers.sh
|}
              )
             )
           )
         )
       )
    ++ end_job

let upgrade_job ~build_job_name ~version ~oc ~platform =
  let matrix = (false, [("os", [name_of_platform platform]); single_ocaml version]) in
  job ~section:"Upgrade from 1.2 to current" ~oc ~platform ~needs:[build_job_name] ~matrix "upgrade"
    ++ install_sys_sandbox () (fun ~sandbox ->
         checkout () (fun ~checkout ->
           ocaml_cache "${{ matrix.ocamlv }}" ~checkout (fun ~ocaml ->
             steps
{|    - name: opam 1.2 root cache
      uses: actions/cache@v2
      with:
        path: ${{ env.OPAM12CACHE }}
        key: ${{ runner.os }}-opam1.2-root
    - name: Upgrade
      env:
        OCAML_VERSION: ${{ matrix.ocamlv }}
        OPAM_UPGRADE: 1
      run: bash -exu .github/scripts/main.sh
|}
           )
         )
       )
    ++ end_job

let hygiene_job ~archives_job_name ~oc ~platform =
  job ~section:"Around opam tests" ~oc ~platform ~needs:[archives_job_name] "hygiene"
    ++ checkout () (fun ~checkout ->
         archives_cache ~checkout (fun ~archives ->
           steps
{|    - name: Hygiene
      env:
        # Defined only on pull request jobs
        BASE_REF_SHA: ${{ github.event.pull_request.base.sha }}
        PR_REF_SHA: ${{ github.event.pull_request.head.sha }}
      run: bash -exu .github/scripts/hygiene.sh
|}
         )
       )
    ++ end_job

let main oc platform =
  let env = [
    ("OPAMBSVERSION", "2.1.0");
    ("OPAMBSROOT", "~/.cache/.opam.cached");
    ("OPAM12CACHE", "~/.cache/opam1.2/cache");
    (* These should be identical to the values in appveyor.yml *)
    ("OPAM_REPO", "https://github.com/dra27/opam-repository.git");
    ("OPAM_TEST_REPO_SHA", "02ead5a557d118a8d7de05edeae25d2301325a7a");
    ("OPAM_REPO_SHA", "03356a3912d5717064abf00fe0004f6f1e314305");
    (* Default ocaml version for some jobs *)
    ("OCAML_VERSION", "4.11.2");
    (*  variables for cache paths *)
    ("GH_OCAML_CACHE", "~/.cache/ocaml-local/**");
    ("SOLVER", "");
  ] in 
  let archives_job_name = "archives-cache" in
  let legacy_job_name = "legacy-cache" in
  let build_job_name = "build" in
  let start_version =
    if platform = Linux then
      (4, 8) (* Build 4.08+ on Linux *)
    else
      (4, 12) in
  let version = (4, 11) in
  workflow ~oc ~platform ~env
    ++ archives_cache_job ~archives_job_name
    ++ only_on Linux (legacy_cache_job ~legacy_job_name)
    ++ main_build_job ~archives_job_name ~build_job_name ~start_version
    ++ only_on Linux (legacy_build_job ~legacy_job_name ~start_version)
    ++ tests_job ~archives_job_name ~build_job_name ~version
    ++ only_on Linux (cold_job ~archives_job_name ~build_job_name ~version)
    ++ solvers_job ~archives_job_name ~build_job_name ~version
    ++ upgrade_job ~build_job_name ~version
    ++ only_on Linux (hygiene_job ~archives_job_name)
    ++ end_workflow

let () =
  let pipelines =
    [(main, "ubuntu", Linux);
     (main, "macos", MacOS)]
  in
  let generate (pipeline, yaml, platform) =
    let oc = open_out (yaml ^ ".yml") in
    pipeline oc platform;
    close_out oc
  in
  List.iter generate pipelines
