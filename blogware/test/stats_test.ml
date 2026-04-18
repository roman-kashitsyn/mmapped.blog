open Blogware
open Test_framework

let tests : Test_framework.t list =
  group "stats"
    [
      test "word_count counts prose without tokenizing" (fun () ->
          assert_equal_int 8
            (Stats.word_count
               [
                 Para
                   [
                     Str "Memory-mapped IO isn't slow.";
                     Numeric_space;
                     Strong [ Str "It scales." ];
                     Line_break;
                     Link ("https://example.com", [ Str "Read more" ]);
                   ];
               ]));
      test "word_count ignores code math and media" (fun () ->
          assert_equal_int 4
            (Stats.word_count
               [
                 Para [ Str "Count this short paragraph." ];
                 Code_block ([], [ Str "let x = 1" ]);
                 Verbatim_block ([], "printfn \"hello\"");
                 Para [ Math (Math_inline, []) ];
                 Image ([], "/images/example.svg");
               ]));
      test "word_count carries state across inline boundaries" (fun () ->
          assert_equal_int 1
            (Stats.word_count [ Para [ Small_caps [ Str "llm" ]; Str "s" ] ]));
      test "word_count treats inline separators as boundaries" (fun () ->
          assert_equal_int 4
            (Stats.word_count
               [
                 Para
                   [
                     Str "one";
                     Numeric_space;
                     Str "two";
                     Line_break;
                     Str "three";
                     Math (Math_inline, []);
                     Str "four";
                   ];
               ]));
      test "word_count includes headings notes tables and quotes" (fun () ->
          assert_equal_int 14
            (Stats.word_count
               [
                 Section
                   ( Some ("intro", [ Str "One heading" ]),
                     [
                       Para [ Str "Two body words." ];
                       Blockquote ([ Para [ Str "Three quoted words." ] ], []);
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
                                         [ Str "Four header words here" ];
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
                                           Margin_note ("n1", [ Str "Two note" ]);
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
