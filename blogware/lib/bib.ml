(* Simplistic BibTeX parser.

   Supports a subset of BibTeX syntax:
   - Brace-delimited field values with nested braces.
   - Bare numeric values.
   - Comments (anything outside @entries, and @comment/@preamble/@string).
   - Trailing commas.

   Does NOT support:
   - @string macros or # concatenation.
   - Double-quote delimited values.

   Entry types are parsed into a closed sum type: Book, Article,
   Phdthesis, Blog, Talk, Podcast, Misc.
   Unknown @types are rejected at parse time.
*)

open Parser

type book = {
  book_key : Text.t;
  book_author : Text.t;
  book_title : Text.t;
  book_year : Text.t option;
  book_url : Text.t option;
  book_isbn : Text.t option;
}

type article = {
  article_key : Text.t;
  article_author : Text.t;
  article_title : Text.t;
  article_journal : Text.t option;
  article_year : Text.t option;
  article_url : Text.t option;
}

type phdthesis = {
  phdthesis_key : Text.t;
  phdthesis_author : Text.t;
  phdthesis_title : Text.t;
  phdthesis_school : Text.t option;
  phdthesis_year : Text.t option;
  phdthesis_url : Text.t option;
}

type blog = {
  blog_key : Text.t;
  blog_title : Text.t;
  blog_author : Text.t option;
  blog_url : Text.t;
}

type podcast = {
  podcast_key : Text.t;
  podcast_title : Text.t;
  podcast_author : Text.t option;
  podcast_url : Text.t;
}

type talk = {
  talk_key : Text.t;
  talk_author : Text.t;
  talk_title : Text.t;
  talk_year : Text.t option;
  talk_url : Text.t option;
}

type misc = {
  misc_key : Text.t;
  misc_title : Text.t;
  misc_author : Text.t option;
  misc_year : Text.t option;
  misc_url : Text.t option;
}

type entry =
  | Book of book
  | Article of article
  | Phdthesis of phdthesis
  | Blog of blog
  | Talk of talk
  | Podcast of podcast
  | Misc of misc

let entry_key = function
  | Book b -> b.book_key
  | Article a -> a.article_key
  | Phdthesis p -> p.phdthesis_key
  | Blog b -> b.blog_key
  | Talk t -> t.talk_key
  | Podcast p -> p.podcast_key
  | Misc m -> m.misc_key

let entry_title = function
  | Book b -> b.book_title
  | Article a -> a.article_title
  | Phdthesis p -> p.phdthesis_title
  | Blog b -> b.blog_title
  | Talk t -> t.talk_title
  | Podcast p -> p.podcast_title
  | Misc m -> m.misc_title

let entry_author = function
  | Book b -> Some b.book_author
  | Article a -> Some a.article_author
  | Phdthesis p -> Some p.phdthesis_author
  | Blog b -> b.blog_author
  | Talk t -> Some t.talk_author
  | Podcast p -> p.podcast_author
  | Misc m -> m.misc_author

let entry_url = function
  | Book b -> b.book_url
  | Article a -> a.article_url
  | Phdthesis p -> p.phdthesis_url
  | Blog b -> Some b.blog_url
  | Talk t -> t.talk_url
  | Podcast p -> Some p.podcast_url
  | Misc m -> m.misc_url

type bib_file = entry list

(* --- low-level BibTeX syntax --- *)

let is_alpha c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_digit c = c >= '0' && c <= '9'

let is_key_char c =
  is_alpha c || is_digit c || c = '-' || c = '_' || c = ':' || c = '.'

let is_field_name_char c = is_alpha c || is_digit c || c = '_' || c = '-'

let ws : unit t =
  skip_while (fun c -> c = ' ' || c = '\n' || c = '\r' || c = '\t')

