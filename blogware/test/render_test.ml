(* Render tests. Smoke coverage; the pipeline tests in Phase 9 will
   exercise the end-to-end path. *)

open Blogware
open Test_framework
open Document

let txt = Text.of_string
let s x = Str (txt x)

let t name expected actual_html : Test_framework.t =
  test name (fun () -> assert_equal_string expected (Html.render actual_html))

let tests : Test_framework.t list =
  group "render"
    [
      t "simple paragraph" "<p>hi</p>\n"
        (Render.render_block Render.empty_ctx (Para [ s "hi" ]));
      t "plain inlines" "hi"
        (Render.render_block Render.empty_ctx (Plain [ s "hi" ]));
      t "strong inline" "<b>bold</b>"
        (Render.render_inline Render.empty_ctx (Strong [ s "bold" ]));
      t "link" "<a href=\"/x\">x</a>"
        (Render.render_inline Render.empty_ctx (Link (txt "/x", [ s "x" ])));
      t "anchor" "<span id=\"foo\"></span>"
        (Render.render_inline Render.empty_ctx (Anchor (txt "foo")));
      t "line break" "<br>" (Render.render_inline Render.empty_ctx Line_break);
      t "hrule block" "<hr>\n" (Render.render_block Render.empty_ctx HRule);
      t "section with no header" "<section></section>\n"
        (Render.render_block Render.empty_ctx (Section (None, [])));
      t "section with header and id"
        "<section><h2 id=\"x\"><a href=\"#x\">T</a></h2>\n</section>\n"
        (Render.render_block Render.empty_ctx
           (Section (Some (txt "x", [ s "T" ]), [])));
      t "bullet list arrows" "<ul class=\"arrows\"><li>a</li></ul>\n"
        (Render.render_block Render.empty_ctx
           (Bullet_list (Arrows, [ [ Plain [ s "a" ] ] ])));
      t "ordered list glyph"
        ("<ol class=\"circled\"><li data-num-glyph=\"" ^ "\xE2\x91\xA0"
       (* ① U+2460 *) ^ "\">a</li></ol>\n")
        (Render.render_block Render.empty_ctx
           (Ordered_list [ [ Plain [ s "a" ] ] ]));
      t "image no class" "<p><img src=\"p.png\"></p>\n"
        (Render.render_block Render.empty_ctx (Image ([], txt "p.png")));
      t "image with class" "<p><img class=\"wide\" src=\"p.png\"></p>\n"
        (Render.render_block Render.empty_ctx
           (Image ([ txt "wide" ], txt "p.png")));
      t "svg image wrapped in p.svg"
        "<p class=\"svg\"><img src=\"diagram.svg\"></p>\n"
        (Render.render_block Render.empty_ctx (Image ([], txt "diagram.svg")));
      t "blockquote trims boundary whitespace in quote paragraphs"
        "<blockquote><p>hello <b>world</b></p><footer>by \
         test</footer></blockquote>\n"
        (Render.render_block Render.empty_ctx
           (Blockquote
              ( [ Para [ s "\n  hello "; Strong [ s "world" ]; s "\n" ] ],
                [ s "by test" ] )));
      t "advice anchor uses gutter anchor link"
        "<div class=\"advice\" id=\"hint\"><p><a class=\"anchor \
         left-gutter-anchor advice-anchor\" href=\"#hint\" aria-label=\"Link \
         to this advice\"></a>Use it.</p></div>\n"
        (Render.render_block Render.empty_ctx
           (Advice (txt "hint", [ s "Use it." ])));
    ]
