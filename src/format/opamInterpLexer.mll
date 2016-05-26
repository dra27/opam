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

{
let b = Buffer.create 64
}

let eol = '\n' | "\r\n"

rule line acc = parse
| eol          { Lexing.new_line lexbuf; List.rev acc }
| [^ '"' '\r' '\n' ]+
               { line ((false, Lexing.lexeme lexbuf)::acc) lexbuf }
| '"'          { Buffer.reset b; Buffer.add_char b '"'; string acc lexbuf}
| eof          { List.rev acc }

and string acc = parse
| [^ '"' '\\' '\n' '\r' ]+
               { Buffer.add_string b (Lexing.lexeme lexbuf); string acc lexbuf }
| '\\' [^ '\r' '\n' ]?
               { Buffer.add_string b (Lexing.lexeme lexbuf); string acc lexbuf }
| '"'          { line ((true, Buffer.contents b ^ "\"")::acc) lexbuf }
| eol          { List.rev ((true, Buffer.contents b)::acc) }
| eof          { List.rev ((true, Buffer.contents b)::acc) }

{
let line lexbuf = line [] lexbuf
}
