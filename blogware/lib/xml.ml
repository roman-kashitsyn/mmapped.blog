(* Minimal XML builder. *)

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

(* --- Attributes --- *)

type attribute = Buffer.t -> unit

let attr (key : string) (value : Text.t) : attribute =
 fun buf ->
  Buffer.add_char buf ' ';
  Buffer.add_string buf key;
  Buffer.add_string buf "=\"";
  escape_xml value buf;
  Buffer.add_char buf '"'

let render_attrs (attrs : attribute list) (buf : Buffer.t) : unit =
  List.iter (fun a -> a buf) attrs

(* --- Generic tag constructors --- *)

let parent (tag : string) (attrs : attribute list) (content : t) : t =
 fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf tag;
  render_attrs attrs buf;
  Buffer.add_char buf '>';
  content buf;
  Buffer.add_string buf "</";
  Buffer.add_string buf tag;
  Buffer.add_string buf ">\n"

let leaf (tag : string) (attrs : attribute list) : t =
 fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf tag;
  render_attrs attrs buf;
  Buffer.add_string buf "/>\n"
