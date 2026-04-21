(* Minimal XML builder, mirror of Blogware.Xml.

   The Haskell version wraps Data.Text.Lazy.Builder in a newtype with a
   Semigroup/Monoid instance. The OCaml version uses buffer-passing
   functions, which is the same trick as the Html module: a value of type
   [t] is a function that appends its content to a buffer. *)

type t = Buffer.t -> unit

let empty : t = fun _ -> ()

let ( ++ ) (a : t) (b : t) : t =
 fun buf ->
  a buf;
  b buf

let render (x : t) : string =
  let b = Buffer.create 1024 in
  x b;
  Buffer.contents b

(* XML 1.0 declaration. *)
let decl : t =
 fun buf -> Buffer.add_string buf "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"

let is_special = function '<' | '>' | '&' | '"' | '\'' -> true | _ -> false

let escape_xml (s : Text.t) (buf : Buffer.t) =
  if not (Text.exists is_special s) then Text.output_to_buffer buf s
  else
    Text.iter
      (fun c ->
        match c with
        | '<' -> Buffer.add_string buf "&lt;"
        | '>' -> Buffer.add_string buf "&gt;"
        | '&' -> Buffer.add_string buf "&amp;"
        | '"' -> Buffer.add_string buf "&quot;"
        | '\'' -> Buffer.add_string buf "&apos;"
        | c -> Buffer.add_char buf c)
      s

let text (s : Text.t) : t = fun buf -> escape_xml s buf
let raw (s : Text.t) : t = fun buf -> Text.output_to_buffer buf s

let tag (name : string) (content : t) : t =
 fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf name;
  Buffer.add_char buf '>';
  content buf;
  Buffer.add_string buf "</";
  Buffer.add_string buf name;
  Buffer.add_string buf ">\n"

let tag_attr (name : string) (attrs : Text.t) (content : t) : t =
 fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf name;
  Buffer.add_char buf ' ';
  Text.output_to_buffer buf attrs;
  Buffer.add_char buf '>';
  content buf;
  Buffer.add_string buf "</";
  Buffer.add_string buf name;
  Buffer.add_string buf ">\n"
