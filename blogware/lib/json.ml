module type Builder = sig
  type t

  val null : t
  val str : string -> t
  val num : int -> t
  val arr : t array -> t
  val obj : (string * t) array -> t
end

module Render = struct
  type t = Buffer.t -> unit

  let null buf = Buffer.add_string buf "null"

  let str s buf =
    Buffer.add_char buf '"';
    String.iter
      (function
        | '"' -> Buffer.add_string buf "\\\""
        | '\\' -> Buffer.add_string buf "\\\\"
        | '\b' -> Buffer.add_string buf "\\b"
        | '\n' -> Buffer.add_string buf "\\n"
        | '\r' -> Buffer.add_string buf "\\r"
        | '\t' -> Buffer.add_string buf "\\t"
        | '<' -> Buffer.add_string buf "\\u003c"
        | '>' -> Buffer.add_string buf "\\u003e"
        | '&' -> Buffer.add_string buf "\\u0026"
        | c when Char.code c < 0x20 ->
            Printf.bprintf buf "\\u%04x" (Char.code c)
        | c -> Buffer.add_char buf c)
      s;
    Buffer.add_char buf '"'

  let num n buf = Printf.bprintf buf "%d" n

  let arr elems buf =
    Buffer.add_char buf '[';
    Array.iteri
      (fun i v ->
        if i > 0 then Buffer.add_char buf ',';
        v buf)
      elems;
    Buffer.add_char buf ']'

  let obj fields buf =
    Buffer.add_char buf '{';
    Array.iteri
      (fun i (name, value) ->
        if i > 0 then Buffer.add_char buf ',';
        str name buf;
        Buffer.add_char buf ':';
        value buf)
      fields;
    Buffer.add_char buf '}'
end
