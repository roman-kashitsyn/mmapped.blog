(* Render.MathML tests. *)

open Blogware
open Test_framework
open Syntax

let t name expected actual_html : Test_framework.t =
  test name (fun () -> assert_equal_string expected (Html.render actual_html))

let s = Text.of_string

let u cp =
  let buf = Buffer.create 4 in
  Buffer.add_utf_8_uchar buf (Uchar.of_int cp);
  Buffer.contents buf

let tests : Test_framework.t list =
  group "render_mathml"
    [
      t "inline math letter"
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" \
         class=\"math\"><mi>x</mi></math>"
        (Render_mathml.render_math Math_inline [ Math_text (s "x") ]);
      t "display math"
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" class=\"math\" \
         display=\"block\"><mn>42</mn></math>"
        (Render_mathml.render_math Math_display [ Math_num (s "42") ]);
      t "operator escapes lt" "<mo stretchy=\"false\">&lt;</mo>"
        (Render_mathml.render_math_node (Math_op (s "<", false)));
      t "stretchy op no attr" "<mo>(</mo>"
        (Render_mathml.render_math_node (Math_op (s "(", true)));
      t "subscript term uses msub" "<msub><mi>x</mi><mi>i</mi></msub>"
        (Render_mathml.render_math_node
           (Math_term (Math_text (s "x"), Some (Math_text (s "i")), None)));
      t "superscript term uses msup" "<msup><mi>x</mi><mn>2</mn></msup>"
        (Render_mathml.render_math_node
           (Math_term (Math_text (s "x"), None, Some (Math_num (s "2")))));
      t "sum term uses munderover"
        "<munderover><mo>∑</mo><mn>1</mn><mi>n</mi></munderover>"
        (Render_mathml.render_math_node
           (Math_term
              ( Math_cmd (S_sum, []),
                Some (Math_num (s "1")),
                Some (Math_text (s "n")) )));
      t "frac command"
        "<mrow><mfrac><mrow><mi>a</mi></mrow><mrow><mi>b</mi></mrow></mfrac></mrow>"
        (Render_mathml.render_math_node
           (Math_cmd (S_frac, [ Math_text (s "a"); Math_text (s "b") ])));
      t "operatorname command uses mi" "<mi>max</mi>"
        (Render_mathml.render_math_node
           (Math_cmd (S_operatorname, [ Math_op (s "max", false) ])));
      t "mathcal command maps letters"
        (String.concat ""
           [
             "<mi>";
             u 0x1D49C;
             u 0x1D4B7;
             u 0x1D4CF;
             "</mi>";
           ])
        (Render_mathml.render_math_node
           (Math_cmd (S_mathcal, [ Math_op (s "Abz", false) ])));
      t "setminus command" "<mo>∖</mo>"
        (Render_mathml.render_math_node (Math_cmd (S_setminus, [])));
      t "align table"
        "<mtable columnalign=\"right left \
         \"><mtr><mtd><mrow><mi>a</mi></mrow></mtd><mtd><mrow><mo \
         stretchy=\"false\">=</mo><mi>b</mi></mrow></mtd></mtr><mtr><mtd><mrow><mi>c</mi></mrow></mtd><mtd><mrow><mo \
         stretchy=\"false\">=</mo><mi>d</mi></mrow></mtd></mtr></mtable>"
        (Render_mathml.render_math_node
           (Math_align
              ( [ Col_right; Col_left ],
                [
                  [
                    [ Math_text (s "a") ];
                    [ Math_op (s "=", false); Math_text (s "b") ];
                  ];
                  [
                    [ Math_text (s "c") ];
                    [ Math_op (s "=", false); Math_text (s "d") ];
                  ];
                ] )));
    ]
