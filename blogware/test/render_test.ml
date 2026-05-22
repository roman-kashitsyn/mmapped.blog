(* Render tests. Smoke coverage; the pipeline tests in Phase 9 will
   exercise the end-to-end path. *)

open Blogware
open Test_framework
open Document

let txt = Text.of_string
let s x = Str (txt x)

let t name expected actual_html : Test_framework.t =
  test name (fun () -> assert_equal_string expected (Html.render actual_html))

let table ?(opts = []) () =
  Table
    {
      table_spec = [ Col_left; Col_left ];
      table_header = None;
      table_rows =
        [
          {
            tr_border_top = false;
            tr_border_bottom = false;
            tr_cells =
              [
                { tc_colspan = 1; tc_align = Col_left; tc_content = [ s "a" ] };
                { tc_colspan = 1; tc_align = Col_left; tc_content = [ s "b" ] };
              ];
          };
        ];
      table_opts = List.map txt opts;
    }

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
      t "circled ref uses generated content"
        ("<span class=\"circled-ref\" data-num-glyph=\"" ^ "\xE2\x91\xA0"
       (* ① U+2460 *)
       ^ "\" aria-label=\"step 1\" role=\"img\"></span>")
        (Render.render_inline Render.empty_ctx (Circled_ref 1));
      t "highlighted inline role" "<span class=\"hl-kw\">func</span>"
        (Render.render_inline Render.empty_ctx
           (Highlighted (Hl_keyword, [ s "func" ])));
      t "highlighted typedef role" "<span class=\"hl-typedef\">Server</span>"
        (Render.render_inline Render.empty_ctx
           (Highlighted (Hl_typedef, [ s "Server" ])));
      t "hrule block" "<hr>\n" (Render.render_block Render.empty_ctx HRule);
      t "section with no header" "<section></section>\n"
        (Render.render_block Render.empty_ctx (Section (None, [])));
      t "section with header and id"
        "<section><h2 id=\"x\"><a href=\"#x\">T</a></h2>\n</section>\n"
        (Render.render_block Render.empty_ctx
           (Section (Some (txt "x", [ s "T" ]), [])));
      t "bullet list bullets" "<ul class=\"bullets\"><li>a</li></ul>\n"
        (Render.render_block Render.empty_ctx
           (Bullet_list (Bullets, [ [ Plain [ s "a" ] ] ])));
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
      t "table without uniform option has no generated width class"
        "<table><tbody><tr><td colspan=\"1\" class=\"align-l\">a</td><td \
         colspan=\"1\" class=\"align-l\">b</td></tr></tbody></table>\n"
        (Render.render_block Render.empty_ctx (table ()));
      t "table with uniform option has generated width class"
        "<table class=\"table-2 uniform\"><tbody><tr><td colspan=\"1\" \
         class=\"align-l\">a</td><td colspan=\"1\" \
         class=\"align-l\">b</td></tr></tbody></table>\n"
        (Render.render_block Render.empty_ctx (table ~opts:[ "uniform" ] ()));
      t "blockquote trims boundary whitespace in quote paragraphs"
        {|<figure class="bq left-gutter-anchor"><blockquote><p>hello <b>world</b></p></blockquote><figcaption>by test</figcaption></figure>
|}
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
      t "go code block emits syntax spans inside lines"
        "<div class=\"source-container\"><pre class=\"source go\"><code><span \
         class=\"line\"><span class=\"hl-kw\">package</span> <span \
         class=\"hl-id\">main</span></span>\n\
         <span class=\"line\"><span class=\"hl-kw\">func</span> <span \
         class=\"hl-defun\">main</span>() {}</span>\n\
         </code></pre></div>\n"
        (Render.render_block Render.empty_ctx
           (Code_block ([ txt "go" ], [ s "package main\nfunc main() {}" ])));
      t "go code block emits typedef spans"
        "<div class=\"source-container\"><pre class=\"source go\"><code><span \
         class=\"line\"><span class=\"hl-kw\">type</span> <span \
         class=\"hl-typedef\">Server</span> <span \
         class=\"hl-kw\">struct</span>{}</span>\n\
         </code></pre></div>\n"
        (Render.render_block Render.empty_ctx
           (Code_block ([ txt "go" ], [ s "type Server struct{}" ])));
      t "non-go code block remains unchanged"
        "<div class=\"source-container\"><pre class=\"source \
         rust\"><code><span class=\"line\">fn main() {}</span>\n\
         </code></pre></div>\n"
        (Render.render_block Render.empty_ctx
           (Code_block ([ txt "rust" ], [ s "fn main() {}" ])));
      t "go code block preserves embedded inlines"
        "<div class=\"source-container\"><pre class=\"source go\"><code><span \
         class=\"line\"><span class=\"hl-kw\">func</span> <span \
         id=\"code-label\"></span><span class=\"hl-id\">main</span>() <a \
         href=\"/x\">body</a></span>\n\
         </code></pre></div>\n"
        (Render.render_block Render.empty_ctx
           (Code_block
              ( [ txt "go" ],
                [
                  s "func ";
                  Anchor (txt "code-label");
                  s "main() ";
                  Link (txt "/x", [ s "body" ]);
                ] )));
      t "go line comment spans embedded inlines"
        "<div class=\"source-container\"><pre class=\"source go\"><code><span \
         class=\"line\"><span class=\"hl-comment\">// Hello <span \
         class=\"smallcaps\">cruel</span> world!</span></span>\n\
         </code></pre></div>\n"
        (Render.render_block Render.empty_ctx
           (Code_block
              ( [ txt "go" ],
                [ s "// Hello "; Small_caps [ s "cruel" ]; s " world!" ] )));
    ]
