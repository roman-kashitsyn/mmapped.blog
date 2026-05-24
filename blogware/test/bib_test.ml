open Blogware
open Test_framework
open Bib

let s = Text.of_string

let parse input =
  Bib.parse ~source_name:"<test>" input

(* Normalize Text.t Sub nodes to Str so structural equality works. *)
let t s = Text.of_string (Text.to_string s)
let ot s = Option.map t s

let norm_entry = function
  | Book b -> Book { book_key = t b.book_key; book_author = t b.book_author;
      book_title = t b.book_title; book_year = ot b.book_year;
      book_url = ot b.book_url; book_isbn = ot b.book_isbn }
  | Article a -> Article { article_key = t a.article_key;
      article_author = t a.article_author; article_title = t a.article_title;
      article_journal = ot a.article_journal; article_year = ot a.article_year;
      article_url = ot a.article_url }
  | Phdthesis p -> Phdthesis { phdthesis_key = t p.phdthesis_key;
      phdthesis_author = t p.phdthesis_author;
      phdthesis_title = t p.phdthesis_title;
      phdthesis_school = ot p.phdthesis_school;
      phdthesis_year = ot p.phdthesis_year;
      phdthesis_url = ot p.phdthesis_url }
  | Blog b -> Blog { blog_key = t b.blog_key; blog_title = t b.blog_title;
      blog_author = ot b.blog_author; blog_url = t b.blog_url }
  | Talk k -> Talk { talk_key = t k.talk_key; talk_author = t k.talk_author;
      talk_title = t k.talk_title; talk_year = ot k.talk_year;
      talk_url = ot k.talk_url }
  | Podcast p -> Podcast { podcast_key = t p.podcast_key;
      podcast_title = t p.podcast_title; podcast_author = ot p.podcast_author;
      podcast_url = t p.podcast_url }
  | Misc m -> Misc { misc_key = t m.misc_key; misc_title = t m.misc_title;
      misc_author = ot m.misc_author; misc_year = ot m.misc_year;
      misc_url = ot m.misc_url }

let parse_ok name input (expected : entry list) : t =
  test name (fun () ->
      match parse input with
      | Error e -> Fail ("parse error: " ^ e.pe_message)
      | Ok entries ->
          let normalized = List.map norm_entry entries in
          if normalized = expected then Pass
          else
            Fail
              (Printf.sprintf "expected %d entries, got %d"
                 (List.length expected) (List.length normalized)))

let parse_fails name input : t =
  test name (fun () ->
      match parse input with
      | Error _ -> Pass
      | Ok _ -> Fail "expected parse error")

