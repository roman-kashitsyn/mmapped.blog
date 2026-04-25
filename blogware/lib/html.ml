(* HTML builder. Mirror of Blogware.Html.

   The Haskell version uses an [HtmlM a] phantom-type Builder monad so it
   can use do-notation. OCaml has no do-notation, so the port replaces the
   monadic interface with simple buffer-passing functions: a value of type
   [t] is "a function that appends its content to a buffer". Composition
   is just function composition (sequencing two writes), exposed as [++].

   Tag helpers (~100 of them) all delegate to [parent] / [leaf] one-liners
   below, exactly as in the Haskell version. *)

type t = Buffer.t -> unit

let empty : t = fun _ -> ()

let ( ++ ) (a : t) (b : t) : t =
 fun buf ->
  a buf;
  b buf

let concat (xs : t list) : t = fun buf -> List.iter (fun x -> x buf) xs

let render (h : t) : string =
  let b = Buffer.create 4096 in
  h b;
  Buffer.contents b

(* --- HTML escaping (text content and attribute values) ---
   Special characters: lt, gt, amp, dquote. The apostrophe is allowed in
   HTML body and in double-quoted attribute values, matching the Haskell
   escaper. *)

let is_special c = match c with '<' | '>' | '&' | '"' -> true | _ -> false

let escape_html (s : Text.t) (buf : Buffer.t) : unit =
  if not (Text.exists is_special s) then Text.output_to_buffer buf s
  else
    Text.iter
      (fun c ->
        match c with
        | '<' -> Buffer.add_string buf "&lt;"
        | '>' -> Buffer.add_string buf "&gt;"
        | '&' -> Buffer.add_string buf "&amp;"
        | '"' -> Buffer.add_string buf "&quot;"
        | c -> Buffer.add_char buf c)
      s

(* --- Primitives --- *)

let text (s : Text.t) : t = escape_html s
let raw (s : Text.t) : t = fun buf -> Text.output_to_buffer buf s
let nl : t = raw (Text.of_string "\n")
let nbsp : t = raw (Text.of_string "&nbsp;")
let endash : t = raw (Text.of_string "&ndash;")
let doctype : t = raw (Text.of_string "<!DOCTYPE html>")

(* --- Attributes --- *)

(* An attribute is also a buffer-writing function. It is responsible for
   emitting its own leading space, mirroring the Haskell encoding. *)
type attribute = Buffer.t -> unit

let attr (key : string) (value : Text.t) : attribute =
 fun buf ->
  Buffer.add_char buf ' ';
  Buffer.add_string buf key;
  Buffer.add_string buf "=\"";
  escape_html value buf;
  Buffer.add_char buf '"'

let class_ v = attr "class" v
let role_ v = attr "role" v
let href_ v = attr "href" v
let id_ v = attr "id" v
let for_ v = attr "for" v
let type_ v = attr "type" v
let colspan_ v = attr "colspan" v
let datetime_ v = attr "datetime" v
let rel_ v = attr "rel" v
let charset_ v = attr "charset" v
let name_ v = attr "name" v
let content_ v = attr "content" v
let lang_ v = attr "lang" v
let src_ v = attr "src" v
let alt_ v = attr "alt" v

let render_attrs (attrs : attribute list) (buf : Buffer.t) : unit =
  List.iter (fun a -> a buf) attrs

(* --- Generic tag constructors --- *)

let parent (tag : string) (attrs : attribute list) (body : t) : t =
 fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf tag;
  render_attrs attrs buf;
  Buffer.add_char buf '>';
  body buf;
  Buffer.add_string buf "</";
  Buffer.add_string buf tag;
  Buffer.add_char buf '>'

let leaf (tag : string) (attrs : attribute list) : t =
 fun buf ->
  Buffer.add_char buf '<';
  Buffer.add_string buf tag;
  render_attrs attrs buf;
  Buffer.add_char buf '>'

(* --- Named tag helpers --- *)

(* Document structure *)
let html_ a c = parent "html" a c
let head_ a c = parent "head" a c
let body_ a c = parent "body" a c
let title_ a c = parent "title" a c
let article_ a c = parent "article" a c
let section_ a c = parent "section" a c
let header_ a c = parent "header" a c
let footer_ a c = parent "footer" a c
let nav_ a c = parent "nav" a c
let aside_ a c = parent "aside" a c
let figure_ a c = parent "figure" a c
let figcaption_ a c = parent "figcaption" a c
let cite_ a c = parent "cite" a c

(* Headings *)
let h1_ a c = parent "h1" a c
let h2_ a c = parent "h2" a c
let h3_ a c = parent "h3" a c

(* Block content *)
let div_ a c = parent "div" a c
let p_ a c = parent "p" a c
let pre_ a c = parent "pre" a c
let blockquote_ a c = parent "blockquote" a c

(* Lists *)
let ul_ a c = parent "ul" a c
let ol_ a c = parent "ol" a c
let li_ a c = parent "li" a c
let dl_ a c = parent "dl" a c
let dt_ a c = parent "dt" a c
let dd_ a c = parent "dd" a c

(* Inline *)
let span_ a c = parent "span" a c
let a_ a c = parent "a" a c
let b_ a c = parent "b" a c
let em_ a c = parent "em" a c
let u_ a c = parent "u" a c
let code_ a c = parent "code" a c
let kbd_ a c = parent "kbd" a c
let sub_ a c = parent "sub" a c
let sup_ a c = parent "sup" a c
let time_ a c = parent "time" a c
let label_ a c = parent "label" a c

(* Tables *)
let table_ a c = parent "table" a c
let thead_ a c = parent "thead" a c
let tbody_ a c = parent "tbody" a c
let tr_ a c = parent "tr" a c
let th_ a c = parent "th" a c
let td_ a c = parent "td" a c

(* Void tags *)
let hr_ a = leaf "hr" a
let br_ a = leaf "br" a
let meta_ a = leaf "meta" a
let link_ a = leaf "link" a
let input_ a = leaf "input" a
let img_ a = leaf "img" a

(* MathML *)
let math_ a c = parent "math" a c
let mi_ a c = parent "mi" a c
let mn_ a c = parent "mn" a c
let mo_ a c = parent "mo" a c
let mrow_ a c = parent "mrow" a c
let mfrac_ a c = parent "mfrac" a c
let msub_ a c = parent "msub" a c
let msup_ a c = parent "msup" a c
let msubsup_ a c = parent "msubsup" a c
let munder_ a c = parent "munder" a c
let mover_ a c = parent "mover" a c
let munderover_ a c = parent "munderover" a c
let mtable_ a c = parent "mtable" a c
let mtr_ a c = parent "mtr" a c
let mtd_ a c = parent "mtd" a c
let mtext_ a c = parent "mtext" a c
