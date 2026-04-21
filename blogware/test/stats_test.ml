open Blogware
open Test_framework
open Document

let txt = Text.of_string
let s x = Str (txt x)

let tests : Test_framework.t list =
  group "stats"
    [
      test "word_count counts prose without tokenizing" (fun () ->
          assert_equal_int 8
            (Stats.word_count
               [
                 Para
                   [
                     s "Memory-mapped IO isn't slow.";
                     Numeric_space;
                     Strong [ s "It scales." ];
                     Line_break;
                     Link (txt "https://example.com", [ s "Read more" ]);
                   ];
               ]));
      test "word_count ignores code math and media" (fun () ->
          assert_equal_int 4
            (Stats.word_count
               [
                 Para [ s "Count this short paragraph." ];
                 Code_block ([], [ s "let x = 1" ]);
                 Verbatim_block ([], Text.of_string "printfn \"hello\"");
                 Para [ Math (Math_inline, []) ];
                 Image ([], txt "/images/example.svg");
               ]));
      test "word_count carries state across inline boundaries" (fun () ->
          assert_equal_int 1
            (Stats.word_count [ Para [ Small_caps [ s "llm" ]; s "s" ] ]));
      test "word_count treats inline separators as boundaries" (fun () ->
          assert_equal_int 4
            (Stats.word_count
               [
                 Para
                   [
                     s "one";
                     Numeric_space;
                     s "two";
                     Line_break;
                     s "three";
                     Math (Math_inline, []);
                     s "four";
                   ];
               ]));
      test "word_count includes headings notes tables and quotes" (fun () ->
          assert_equal_int 14
            (Stats.word_count
               [
                 Section
                   ( Some (txt "intro", [ s "One heading" ]),
                     [
                       Para [ s "Two body words." ];
                       Blockquote ([ Para [ s "Three quoted words." ] ], []);
                       Table
                         {
                           table_spec = [ Col_left ];
                           table_header =
                             Some
                               {
                                 tr_border_top = false;
                                 tr_border_bottom = false;
                                 tr_cells =
                                   [
                                     {
                                       tc_colspan = 1;
                                       tc_align = Col_left;
                                       tc_content =
                                         [ s "Four header words here" ];
                                     };
                                   ];
                               };
                           table_rows =
                             [
                               {
                                 tr_border_top = false;
                                 tr_border_bottom = false;
                                 tr_cells =
                                   [
                                     {
                                       tc_colspan = 1;
                                       tc_align = Col_left;
                                       tc_content =
                                         [
                                           Margin_note
                                             (txt "n1", [ s "Two note" ]);
                                         ];
                                     };
                                   ];
                               };
                             ];
                           table_opts = [];
                         };
                     ] );
               ]));
    ]