let tests =
  Test_framework.group "bib"
    [
      parse_ok "book with all fields" {|
@book{knuth-taocp,
  author = {Donald Knuth},
  title = {The Art of Computer Programming},
  year = {1968},
  url = {https://www-cs-faculty.stanford.edu/~knuth/taocp.html},
}
|}
        [ Book {
            book_key = s "knuth-taocp";
            book_author = s "Donald Knuth";
            book_title = s "The Art of Computer Programming";
            book_year = Some (s "1968");
            book_url = Some (s "https://www-cs-faculty.stanford.edu/~knuth/taocp.html");
            book_isbn = None;
          } ];

      parse_ok "book with bare numeric year" {|
@book{foo,
  author = {Bar},
  title = {Baz},
  year = 2009,
}
|}
        [ Book {
            book_key = s "foo";
            book_author = s "Bar";
            book_title = s "Baz";
            book_year = Some (s "2009");
            book_url = None;
            book_isbn = None;
          } ];

      parse_ok "article" {|
@article{dijkstra-goto,
  author = {Edsger Dijkstra},
  title = {Go To Statement Considered Harmful},
  journal = {Communications of the ACM},
  year = {1968},
}
|}
        [ Article {
            article_key = s "dijkstra-goto";
            article_author = s "Edsger Dijkstra";
            article_title = s "Go To Statement Considered Harmful";
            article_journal = Some (s "Communications of the ACM");
            article_year = Some (s "1968");
            article_url = None;
          } ];

      parse_ok "blog" {|
@blog{danluu-p95,
  author = {Dan Luu},
  title = {95%-ile isn't that good},
  url = {https://danluu.com/p95-skill/},
}
|}
        [ Blog {
            blog_key = s "danluu-p95";
            blog_title = s "95%-ile isn't that good";
            blog_author = Some (s "Dan Luu");
            blog_url = s "https://danluu.com/p95-skill/";
          } ];

      parse_ok "talk" {|
@talk{parent-cpp-seasoning,
  author = {Sean Parent},
  title = {C++ Seasoning},
  year = {2013},
  url = {https://youtu.be/W2tWOdzgXHA},
}
|}
        [ Talk {
            talk_key = s "parent-cpp-seasoning";
            talk_author = s "Sean Parent";
            talk_title = s "C++ Seasoning";
            talk_year = Some (s "2013");
            talk_url = Some (s "https://youtu.be/W2tWOdzgXHA");
          } ];

      parse_ok "podcast" {|
@podcast{wizardology,
  title = {Wizardology podcast},
  url = {https://example.com/wiz},
}
|}
        [ Podcast {
            podcast_key = s "wizardology";
            podcast_title = s "Wizardology podcast";
            podcast_author = None;
            podcast_url = s "https://example.com/wiz";
          } ];

      parse_ok "phdthesis" {|
@phdthesis{dolstra-nix,
  author = {Eelco Dolstra},
  title = {The Purely Functional Software Deployment Model},
  school = {Utrecht University},
  year = {2006},
  url = {https://edolstra.github.io/pubs/phd-thesis.pdf},
}
|}
        [ Phdthesis {
            phdthesis_key = s "dolstra-nix";
            phdthesis_author = s "Eelco Dolstra";
            phdthesis_title = s "The Purely Functional Software Deployment Model";
            phdthesis_school = Some (s "Utrecht University");
            phdthesis_year = Some (s "2006");
            phdthesis_url = Some (s "https://edolstra.github.io/pubs/phd-thesis.pdf");
          } ];

      parse_ok "misc" {|
@misc{feynman-trinity,
  author = {Richard Feynman},
  title = {My Observations During the Explosion at Trinity on July 16, 1945},
}
|}
        [ Misc {
            misc_key = s "feynman-trinity";
            misc_title = s "My Observations During the Explosion at Trinity on July 16, 1945";
            misc_author = Some (s "Richard Feynman");
            misc_year = None;
            misc_url = None;
          } ];

      parse_ok "no trailing comma" {|
@article{bar,
  author = {Baz},
  title = {Quux}
}
|}
        [ Article {
            article_key = s "bar";
            article_author = s "Baz";
            article_title = s "Quux";
            article_journal = None;
            article_year = None;
            article_url = None;
          } ];

      parse_ok "nested braces in value"
        {|@misc{x, title = {A {Nested} Title}}|}
        [ Misc {
            misc_key = s "x";
            misc_title = s "A {Nested} Title";
            misc_author = None;
            misc_year = None;
            misc_url = None;
          } ];

      parse_ok "multiple entries" {|
@misc{a, title = {First}}
@misc{b, title = {Second}}
|}
        [ Misc { misc_key = s "a"; misc_title = s "First";
                 misc_author = None; misc_year = None; misc_url = None };
          Misc { misc_key = s "b"; misc_title = s "Second";
                 misc_author = None; misc_year = None; misc_url = None } ];

      parse_ok "comment entries are skipped" {|
@comment{this is ignored}
@misc{real, title = {Real}}
@preamble{also ignored}
|}
        [ Misc { misc_key = s "real"; misc_title = s "Real";
                 misc_author = None; misc_year = None; misc_url = None } ];

      parse_ok "junk between entries" {|
% This is a BibTeX comment line
Some random text here

@misc{x, title = {Hello}}
|}
        [ Misc { misc_key = s "x"; misc_title = s "Hello";
                 misc_author = None; misc_year = None; misc_url = None } ];

      parse_ok "empty file" "" [];

      parse_ok "key with dots and colons"
        {|@misc{rfc:2119.v2, title = {RFC}}|}
        [ Misc { misc_key = s "rfc:2119.v2"; misc_title = s "RFC";
                 misc_author = None; misc_year = None; misc_url = None } ];

      parse_fails "unterminated value"
        {|@misc{x, title = {unclosed|};

      parse_fails "missing closing brace"
        {|@misc{x, title = {ok}|};

      parse_fails "unknown entry type"
        {|@thesis{x, title = {Foo}}|};

      parse_fails "book missing author"
        {|@book{x, title = {Foo}}|};

      parse_fails "blog missing url"
        {|@blog{x, title = {Foo}}|};

      test "entry_key accessor" (fun () ->
          match parse {|@misc{my-key, title = {T}}|} with
          | Error e -> Fail e.pe_message
          | Ok [ e ] ->
              assert_equal_string "my-key" (Text.to_string (entry_key e))
          | Ok _ -> Fail "expected one entry");
    ]
