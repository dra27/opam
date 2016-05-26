(**************************************************************************)
(*                                                                        *)
(*    Copyright 2016 MetaStack Solutions Ltd.                             *)
(*                                                                        *)
(*  This file is distributed under the terms of the GNU General Public    *)
(*  License version 3.0                                                   *)
(*                                                                        *)
(*  OPAM is distributed in the hope that it will be useful, but WITHOUT   *)
(*  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY    *)
(*  or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public       *)
(*  License for more details.                                             *)
(*                                                                        *)
(**************************************************************************)

(** OPAM string interpolation lexer *)

val line: Lexing.lexbuf -> (bool * string) list
