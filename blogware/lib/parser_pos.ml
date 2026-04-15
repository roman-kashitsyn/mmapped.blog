(* Source position type, filling the role of Text.Parsec.Pos.SourcePos. *)

type t = {
  source_name : string;
  offset : int;
}

type resolved = {
  source_name : string;
  line : int;
  column : int;
}

let make source_name offset _column = { source_name; offset }

let initial source_name = { source_name; offset = 0 }

let source_name p = p.source_name
let offset p = p.offset

let equal a b =
  a.offset = b.offset && a.source_name = b.source_name

let compare a b =
  compare a.offset b.offset

let advance p _c =
  { p with offset = p.offset + 1 }

let advance_by p n =
  { p with offset = p.offset + n }

let resolve source p =
  let line = ref 1 in
  let column = ref 1 in
  let limit = min p.offset (String.length source) in
  for i = 0 to limit - 1 do
    if source.[i] = '\n' then begin
      incr line;
      column := 1
    end else
      incr column
  done;
  { source_name = p.source_name; line = !line; column = !column }

let to_string (p : t) =
  Printf.sprintf "\"%s\" (offset %d)" p.source_name p.offset
