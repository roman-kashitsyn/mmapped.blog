(* Render tests. Smoke coverage; the pipeline tests in Phase 9 will
   exercise the end-to-end path. *)

open Blogware
open Test_framework
open Document

let t name expected actual_html : Test_framework.t =
  test name (fun () -> assert_equal_string expected (Html.render actual_html))

let tests : Test_framework.t list =
  group "render"
    [
      t "simple paragraph" "<p>hi</p>\n"
        (Render.render_block Render.empty_ctx (Para [ Str "hi" ]));
      t "plain inlines" "hi"
        (Render.render_block Render.empty_ctx (Plain [ Str "hi" ]));
      t "strong inline" "<b>bold</b>"
        (Render.render_inline Render.empty_ctx (Strong [ Str "bold" ]));
      t "link" "<a href=\"/x\">x</a>"
        (Render.render_inline Render.empty_ctx (Link ("/x", [ Str "x" ])));
      t "anchor" "<span id=\"foo\"></span>"
        (Render.render_inline Render.empty_ctx (Anchor "foo"));
      t "line break" "<br>" (Render.render_inline Render.empty_ctx Line_break);
      t "hrule block" "<hr>\n" (Render.render_block Render.empty_ctx HRule);
      t "section with no header" "<section></section>\n"
        (Render.render_block Render.empty_ctx (Section (None, [])));
      t "section with header and id"
        "<section><h2 id=\"x\"><a href=\"#x\">T</a></h2>\n</section>\n"
        (Render.render_block Render.empty_ctx
           (Section (Some ("x", [ Str "T" ]), [])));
      t "bullet list arrows" "<ul class=\"arrows\"><li>a</li></ul>\n"
        (Render.render_block Render.empty_ctx
           (Bullet_list (Arrows, [ [ Plain [ Str "a" ] ] ])));
      t "ordered list glyph"
        ("<ol class=\"circled\"><li data-num-glyph=\"" ^ "\xE2\x91\xA0"
       (* ① U+2460 *) ^ "\">a</li></ol>\n")
        (Render.render_block Render.empty_ctx
           (Ordered_list [ [ Plain [ Str "a" ] ] ]));
      t "image no class" "<p><img src=\"p.png\"></p>\n"
        (Render.render_block Render.empty_ctx (Image ([], "p.png")));
      t "image with class" "<p><img class=\"wide\" src=\"p.png\"></p>\n"
        (Render.render_block Render.empty_ctx (Image ([ "wide" ], "p.png")));
      t "svg image wrapped in p.svg"
        "<p class=\"svg\"><img src=\"diagram.svg\"></p>\n"
        (Render.render_block Render.empty_ctx (Image ([], "diagram.svg")));
      t "blockquote trims boundary whitespace in quote paragraphs"
        "<blockquote><p>hello <b>world</b></p><footer>by test</footer></blockquote>\n"
        (Render.render_block Render.empty_ctx
           (Blockquote
              ([ Para [ Str "\n  hello "; Strong [ Str "world" ]; Str "\n" ] ],
               [ Str "by test" ])));
    ]
