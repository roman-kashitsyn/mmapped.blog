(* Source position type, filling the role of Text.Parsec.Pos.SourcePos. *)

type t = {
  source_name : string;
  line : int;
  column : int;
}

let make source_name line column = { source_name; line; column }

let initial source_name = { source_name; line = 1; column = 1 }

let source_name p = p.source_name
let line p = p.line
let column p = p.column

let equal a b =
  a.line = b.line && a.column = b.column && a.source_name = b.source_name

let compare a b =
  let c = compare a.line b.line in
  if c <> 0 then c else compare a.column b.column

(* Advance a position past a character. Tabs do not get any special treatment;
   this matches Parsec's defaultUpdatePosChar with tab width = 1. *)
let advance p c =
  if c = '\n' then { p with line = p.line + 1; column = 1 }
  else { p with column = p.column + 1 }

let to_string p =
  Printf.sprintf "\"%s\" (line %d, column %d)" p.source_name p.line p.column
