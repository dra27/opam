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

open OpamCompat

(* Global configuration *)

let debug () = OpamCoreConfig.(!r.debug_level) > 0

let verbose () = OpamCoreConfig.(!r.verbose_level) > 0

let dumb_term = lazy (
  try OpamStd.Env.get "TERM" = "dumb" with Not_found -> OpamStd.(Sys.os () <> Sys.Win32)
)

let win32_color = ref true
let win32_ecolor = ref true

let color =
  let auto = lazy (
    OpamStd.Sys.tty_out && not (Lazy.force dumb_term)
  ) in
  fun () -> match OpamCoreConfig.(!r.color) with
    | `Always -> !win32_color || !win32_ecolor
    | `Never -> false
    | `Auto -> Lazy.force auto && (!win32_color || !win32_ecolor)

let disp_status_line () =
  match OpamCoreConfig.(!r.disp_status_line) with
  | `Always -> true
  | `Never -> false
  | `Auto -> OpamStd.Sys.tty_out && (color () || not (Lazy.force dumb_term))

let utf8, utf8_extended =
  let auto = lazy (
    if OpamStd.Sys.(os () = Win32) then
      try
        let info = OpamStd.Win32.getCurrentConsoleFontEx (OpamStd.Win32.getStdHandle (-11)) false in
          (*
           * The Windows Console can be set to support Unicode as long as a TrueType font has been selected (Consolas or Lucida Console
           * are installed by default)
           * TMPF_TRUETYPE = 0x4 (wingdi.h)
           *)
          OpamStd.Win32.(info.fontFamily land 0x4 <> 0)
      with Not_found ->
        false
    else
      let checkv v =
        try Some (OpamStd.String.ends_with ~suffix:"UTF-8" (OpamStd.Env.get v))
        with Not_found -> None
      in
      OpamStd.Option.Op.(checkv "LC_ALL" ++ checkv "LANG" +! false)
  ) in
  (fun () -> match OpamCoreConfig.(!r.utf8) with
     | `Always | `Extended -> true
     | `Never -> false
     | `Auto -> Lazy.force auto),
  (fun () -> match OpamCoreConfig.(!r.utf8) with
     | `Extended -> OpamStd.Sys.(os () <> Win32)
     | `Always | `Never -> false
     | `Auto -> Lazy.force auto && OpamStd.Sys.(os () = Darwin))

let timer () =
  if debug () then
    let t = Sys.time () in
    fun () -> Sys.time () -. t
  else
    fun () -> 0.

let global_start_time =
  Unix.gettimeofday ()

type text_style =
  [ `bold
  | `underline
  | `crossed
  | `black
  | `red
  | `green
  | `yellow
  | `blue
  | `magenta
  | `cyan
  | `white ]

let style_code (c: text_style) = match c with
  | `bold      -> "01"
  | `underline -> "04"
  | `crossed   -> "09"
  | `black     -> "30"
  | `red       -> "31"
  | `green     -> "32"
  | `yellow    -> "33"
  | `blue      -> "1;34" (* most terminals make blue unreadable unless bold *)
  | `magenta   -> "35"
  | `cyan      -> "36"
  | `white     -> "37"

(* not nestable *)
let colorise style s =
  if not (color ()) then s else
    Printf.sprintf "\027[%sm%s\027[m" (style_code style) s

let colorise' styles s =
  if not (color ()) then s else
    Printf.sprintf "\027[%sm%s\027[m"
      (String.concat ";" (List.map style_code styles))
      s

let acolor_with_width width c () s =
  let str = colorise c s in
  str ^
  match width with
  | None   -> ""
  | Some w ->
    if String.length str >= w then ""
    else String.make (w-String.length str) ' '

let acolor c () = colorise c
let acolor_w width c oc s = output_string oc (acolor_with_width (Some width) c () s)

(*
 * Layout of attributes (wincon.h)
 *
 * Bit 0 - Blue --\
 * Bit 1 - Green   } Foreground
 * Bit 2 - Red    /
 * Bit 3 - Bold -/
 * Bit 4 - Blue --\
 * Bit 5 - Green   } Background
 * Bit 6 - Red    /
 * Bit 7 - Bold -/
 * Bit 8 - Leading Byte
 * Bit 9 - Trailing Byte
 * Bit a - Top horizontal
 * Bit b - Left vertical
 * Bit c - Right vertical
 * Bit d - unused
 * Bit e - Reverse video
 * Bit f - Underscore
 *)

