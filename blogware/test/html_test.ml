(* Tests for the Html builder. Covers the pieces most likely to regress:
   escaping, composition, attribute emission, and leaf vs parent tags. *)

open Blogware
open Test_framework
open Html

let t name expected actual : Test_framework.t =
  test name (fun () -> assert_equal_string expected (render actual))

let tests : Test_framework.t list =
  group "html"
    [ t "empty" "" empty

    ; t "text escapes lt"
        "a&lt;b"
        (text "a<b")

    ; t "text escapes all specials"
        "&lt;&gt;&amp;&quot;"
        (text "<>&\"")

    ; t "text no-escape apostrophe"
        "it's"
        (text "it's")

    ; t "raw passes through"
        "a<b"
        (raw "a<b")

    ; t "compose with ++"
        "ab"
        (text "a" ++ text "b")

    ; t "concat"
        "abc"
        (concat [text "a"; text "b"; text "c"])

    ; t "parent empty body"
        "<div></div>"
        (div_ [] empty)

    ; t "parent with text body"
        "<p>hi</p>"
        (p_ [] (text "hi"))

    ; t "parent with class attr"
        "<div class=\"foo\">hi</div>"
        (div_ [class_ "foo"] (text "hi"))

    ; t "multiple attrs preserve order"
        "<a href=\"u\" class=\"x\">link</a>"
        (a_ [href_ "u"; class_ "x"] (text "link"))

    ; t "attr escaping"
        "<a href=\"a&amp;b\">x</a>"
        (a_ [href_ "a&b"] (text "x"))

    ; t "leaf no attrs"
        "<br>"
        (br_ [])

    ; t "leaf with attrs"
        "<img src=\"p.png\" alt=\"x\">"
        (leaf "img" [src_ "p.png"; alt_ "x"])

    ; t "nested parents"
        "<ul><li>a</li><li>b</li></ul>"
        (ul_ [] (li_ [] (text "a") ++ li_ [] (text "b")))

    ; t "doctype"
        "<!DOCTYPE html>"
        doctype

    ; t "nl is newline"
        "\n"
        nl
    ]
