#directory "C:/DRA/opam/_build/install/default/lib/opam-admin";;
#directory "C:/DRA/opam/_build/install/default/lib/opam-repository";;
#directory "C:/DRA/opam/_build/install/default/lib/opam-core";;
#directory "C:/DRA/opam/_build/install/default/lib/opam-format";;
#directory "C:/DRA/opam/_build/install/default/lib/re";;
#directory "C:/DRA/opam/_build/install/default/lib/re/pcre";;

open Opam_admin_top;;
open OpamTypes;;

let carriage_delete () =
  if OpamStd.(Sys.os () = Sys.Win32) then
    Printf.sprintf "\r%s\r" (String.make (OpamStd.Sys.terminal_columns () - 1) ' ')
  else
    "\r\027[K" in
iter_packages (*~margin:150*) ~opam:(fun package opam ->
    let module O = OpamFile.OPAM in
    if (OpamPackage.name package |> OpamPackage.Name.to_string) = "ocaml-base-compiler" then
      let version = OpamPackage.version package in
      let str_version = OpamPackage.Version.to_string version in
      if str_version <> "system" then
        let clear =
          let clear = ref false in
          fun () ->
            if not !clear then begin
              clear := true;
              print_string (carriage_delete ())
            end
        in
        (* These are compiler variants which are expressly disabled for Windows *)
        let not_for_windows =
          OpamStd.String.Set.of_list [
            "PIC"; "fPIC"; (* All code is position-independent on Windows *)
            "fp"; "fp+flambda"; "trunk+fp"; "trunk+fp+flambda"; (* -with-frame-pointers not supported on Windows *)
            "lsb"; (* Linux-specific *)
            "bin-ocp"; (* Broken anyway *)
            "32bit"; (* configure-specific - Windows ports selected differently *)
            "rc1"; (* Old release candidates and betas not being enabled *)
            "armv6-freebsd"; "raspberrypi"; (* !! *)
            "BER";  (* Windows support not yet implemented *)
            "statistical-memprof"; (* Windows support not yet implemented *)
            "bytecode-only"; (* Windows build system at present doesn't support building bytecode only *)
            "mirage-xen"; "mirage-unix"; (* Not for Windows? *)
            "musl"; "musl+static"; (* Linux-specific *)
          ] in
        let recognised_flags =
          OpamStd.String.Set.of_list [
            "trunk"; "trunk+flambda"; "trunk+safe-string"; "flambda"
          ] in
        let allowed_patches =
          OpamStd.String.Set.of_list [
            "annot";
            "buckle-1";
            "curried-constr";
            "french";
            "improved-errors";
            "jocaml";
            "modular-implicits-ber";
            "modular-implicits";
            "open-types";
            "short-types";
            "trunk+forced_lto"
          ] in
        (* Build system patches from https:/github.com/metastack/ocaml-legacy *)
        let build_patches =
          let patches = [
            (* GPR405 enabling Visual Studio 2015 compilation support *)
            ("GPR405-to-4.01.0", "1536effeecbcacd079390abd57cfe31b", "3.07", "4.01.0", true, []);
            ("GPR405-to-4.02.1", "81de83791cb4f1ccb022abc8b542b42d", "4.02.0", "4.02.1", true, []);
            ("GPR405", "7507593816415e330d6f0669de729cf6", "4.02.2", "4.02.3", true, ["4.02"]);
            (* GPR465 (this must appear before cc-profile, or 3.10.x won't build *)
            ("gpr%23465-3.09.0%2B", "d206a404c8795c34c6fb86a175b027fe", "3.07", "3.11.2", false, []);
            ("gpr%23465-3.12.0%2B", "35d8fca8437d5a900497b16324863b46", "3.12.0", "4.04.0", false, ["4.02"; "4.03"; "4.04"]);
            (* GPR582 installing the .cmx files from the threads library *)
            ("GPR582", "45c486b419ce72d53641b5fc9f7d6a34", "4.03.0", "4.03.0", true, []);
            (* GPR658 supporting back-slashes properly in the output of -where commands *)
            ("GPR658-to-3.09.3", "3149c70871af31d178a2a3f4844d0ec2", "3.07", "3.09.3", true, []);
            ("GPR658-to-3.10.2", "4e6f0526c6ce1fac8c63f6fe0ffd5075", "3.10.0", "3.10.2", true, []);
            ("GPR658-3.11.0", "2cdcd1ed7fbc42f5022bd5825a395e58", "3.11.0", "3.11.0", true, []);
            ("GPR658-to-3.11.2", "869d3ddfa02239eeb5c647c16b5b3e32", "3.11.1", "3.11.2", true, []);
            ("GPR658-to-4.01.0", "f1348b8495608a8ce6553b272ea4e2d2", "3.12.0", "4.01.0", true, []);
            ("GPR658-to-4.02.1", "fb242e9701e074010f833a3db5de0ad9", "4.02.0", "4.02.1", true, []);
            ("GPR658-to-4.02.3", "e6d1d60cd86dfd605ab79682275ff4b2", "4.02.2", "4.02.3", true, ["4.02"]);
            ("GPR658", "666ca9e439b718e741d08c4702926004", "4.03.0", "4.04.0", true, ["4.03"; "4.04"]);
            (* GPR678 fixing Graphics.close_graph in 4.01.0+ and allowing the X button to unblock
               calls to Graphics.wait_next_event in 3.08.0-4.00.1 *)
            ("GPR678-to-4.00.1", "106454e5e5bf88e447e96837abef0957", "3.08.0", "4.00.1", true, []);
            ("GPR678-4.01.0", "06b9c8dd0a8fe4495245356243d17900", "4.01.0", "4.01.0", true, []);
            ("GPR678", "8544ea38f1fad93b471694c0d32028d8", "4.02.0", "4.03.0", true, ["4.02"; "4.03"]);
            (* Add -config option to 3.07 and 3.08x *)
            ("config-option-3.07", "522ae27987d91e020a165628b0548bf5", "3.07", "3.07+2", false, []);
            ("config-option-3.08", "b1005263922b7ae3fe0c64cd37f00b78", "3.08.0", "3.08.4", false, []);
            (* Fix the display of %%CC_PROFILE%% in ocamlc -config *)
            ("cc-profile", "71ebd6a61589c60529886ad29f27a6c4", "3.07", "3.10.2", true, []);
            (* Remove /debugtype:cv from older compilers *)
            ("debugtype-to-3.08.2", "682e5798ea9dad4324baa8dd85ac2a73", "3.07", "3.08.2", true, []);
            ("debugtype-to-3.09.2", "76751d177c74504010e04f888dbae832", "3.08.3", "3.09.2", true, []);
            ("debugtype-3.09.3", "c4bb9af3306b5edefeb6181f1a5e6183", "3.09.3", "3.09.3", true, []);
            (* *-w64-mingw32-* compilers instead of -mno-cygwin *)
            ("mingw-to-3.08.4", "aa596f7daef4a641cb3757a73cd430e7", "3.07", "3.08.4", true, []);
            ("mingw-to-3.09.3", "2cd86833385b0a43c57e5c8705c5f353", "3.09.0", "3.09.3", true, []);
            ("mingw-to-3.10.2", "361db179ca1f69d6ed6aec195cf06ad8", "3.10.0", "3.10.2", true, []);
            ("mingw-to-3.12.1", "93721cd96038174f0a34c8dab415cbdd", "3.11.0", "3.12.1", true, []);
            (* Use i686-w64-mingw32- versions of tools for -pack in 3.07-3.09 *)
            ("msvc-to-3.08.4", "147e47203cfccc34477af78cbdba741a", "3.07", "3.08.4", true, []);
            ("msvc-3.09", "c0539ace88384f821a82678943faca79", "3.09.0", "3.09.3", true, []);
            (* Remove reference to bufferoverflowU.lib *)
            ("msvc64-3.10", "3283dfca7ee6a9c11b8f63132a4b8f98", "3.10.0", "3.10.2", true, []);
            ("msvc64-3.11", "b4396c0d4eb26ee5baafeb2000bfffb0", "3.11.0", "3.11.2", true, []);
            (* Very strange spacing in ocamldoc/Makefile.nt *)
            ("ocamldoc-3.07", "bdc202f94efe667464ecc4f4dd5f2048", "3.07", "3.07+2", true, []);
            (* French accents in ocamldoc\*.ml interfering with modern grep *)
            ("ocamldoc-build", "3bb063f019cd5a801ff2c8ab1965a266", "3.07", "4.00.1", true, []);
            (* Eliminate a GCC warning in -output-obj in 3.07 *)
            ("output-obj", "8da0d2bb479ee099b50e77e6452ba127", "3.07", "3.07+2", false, []);
            (* Enable graphics library on 3.08.4 *)
            ("win32-graph", "bd743e4275b75ff796384be471344e5d", "3.08.4", "3.08.4", true, []);
            (* Fix building of ocamlrund.exe *)
            ("win-runtimed-to-4.00.1", "ad5523fb98c08c261865170ca071ec33", "3.11.0", "4.00.1", true, []);
            ("win-runtimed", "baded8ba704d8bafb0b9ad58973825d1", "4.01.0", "4.02.1", true, []);
            (* Enable 64-bit labltk in all applicable versions *)
            ("tcl-tk-amd64-4.x", "0bf4a5ae41ad89c8773191fc1e361ae6", "4.00.0", "4.01.0", true, []);
            ("tcl-tk-amd64-3.11-85", "16aadedcb6d57aaf023db43444848a41", "3.11.2", "3.12.1", true, []);
            ("tcl-tk-amd64-3.11-84", "3ed4a33515635077514157d61e7acd00", "3.11.0", "3.11.1", true, []);
            ("tcl-tk-amd64-3.10", "242e0ae0e97f167e942b0e52cb9d1ac3", "3.10.0", "3.10.2", true, []);
            (* Fix building debug runtime. Note that this may apply some/all of 3.07-4.00.1 *)
            ("GPR820-4.00", "9f990fff9c959d81fa1874a0e7cc66d2", "4.00.0", "4.00.1", true, []);
            ("GPR820", "65af8ed87a308d6e2d00fdfcb521c805", "4.01.0", "4.02.0", true, []);
            ("GPR820-4.02.1", "2062b0721325fc61351927761e0f9c18", "4.02.1", "4.02.1", true, []);
            ("GPR820-4.02.2+", "0890b265759b825a94792d8a787c5c53", "4.02.2", "4.03.0", true, ["4.02"; "4.03"]);
            (* Fix Cygwin problem renaming .exe files fixed in 3.08.3 *)
            ("PR3485", "977d8435713f3442fad50b42e94f9171", "3.07", "3.08.2", true, []);
            (* Fix compilation with Visual Studio 2015 *)
            ("PR3821-to-3.08.2", "bfa93736ae0bc863b75503842df252df", "3.07", "3.08.2", true, []);
            ("PR3821", "7972d7593a359b51fd9ce4cf43d5c5bd", "3.08.3", "3.09.3", true, []);
            (* Fix OCaml 3.10.1 on MSVC (and other strict ANSI C compilers) *)
            ("PR4483", "ca9b901265ed9034c81d50007fe6168d", "3.10.1", "3.10.1", false, []);
            (* Fix \r characters appearing in ocamlbuild -where *)
            ("PR4575", "7fdaa6ee9267762fdfd3cfcb3d73af9e", "3.10.0", "3.10.2", true, []);
            (* Back-ports enabling Tcl/Tk 8.5 prior to 3.11.0 *)
            ("PR4614", "149f851a633ea90e7314be31bdac62fc", "3.07", "3.10.2", false, []);
            (* Back-ports labltk.bat from 3.12.0 for 3.11.x *)
            ("PR4683", "43d443fa93f09e3caa5bc3f4cd82fd94", "3.11.0", "3.11.2", true, []);
            (* Disable the tkanim library when compiling with Tcl/Tk 8.5 and later.
               OCaml 3.11.x compiles a broken version; for 3.10.x and earlier, the
               build actually fails. *)
            ("PR4700", "14ee232da5b97028ab64ba319b61a4c6", "3.07", "3.11.2", true, []);
            (* Back-port fix from OCaml 3.11.2 enabling -output-obj on MSVC64 *)
            ("PR4847-3.10.x", "a8ed3f7e644a164c3b8486a55fd2cf02", "3.10.0", "3.10.2", false, []);
            ("PR4847", "c58d4414747b32e453a131dd45a5b389", "3.11.0", "3.11.1", false, []);
            (* Back-port changes from OCaml 4.01.0 enabling Tcl/Tk 8.6 *)
            ("PR5011", "e18e8224835c0766fcee767be9105360", "3.07", "3.10.2", false, []);
            ("PR5011-3.11", "b2b2dc404a22304baa03d05f4e7831f9", "3.11.0", "3.11.2", false, []);
            ("PR5011-3.12+4.00", "83536dd1f9eb292091391f139dae702a", "3.12.0", "4.00.1", false, []);
            (* Back-port a fix from OCaml 4.00.0 so that ocamlmktop is correctly installed *)
            ("PR5331", "6c698e3bc682259d556d570c1c49b5aa", "3.12.1", "3.12.1", true, []);
            (* Back-port a fix to systhreads from 4.03.0 allowing graceful termination of programs *)
            ("PR6766", "f09039decccfc8c31286475a915724ed", "3.12.0", "4.02.3", true, ["4.02"]);
            (* Back-port a fix to utils/ccomp.ml from 4.03.0 allowing -output-complete-obj to work in 4.02.2 and 4.02.3 *)
            ("PR6797", "ec342fc5e47504c41addbf8a7910047a", "4.02.2", "4.02.3", true, ["4.02"]);
            (* Fix 64-bit MSVC ports in Windows 10 *)
            ("GPR912", "e4f9ae930c11e3fece95b08a849a2cd5", "4.04.0", "4.04.0", true, []);
          ] in
          let base = "https://raw.githubusercontent.com/metastack/ocaml-legacy/2fc7d01bc27c3f099ddc64ca8450bc9d858a01a4/" in
          let f (patch, md5, from_version, to_version, windows_only, trunks) =
            let patch = patch ^ ".patch" in
            (OpamFilename.Base.of_string patch, base ^ patch, md5, OpamPackage.Version.of_string from_version, OpamPackage.Version.of_string to_version, windows_only, List.fold_left (fun acc ver -> OpamPackage.Version.Set.add (OpamPackage.Version.of_string (ver ^ ".0")) acc) OpamPackage.Version.Set.empty trunks)
          in
          List.map f patches
        in
        let build_info =
          let only version =
            let version = OpamPackage.Version.of_string version in
            fun vn -> OpamPackage.Version.compare vn version = 0
          in
          let series major minor =
            let upper = Printf.sprintf "%d.%d" major (succ minor) |> OpamPackage.Version.of_string in
            let lower = Printf.sprintf "%d.%d" major minor |> OpamPackage.Version.of_string in
            fun version ->
              OpamPackage.Version.compare version lower >= 0 && OpamPackage.Version.compare version upper < 0
          in
          let info = List.rev [
            (series 3 07, None, None, Some "8.3");
            (series 3 08, None, None, Some "8.3");
            (series 3 09, None, None, Some "8.3");
            (series 3 10, None, None, Some "8.4");
            (only "3.11.0", Some "0.13", None, Some "8.4");
            (only "3.11.1", Some "0.19", None, Some "8.4");
            (only "3.11.2", Some "0.22", None, Some "8.5");
            (only "3.12.0", Some "0.25", Some "0.23", Some "8.5");
            (only "3.12.1", Some "0.26", Some "0.23", Some "8.5");
            (only "4.00.0", Some "0.29", Some "0.29", Some "8.5");
            (* OCaml 4.00.1 mingw doesn't build with flexlink 0.30 (str library fails) *)
            (only "4.00.1", Some "0.31", Some "0.29", Some "8.5");
            (only "4.01.0", Some "0.31", Some "0.31", Some "8.5");
            (only "4.02.0", Some "0.31", Some "0.31", None);
            (only "4.02.1", Some "0.32", Some "0.31", None);
            (only "4.02.2", Some "0.34", Some "0.31", None);
            (only "4.02.3", Some "0.34", Some "0.31", None);
            (only "4.03.0", Some "0.35", Some "0.35", None);
            (series 4 04, Some "0.35", Some "0.35", None);
            (series 4 05, Some "0.35", Some "0.35", None);
            (series 4 06, Some "0.35", Some "0.35", None);
          ] in
          fun version ->
            let (_, a, b, c) = List.find (fun (f, _, _, _) -> f version) info
            in
            (a, b, c)
        in
        let get_patch (patch, _, _, _, _, windows_only, _) =
          (patch, if windows_only then Some (FOp (FIdent ([], OpamVariable.of_string "os", None), `Eq, FString "win32")) else None)
        in
        let get_source (patch, url, md5, _, _, _, _) =
          (patch, OpamFile.URL.create ~checksum:[OpamHash.of_string ("md5=" ^ md5)] (OpamUrl.of_string url))
        in
        let filter_patches f version patches =
          let f ((_, _, _, from_version, to_version, _, _) as patch) =
            if OpamPackage.Version.(compare version from_version >= 0 && compare version to_version <= 0) then
              Some (f patch)
            else
              None
          in
          OpamStd.List.filter_map f build_patches |> List.append patches
        in
        let convert_caml_ld_path envs =
          let f ((name, op, value, comment) as elt) =
            if name = "CAML_LD_LIBRARY_PATH" && value = "%{lib}%/stublibs" then
              (name, op, "%<%{lib}%/stublibs>%", comment)
            else
              elt
          in
          List.map f envs
        in
        let convert_paths commands =
          let f (command, filter) =
            let f = function
            | (CString s, filter) ->
                let rex = Re.(compile @@ seq [str "%{"; diff notnl (set " }") |> rep1; str "}%"; diff notnl (set " ") |> rep |> greedy]) in
                let subst s =
                  let rex = Re.(compile @@ alt [str "%{"; str "}%"]) in
                  "%{<" ^ Re_pcre.substitute ~rex ~subst:(fun _ -> "$") s ^ "}%"
                in
                (CString (Re_pcre.substitute ~rex ~subst s), filter)
            | elt ->
                elt
            in
            (List.map f command, filter)
          in
          List.map f commands
        in
        let windows_filter =
          FOp (FIdent ([], OpamVariable.of_string "os", None), `Eq, FString "win32")
        in
        let not_windows_filter =
          FOp (FIdent ([], OpamVariable.of_string "os", None), `Neq, FString "win32")
        in
        let ocaml_3_10_0 = OpamPackage.Version.of_string "3.10.0" in
        let ocaml_3_11_0 = OpamPackage.Version.of_string "3.11.0" in
        let ocaml_3_12_0 = OpamPackage.Version.of_string "3.12.0" in
        let ocaml_4_00_0 = OpamPackage.Version.of_string "4.00.0" in
        let ocaml_4_01_0 = OpamPackage.Version.of_string "4.01.0" in
        let ocaml_4_02_3 = OpamPackage.Version.of_string "4.02.3" in
        let ocaml_4_03_0 = OpamPackage.Version.of_string "4.03.0" in
        let ocaml_4_04_0 = OpamPackage.Version.of_string "4.04.0" in
        let flexdll_0_29 = OpamPackage.Version.of_string "0.29" in
        let adapt_build version flags patch commands =
          let rec f acc = function
          | (((CString "./configure", None)::_) as command, None)::commands ->
              let configuration =
                let cflags = List.map (fun x -> CString x) flags in
                if OpamPackage.Version.compare version ocaml_4_01_0 >= 0 && not (List.mem "-with-debug-runtime" flags) && patch <> "open-types" then
                  (CString "-with-debug-runtime")::cflags
                else
                  cflags in
              let tcltk =
                if OpamPackage.Version.compare version ocaml_4_01_0 <= 0 then
                  CIdent "win32-tcl-tk:lib"::CIdent "win32-tcl-tk:version"::CIdent "compiler:a"::configuration
                else
                  configuration in
              let flexdll =
                if OpamPackage.Version.compare version ocaml_4_03_0 >= 0 then
                  CIdent "flexdll:share"::tcltk
                else if OpamPackage.Version.compare version ocaml_3_11_0 >= 0 then
                  CIdent "flexdll:lib"::tcltk
                else
                  tcltk in
              let config =
                CIdent "compiler:ocaml-win-conf"::CIdent "prefix"::flexdll in
              let params =
                if OpamPackage.Version.compare version  ocaml_3_11_0 >= 0 then
                  (CString (OpamPackage.Version.to_string version))::config
                else
                  config in
              let win_sh =
                ((CString "./win.sh", None)::(List.map (fun i -> (i, None)) params), Some windows_filter)
              in
              let acc = win_sh::(command, Some not_windows_filter)::acc in
              let acc =
                if patch = "trunk+forced_lto" then
                  ([(CString "bash", None); (CString "-c", None); (CString "echo CMX_CONTAINS_ALL_CODE=true>>config/Makefile", None)], Some windows_filter)::acc
                else
                  acc
              in
              let acc =
                if OpamPackage.Version.compare version ocaml_4_03_0 >= 0 then
                  ([(CIdent "make", None); (CString "flexdll", None)], Some windows_filter)::acc
                else
                  acc
              in
              let win_sh =
                (*
                 * Original version with multiple scripts
                if OpamPackage.Version.compare version ocaml_4_03_0 >= 0 then
                  "4.03.0"
                else if OpamPackage.Version.compare version ocaml_4_01_0 > 0 then
                  "4.02.0"
                else if OpamPackage.Version.compare version ocaml_4_00_0 >= 0 then
                  "4.00.0"
                else if OpamPackage.Version.compare version ocaml_3_11_0 >= 0 then
                  "3.11.0"
                else
                  "3.07"
                 * Final version with one script for 3.07-3.10.x and one script for 3.11.0+
                 *)
                if OpamPackage.Version.compare version ocaml_3_11_0 >= 0 then
                  ""
                else
                  "-3.07"
              in
              let files_dir = OpamRepositoryPath.files repo.repo_root (Some "ocaml-base-compiler") package in
              OpamFilename.copy ~src:(Printf.sprintf "win%s.sh" win_sh |> OpamFilename.Base.of_string |> OpamFilename.create (OpamFilename.Dir.of_string (Filename.dirname Sys.argv.(0)))) ~dst:(OpamFilename.create files_dir (OpamFilename.Base.of_string "win.sh"));
              f acc commands
          | ([(CIdent "make", None) as make; (CString "world.opt", None)], None)::commands when OpamPackage.Version.compare version ocaml_3_12_0 < 0 ->
              f (([make; (CString "world.opt", Some not_windows_filter); (CString "opt", Some windows_filter); (CString "opt.opt", Some windows_filter)], None)::acc) commands
          | (([(CIdent "make", None) as make; (CString "world.opt", None)], None) as command)::commands when OpamPackage.Version.compare version ocaml_4_02_3 = 0 ->
              f (command::([make; (CString "world", None)], Some windows_filter)::acc) commands
          | command::commands ->
              f (command::acc) commands
          | [] ->
              List.rev acc
          in
          f [] commands
        in
        let adapt_install commands =
          let rec f acc = function
          | ((((CString "cp", None) as cp)::params), None)::commands ->
              f (((cp::(CString "--no-preserve=mode", Some windows_filter)::params), None)::acc) commands
          | ([(CIdent "make", None) as make; (CString "world.opt", None)], None)::commands when OpamPackage.Version.compare version ocaml_3_12_0 < 0 ->
              f (([make; (CString "world.opt", Some not_windows_filter); (CString "opt", Some windows_filter); (CString "opt.opt", Some windows_filter)], None)::acc) commands
          | (([(CIdent "make", None) as make; (CString "world.opt", None)], None) as command)::commands when OpamPackage.Version.compare version ocaml_4_02_3 = 0 ->
              f (command::([make; (CString "world", None)], Some windows_filter)::acc) commands
          | (([(CIdent "make", None) as make; ((CString "install", None) as install)], None))::commands when OpamPackage.Version.compare version ocaml_4_04_0 >= 0 ->
              f (([make; (CString "INSTALL_DISTRIB=", Some windows_filter); install], None)::acc) commands
          | command::commands ->
              f (command::acc) commands
          | [] ->
              List.rev acc
          in
          f [] commands
        in
        let add_depends version depends =
          let (_, flexdll_min, tcltk) =
            let (flexdll_install, flexdll_min, tcltk) = build_info version in
            (flexdll_install, OpamStd.Option.default_map flexdll_install flexdll_min, tcltk)
          in
          let tcltk =
            let f version =
              [Atom (OpamPackage.Name.of_string "win32-tcl-tk", And (Atom (Filter windows_filter), Atom (Constraint (`Geq, FString (version ^ ".0")))))]
            in
            OpamStd.Option.map_default f [] tcltk
          in
          let extras =
            let f version =
              (Atom (OpamPackage.Name.of_string "flexdll", And (Atom (Filter windows_filter), Atom (Constraint (`Geq, FString version)))))::tcltk
            in
            OpamStd.Option.map_default f tcltk flexdll_min
          in
          List.append (OpamFormula.ands_to_list depends) ((Atom (OpamPackage.Name.of_string "compiler", Empty))::extras) |> OpamFormula.ands
        in
        let create_also version =
          let (flexdll_install, tcltk) =
            let (flexdll_install, _, tcltk) = build_info version in
            let flexdll_install =
              let f flexdll_install =
                if OpamPackage.Version.compare (OpamPackage.Version.of_string flexdll_install) flexdll_0_29 < 0 then
                  "0.29"
                else
                  flexdll_install
              in
              OpamStd.Option.map f flexdll_install
            in
              (flexdll_install, (if tcltk = Some "8.3" then Some "8.4" else tcltk))
          in
          let tcltk =
            let f version =
              let version =
                match version with
                | "8.4" -> "8.5.0"
                | "8.5" -> "8.6.0"
                | _ -> assert false
              in
              [Atom (OpamPackage.Name.of_string "win32-tcl-tk", And (Atom (Constraint (`Lt, FString version)), Atom (Filter windows_filter)))]
            in
            OpamStd.Option.map_default f [] tcltk
          in
          let also =
            let f version =
              (Atom (OpamPackage.Name.of_string "flexlink", And (Atom (Constraint (`Eq, FString version)), Atom (Filter windows_filter))))::tcltk
            in
            OpamStd.Option.map_default f tcltk flexdll_install
          in
          OpamFormula.ands also
        in
        let compute_available version =
          let os = OpamVariable.of_string "os" in
          let switch_arch = OpamVariable.of_string "switch-arch" in
          if OpamPackage.Version.compare version ocaml_4_00_0 >= 0 then
            FBool true
          else if OpamPackage.Version.compare version ocaml_3_10_0 >= 0 then
            (* For each of these filters, have to allow for two cases:
                 1. The "normal" case where compiler is installed at the same
                    time as ocaml. In this instance, target-arch and cc won't
                    be defined (which is why they are accessed indirectly using
                    %{..}% notation) and we rely on negations of switch-arch and
                    switch-cc and the compiler package correctly selecting an
                    appropriate default if switch-cc = "default" or
                    switch-arch = "default".
                 2. The "manual" case where compiler has been installed
                    beforehand. In this instance, switch-cc and switch-arch may
                    have been "default" and because ocaml wasn't installed at
                    the same time, the compiler package may have chosen an
                    "inappropriate" default (typically, this will mean selecting
                    x86_64 for target-arch) *)
            (* os != "win32" | (switch-arch != "x86_64" & "%{target-arch}%" != "x86_64") | (switch-cc != "cc" & "%{cc}%" != "cc") *)
            (*FOr (FOp (FIdent ([], os, None), `Neq, FString "win32"), FOr (FAnd (FOp (FIdent ([], switch_arch, None), `Neq, FString "x86_64"), FOp (FString "%{target-arch}%", `Neq, FString "x86_64")), FAnd (FOp (FIdent ([], OpamVariable.of_string "switch-cc", None), `Neq, FString "cc"), FOp (FString "%{cc}%", `Neq, FString "cc"))))*)
            FOr (FOp (FIdent ([], os, None), `Neq, FString "win32"), FOr (FAnd (FOp (FIdent ([], switch_arch, None), `Neq, FString "x86_64"), FOp (FString "%{target-arch}%", `Neq, FString "x86_64")), FAnd (FOp (FIdent ([], OpamVariable.of_string "switch-cc", None), `Neq, FString "cc"), FOp (FString "%{cc}%", `Neq, FString "cc"))))
          else
            (* os != "win32" | switch-arch != "x86_64" & "%{target-arch}%" != "x86_64" *)
            FOr (FOp (FIdent ([], os, None), `Neq, FString "win32"), FAnd (FOp (FIdent ([], switch_arch, None), `Neq, FString "x86_64"), FOp (FString "%{target-arch}%", `Neq, FString "x86_64")))
        in
        let debug_patch version patch =
          clear ();
          OpamConsole.note "Test switch: %s+%s" version patch
        in
        let patch_version opam version flags patch =
          assert (OpamFile.OPAM.remove opam = []);
          opam |>
          OpamFile.OPAM.with_patches (filter_patches get_patch version (OpamFile.OPAM.patches opam)) |>
          OpamFile.OPAM.with_extra_sources (filter_patches get_source version (OpamFile.OPAM.extra_sources opam)) |>
          OpamFile.OPAM.with_env (OpamFile.OPAM.env opam |> convert_caml_ld_path) |>
          OpamFile.OPAM.with_build (OpamFile.OPAM.build opam |> convert_paths |> adapt_build version flags patch) |>
          OpamFile.OPAM.with_install (OpamFile.OPAM.install opam |> convert_paths |> adapt_install) |>
          OpamFile.OPAM.with_depends (OpamFile.OPAM.depends opam |> add_depends version) |>
          OpamFile.OPAM.with_also_install (create_also version) |>
          OpamFile.OPAM.with_available (compute_available version)
        in
        match OpamStd.String.cut_at str_version '+' with
        | None ->
            (* Basic 3.07-4.04.0 case *)
            patch_version opam version [] ""
        | Some ("3.07", "1")
        | Some ("3.07", "2") ->
            (* Basic 3.07 case *)
            patch_version opam version [] ""
            (* @@DRA Should use an re test for pr[0-9]+ *)
        | Some ("4.05.0", patch) when OpamStd.String.starts_with ~prefix:"pr" patch ->
            (* OCaml Pull Requests *)
            (* @@DRA Ensure that opam file for a PR is identical to trunk *)
            opam
        | Some (version, ("debug-runtime" as patch))
        | Some (version, ("profile" as patch)) ->
            debug_patch version patch;
            patch_version opam (OpamPackage.Version.of_string version) ["-with-debug-runtime"] ""
        | Some (version, patch) ->
            if not (OpamStd.String.Set.mem patch not_for_windows) && (String.length patch < 4 || String.sub patch 0 4 <> "beta") then begin
              if OpamStd.String.Set.mem patch recognised_flags then begin
                debug_patch version patch;
                patch_version opam (OpamPackage.Version.of_string version) (OpamStd.List.filter_map (fun x -> if x = "trunk" then None else Some ("-" ^ x)) (OpamStd.String.split patch '+')) ""
              end else if OpamStd.String.Set.mem patch allowed_patches then begin
                debug_patch version patch;
                patch_version opam (OpamPackage.Version.of_string version) [] patch
              end else begin
                clear ();
                OpamConsole.warning "Not sure what to do with %s patched %s" version patch;
                opam
              end
            end else
              OpamFile.OPAM.with_available not_windows_filter opam
      else
        opam
    else
      opam) ()
;;
