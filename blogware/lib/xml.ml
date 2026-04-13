(* Minimal XML builder, mirror of Blogware.Xml.

   The Haskell version wraps Data.Text.Lazy.Builder in a newtype with a
   Semigroup/Monoid instance. The OCaml version uses buffer-passing
   functions, which is the same trick as the Html module: a value of type
   [t] is a function that appends its content to a buffer. *)

type t = Buffer.t -> unit

let empty : t = fun _ -> ()

let ( ++ ) (a : t) (b : t) : t = fun buf -> a buf; b buf

let render (x : t) : string =
  let b = Buffer.create 1024 in
  x b;
  Buffer.contents b

(* XML 1.0 declaration. *)
let decl : t = fun buf ->
  Buffer.add_string buf "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"

let escape_xml s =
  let needs_escape =
    let r = ref false in
    String.iter (fun c ->
      if c = '<' || c = '>' || c = '&' || c = '"' || c = '\'' then r := true
    ) s;
    !r
  in
  if not needs_escape then s
  else begin
    let b = Buffer.create (String.length s + 8) in
    String.iter (fun c -> match c with
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '&' -> Buffer.add_string b "&amp;"
      | '"' -> Buffer.add_string b "&quot;"
      | '\'' -> Buffer.add_string b "&apos;"
      | c -> Buffer.add_char b c
    ) s;
    Buffer.contents b
  end

let text (s : string) : t = fun buf ->
  Buffer.add_string buf (escape_xml s)

let raw (s : string) : t = fun buf ->
  Buffer.add_string buf s

let tag (name : string) (content : t) : t = fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf name;
  Buffer.add_char buf '>';
  content buf;
  Buffer.add_string buf "</";
  Buffer.add_string buf name;
  Buffer.add_string buf ">\n"

let tag_attr (name : string) (attrs : string) (content : t) : t = fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf name;
  Buffer.add_char buf ' ';
  Buffer.add_string buf attrs;
  Buffer.add_char buf '>';
  content buf;
  Buffer.add_string buf "</";
  Buffer.add_string buf name;
  Buffer.add_string buf ">\n"