let braced_value : Text.t t =
  let* _ = expect_char '{' in
  let buf = Buffer.create 64 in
  let rec loop depth st =
    if st.ofs >= String.length st.src then
      PFail (st.pos, lazy "unterminated braced value", true)
    else
      let c = st.src.[st.ofs] in
      let st' = { st with ofs = st.ofs + 1; pos = Pos.advance st.pos c } in
      match c with
      | '{' ->
          Buffer.add_char buf c;
          loop (depth + 1) st'
      | '}' when depth > 0 ->
          Buffer.add_char buf c;
          loop (depth - 1) st'
      | '}' -> POk (Text.of_string (Buffer.contents buf), st', true)
      | _ ->
          Buffer.add_char buf c;
          loop depth st'
  in
  fun st -> loop 0 st

let bare_number : Text.t t = take_while1 is_digit
let field_value : Text.t t = braced_value <|> bare_number

let field : (Text.t * Text.t) t =
  let* name = ws *> take_while1 is_field_name_char in
  let* _ = ws *> expect_char '=' in
  let* value = ws *> field_value in
  return (name, value)

let fields : (Text.t * Text.t) list t =
  let sep = ws *> expect_char ',' *> ws in
  let* first = option_maybe field in
  match first with
  | None -> return []
  | Some f ->
      let* rest = many (try_ (sep *> field)) in
      let* _ = optional (try_ (ws *> expect_char ',')) in
      return (f :: rest)

let raw_entry_type : Text.t t = expect_char '@' *> take_while1 is_alpha
let raw_entry_key : Text.t t = take_while1 is_key_char

(* --- field lookup in raw (key, value) list --- *)

let find_field fs name =
  List.find_map
    (fun (k, v) ->
      if String.lowercase_ascii (Text.to_string k) = name then Some v else None)
    fs

let require_field fs field_name ~entry_type key =
  match find_field fs field_name with
  | Some v -> return v
  | None ->
      fail
        (Printf.sprintf "@%s{%s}: missing required field '%s'" entry_type
           (Text.to_string key) field_name)

(* --- classification into typed entries --- *)

let classify_entry typ key fs : entry t =
  let t = String.lowercase_ascii (Text.to_string typ) in
  match t with
  | "book" ->
      let* author = require_field fs ~entry_type:t "author" key in
      let* title = require_field fs ~entry_type:t "title" key in
      return
        (Book
           {
             book_key = key;
             book_author = author;
             book_title = title;
             book_year = find_field fs "year";
             book_url = find_field fs "url";
             book_isbn = find_field fs "isbn";
           })
  | "article" ->
      let* author = require_field fs ~entry_type:t "author" key in
      let* title = require_field fs ~entry_type:t "title" key in
      return
        (Article
           {
             article_key = key;
             article_author = author;
             article_title = title;
             article_journal = find_field fs "journal";
             article_year = find_field fs "year";
             article_url = find_field fs "url";
           })
  | "phdthesis" ->
      let* author = require_field fs ~entry_type:t "author" key in
      let* title = require_field fs ~entry_type:t "title" key in
      return
        (Phdthesis
           {
             phdthesis_key = key;
             phdthesis_author = author;
             phdthesis_title = title;
             phdthesis_school = find_field fs "school";
             phdthesis_year = find_field fs "year";
             phdthesis_url = find_field fs "url";
           })
  | "blog" ->
      let* title = require_field fs ~entry_type:t "title" key in
      let* url = require_field fs ~entry_type:t "url" key in
      return
        (Blog
           {
             blog_key = key;
             blog_title = title;
             blog_author = find_field fs "author";
             blog_url = url;
           })
  | "podcast" ->
      let* title = require_field fs ~entry_type:t "title" key in
      let* url = require_field fs ~entry_type:t "url" key in
      return
        (Podcast
           {
             podcast_key = key;
             podcast_title = title;
             podcast_author = find_field fs "author";
             podcast_url = url;
           })
  | "talk" ->
      let* author = require_field fs ~entry_type:t "author" key in
      let* title = require_field fs ~entry_type:t "title" key in
      return
        (Talk
           {
             talk_key = key;
             talk_author = author;
             talk_title = title;
             talk_year = find_field fs "year";
             talk_url = find_field fs "url";
           })
  | "misc" ->
      let* title = require_field fs ~entry_type:t "title" key in
      return
        (Misc
           {
             misc_key = key;
             misc_title = title;
             misc_author = find_field fs "author";
             misc_year = find_field fs "year";
             misc_url = find_field fs "url";
           })
  | _ -> fail (Printf.sprintf "unknown entry type '@%s'" t)

let parse_entry : entry t =
  let* typ = ws *> raw_entry_type in
  let* _ = ws *> expect_char '{' in
  let* key = ws *> raw_entry_key in
  let* _ = ws *> expect_char ',' in
  let* fs = fields in
  let* _ = ws *> expect_char '}' in
  classify_entry typ key fs

(* --- skip @comment, @preamble, @string --- *)

let skip_comment : unit t =
  let* _ = expect_char '@' *> take_while1 is_alpha in
  let* _ = ws *> expect_char '{' in
  let rec loop depth st =
    if st.ofs >= String.length st.src then
      PFail (st.pos, lazy "unterminated comment", true)
    else
      let c = st.src.[st.ofs] in
      let st' = { st with ofs = st.ofs + 1; pos = Pos.advance st.pos c } in
      match c with
      | '{' -> loop (depth + 1) st'
      | '}' when depth > 0 -> loop (depth - 1) st'
      | '}' -> POk ((), st', true)
      | _ -> loop depth st'
  in
  fun st -> loop 0 st

let is_skipped_type t =
  let s = Text.to_string t |> String.lowercase_ascii in
  s = "comment" || s = "preamble" || s = "string"

let item : entry option t =
  let* typ = ws *> look_ahead (try_ raw_entry_type) in
  if is_skipped_type typ then skip_comment *> return None
  else map (fun e -> Some e) parse_entry

(* --- top-level --- *)

let bib_file : bib_file t =
  let skip_junk = skip_while (fun c -> c <> '@') in
  fun st ->
    let rec loop acc st =
      match skip_junk st with
      | PFail _ as e -> e
      | POk ((), st', _) -> (
          if st'.ofs >= String.length st'.src then
            POk (List.rev (List.filter_map Fun.id acc), st', true)
          else
            match item st' with
            | POk (x, st'', _) -> loop (x :: acc) st''
            | PFail _ as e -> e)
    in
    loop [] st

let parse ~source_name input = run bib_file ~source_name input