let win32_msg ch msg =
  let (ch, fch, rch) =
    match ch with
    | `out -> (stdout, -11, win32_color)
    | `err -> (stderr, -12, win32_ecolor)
  in
  if not !rch then
    Printf.fprintf ch "%s%!" msg
  else
    (*
     * Tread extremely cautiously (and possibly incorrectly) where UTF-8 is concerned. Although we could blithely
     * set code page 65001 at program launch, processes invoked by OPAM may struggle to cope with it. However, the "test"
     * for UTF-8 is simply the presence of any byte with bit 7 set, so we could run into trouble if any extended ASCII
     * bytes are sent through this routine.
     *)
    try
      flush ch;
      let hConsoleOutput = OpamStd.Win32.getStdHandle fch in
      let ({OpamStd.Win32.attributes; _}, write) =
        try
          (OpamStd.Win32.getConsoleScreenBufferInfo hConsoleOutput, OpamStd.Win32.writeWindowsConsole hConsoleOutput)
        with Not_found ->
          rch := false;
          (*
           * msg will have been constructed on the assumption that colour was available - process it as normal
           * in order to remove the escape sequences
           *)
          ({OpamStd.Win32.attributes = 0; cursorPosition = (0, 0); maximumWindowSize = (0, 0); window = (0, 0, 0, 0); size = (0, 0)}, Printf.fprintf ch "%s%!")
      in
      let outputColor = !rch in
      let background = (attributes land 0b1110000) lsr 4 in
      let length = String.length msg in
      let executeCode =
        let color = ref (attributes land 0b1111) in
        let blend ?(inheritbold = true) bits =
          let bits =
            if inheritbold then
              (!color land 0b1000) lor (bits land 0b111)
            else
              bits in
          let result = (attributes land (lnot 0b1111)) lor (bits land 0b1000) lor ((bits land 0b111) lxor background) in
          color := (result land 0b1111);
          result in
        fun code ->
          let l = String.length code in
          assert (l > 0 && code.[0] = '[');
          let attributes = OpamStd.String.split (String.sub code 1 (l - 1)) ';' in
          let attributes = if attributes = [] then [""] else attributes in
          let f attributes attribute =
            match attribute with
              "1"
            | "01" ->
                blend ~inheritbold:false (!color lor 0b1000)
            | "04" ->
                (* Don't have underline, so change the background *)
                (attributes land (lnot 0b11111111)) lor 0b01110000
            | "30" ->
                blend 0b000
            | "31" ->
                blend 0b100
            | "32" ->
                blend 0b010
            | "33" ->
                blend 0b110
            | "34" ->
                blend ~inheritbold:false 0b001
            | "35" ->
                blend 0b101
            | "36" ->
                blend 0b011
            | "37" ->
                blend 0b111
            | "" ->
                blend ~inheritbold:false 0b0111
            | _ -> assert false in
          if outputColor then
            OpamStd.Win32.setConsoleTextAttribute hConsoleOutput (List.fold_left f (blend !color) attributes) in
      let rec f ansi index start inCode =
        if index < length
        then let c = msg.[index] in
             if c = '\027' then begin
               assert (not inCode);
               let fragment = String.sub msg start (index - start) in
               let index = succ index in
               if fragment <> "" then
                 write fragment;
               f ansi index index true end
             else
               if inCode && c = 'm' then
                 let fragment = String.sub msg start (index - start) in
                 let index = succ index in
                 executeCode fragment;
                 f ansi index index false
               else
                 (* UTF-8 chars assumed not to appear inside ANSI escape *)
                 let ansi =
                   if ansi && int_of_char c land 0x80 <> 0 then
                     not (OpamStd.Win32.setConsoleOutputCP 65001)
                   else
                     ansi
                 in
                 f ansi (succ index) start inCode
        else let fragment = String.sub msg start (index - start) in
             if fragment <> "" then
               if inCode then
                 executeCode fragment
               else
                 write fragment
             else
               flush ch;
             ansi in
      let cp =
        OpamStd.Win32.getConsoleOutputCP ()
      in
      let result =
        if f (cp <> 65001 && utf8 ()) 0 0 false then
          cp
        else
          65001
      in
      if cp <> result then
        ignore (OpamStd.Win32.setConsoleOutputCP cp)
    with Exit -> ()

let gen_msg =
  if OpamStd.(Sys.os () = Sys.Win32) then
    fun ch fmt ->
      flush (if ch = `out then stderr else stdout);
      Printf.ksprintf (win32_msg ch) (fmt ^^ "%!")
  else
    fun ch fmt ->
      flush (if ch = `out then stderr else stdout);
      Printf.ksprintf (output_string (if ch = `out then stdout else stderr)) (fmt ^^ "%!")

let timestamp () =
  let time = Unix.gettimeofday () -. global_start_time in
  let tm = Unix.gmtime time in
  let msec = time -. (floor time) in
  Printf.ksprintf (colorise `blue) "%.2d:%.2d.%.3d"
    (tm.Unix.tm_hour * 60 + tm.Unix.tm_min)
    tm.Unix.tm_sec
    (int_of_float (1000.0 *. msec))

let log section ?(level=1) fmt =
  if level <= OpamCoreConfig.(!r.debug_level) then
    let () = flush stdout in
    if OpamStd.(Sys.os () = Sys.Win32) then begin
      (*
       * In order not to break [slog], split the output into two. A side-effect of this is that
       * logging lines may not use colour.
       *)
      win32_msg `err (Printf.sprintf "%s  %a  " (timestamp ()) (acolor_with_width (Some 30) `yellow) section);
      Printf.fprintf stderr (fmt ^^ "\n%!") end
    else
      Printf.fprintf stderr ("%s  %a  " ^^ fmt ^^ "\n%!")
        (timestamp ()) (acolor_w 30 `yellow) section
  else
    Printf.ifprintf stderr fmt

(* Helper to pass stringifiers to log (use [log "%a" (slog to_string) x]
   rather than [log "%s" (to_string x)] to avoid costly unneeded
   stringifications *)
let slog to_string channel x = output_string channel (to_string x)

let error fmt =
  Printf.ksprintf (fun str ->
    gen_msg `err "%a %s\n" (acolor `red) "[ERROR]"
      (OpamStd.Format.reformat ~start_column:8 ~indent:8 str)
  ) fmt

let warning fmt =
  Printf.ksprintf (fun str ->
    gen_msg `err "%a %s\n" (acolor `yellow) "[WARNING]"
      (OpamStd.Format.reformat ~start_column:10 ~indent:10 str)
  ) fmt

let note fmt =
  Printf.ksprintf (fun str ->
    gen_msg `err "%a %s\n" (acolor `blue) "[NOTE]"
      (OpamStd.Format.reformat ~start_column:7 ~indent:7 str)
  ) fmt

let errmsg fmt = gen_msg `err fmt

let error_and_exit ?(num=66) fmt =
  Printf.ksprintf (fun str ->
    error "%s" str;
    OpamStd.Sys.exit num
  ) fmt

let msg fmt = gen_msg `out fmt

(* Flushing version of print_string *)
let print_string s = gen_msg `out "%s" s

let formatted_msg ?indent fmt =
  flush stderr;
  Printf.ksprintf
    (fun s -> print_string (OpamStd.Format.reformat ?indent s))
    fmt

let carriage_delete () =
  if OpamStd.(Sys.os () = Sys.Win32) then
    (*
     * Technically this doesn't erase the final character of the line -
     *   but then there's no checking as to whether the status causes a line wrap either
     *)
    Printf.sprintf "\r%s\r" (String.make (OpamStd.Sys.terminal_columns () - 1) ' ')
  else
    "\r\027[K"

let last_status = ref ""
let status_line fmt =
  let batch =
    debug () || not (disp_status_line ()) in
  let print_msg =
    if batch then
      if OpamStd.Sys.(os () = Win32) then
        fun s -> win32_msg `out (s ^ "\n")
      else
        print_endline
    else
      if OpamStd.Sys.(os () = Win32) then
        fun s -> flush stdout; win32_msg `out s
      else
        fun s -> print_string s in
  if batch then
    Printf.ksprintf
      (fun s -> if s <> !last_status then (last_status := s; print_msg s))
      fmt
  else
    let carriage_delete = carriage_delete () in
    Printf.ksprintf
      (fun s ->
         output_string stdout carriage_delete;
         print_msg s; (* flush before for Windows; after for Unix *)
         output_string stdout carriage_delete (* unflushed *))
      fmt

let header_width () = min 80 (OpamStd.Sys.terminal_columns ())

let header_msg fmt =
  let utf8camel = "\xF0\x9F\x90\xAB " in (* UTF-8 <U+1F42B, U+0020> *)
  let padding = "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\
                 =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=" in
  Printf.ksprintf (fun str ->
      flush stderr;
      print_char '\n';
      let wpad = header_width () - String.length str - 2 in
      let wpadl = 4 in
      print_string (colorise `cyan (String.sub padding 0 wpadl));
      print_char ' ';
      print_string (colorise `bold str);
      print_char ' ';
      let wpadr = wpad - wpadl - if utf8_extended () then 4 else 0 in
      if wpadr > 0 then
        print_string
          (colorise `cyan
             (String.sub padding (String.length padding - wpadr) wpadr));
      if wpadr >= 0 && utf8_extended () then
        (print_string "  ";
         print_string (colorise `yellow utf8camel));
      print_char '\n';
    ) fmt

let header_error fmt =
  let padding = "#=======================================\
                 ========================================#" in
  Printf.ksprintf (fun head fmt ->
      Printf.ksprintf (fun contents ->
          output_char stderr '\n';
          let wpad = header_width () - String.length head - 8 in
          let wpadl = 4 in
          let output_string = gen_msg `err "%s" in
          output_string (colorise `red (String.sub padding 0 wpadl));
          output_char stderr ' ';
          output_string (colorise `bold "ERROR");
          output_char stderr ' ';
          output_string (colorise `bold head);
          output_char stderr ' ';
          let wpadr = wpad - wpadl in
          if wpadr > 0 then
            output_string
              (colorise `red
                 (String.sub padding (String.length padding - wpadr) wpadr));
          output_char stderr '\n';
          output_string contents;
          output_char stderr '\n';
          flush stderr;
        ) fmt
    ) fmt


let confirm ?(default=true) fmt =
  Printf.ksprintf (fun s ->
    try
      if OpamCoreConfig.(!r.safe_mode) then false else
      let prompt () =
        formatted_msg "%s [%s] " s (if default then "Y/n" else "y/N")
      in
      if OpamCoreConfig.(!r.answer) = Some true then
        (prompt (); msg "y\n"; true)
      else if OpamCoreConfig.(!r.answer) = Some false ||
              OpamStd.Sys.(not tty_in)
      then
        (prompt (); msg "n\n"; false)
      else if OpamStd.Sys.(not tty_out || os () = Win32 || os () = Cygwin) then
        let rec loop () =
          prompt ();
          match String.lowercase (read_line ()) with
          | "y" | "yes" -> true
          | "n" | "no" -> false
          | "" -> default
          | _  -> loop ()
        in loop ()
      else
      let open Unix in
      prompt ();
      let buf = Bytes.create 1 in
      let rec loop () =
        let ans =
          try
            if read stdin buf 0 1 = 0 then raise End_of_file
            else Some (Char.lowercase (Bytes.get buf 0))
          with
          | Unix.Unix_error (Unix.EINTR,_,_) -> None
          | Unix.Unix_error _ -> raise End_of_file
        in
        match ans with
        | Some 'y' -> print_endline (Bytes.to_string buf); true
        | Some 'n' -> print_endline (Bytes.to_string buf); false
        | Some '\n' -> print_endline (if default then "y" else "n"); default
        | _ -> loop ()
      in
      let attr = tcgetattr stdin in
      let reset () =
        tcsetattr stdin TCSAFLUSH attr;
        tcflush stdin TCIFLUSH;
      in
      try
        tcsetattr stdin TCSAFLUSH {attr with c_icanon = false; c_echo = false};
        tcflush stdin TCIFLUSH;
        let r = loop () in
        reset ();
        r
      with e -> reset (); raise e
    with
    | End_of_file -> msg "%s\n" (if default then "y" else "n"); default
    | Sys.Break as e -> msg "\n"; raise e
  ) fmt

let read fmt =
  Printf.ksprintf (fun s ->
    formatted_msg "%s %!" s;
    if OpamCoreConfig.(!r.answer = None && not !r.safe_mode) then (
      try match read_line () with
        | "" -> None
        | s  -> Some s
      with
      | End_of_file ->
        msg "\n";
        None
      | Sys.Break as e -> msg "\n"; raise e
    ) else
      None
  ) fmt
