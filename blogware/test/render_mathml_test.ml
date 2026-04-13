(* Render.MathML tests. *)

open Blogware
open Test_framework
open Syntax

let t name expected actual_html : Test_framework.t =
  test name (fun () -> assert_equal_string expected (Html.render actual_html))

let tests : Test_framework.t list =
  group "render_mathml"
    [ t "inline math letter"
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" class=\"math\">\
           <mi>x</mi></math>"
        (Render_mathml.render_math Math_inline [Math_text "x"])

    ; t "display math"
        "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" class=\"math\" \
           display=\"block\"><mn>42</mn></math>"
        (Render_mathml.render_math Math_display [Math_num "42"])

    ; t "operator escapes lt"
        "<mo stretchy=\"false\">&lt;</mo>"
        (Render_mathml.render_math_node (Math_op ("<", false)))

    ; t "stretchy op no attr"
        "<mo>(</mo>"
        (Render_mathml.render_math_node (Math_op ("(", true)))

    ; t "subscript term uses msub"
        "<msub><mi>x</mi><mi>i</mi></msub>"
        (Render_mathml.render_math_node
           (Math_term (Math_text "x", Some (Math_text "i"), None)))

    ; t "superscript term uses msup"
        "<msup><mi>x</mi><mn>2</mn></msup>"
        (Render_mathml.render_math_node
           (Math_term (Math_text "x", None, Some (Math_num "2"))))

    ; t "sum term uses munderover"
        "<munderover><mo>∑</mo><mn>1</mn><mi>n</mi></munderover>"
        (Render_mathml.render_math_node
           (Math_term
              (Math_cmd ("sum", []),
               Some (Math_num "1"),
               Some (Math_text "n"))))

    ; t "frac command"
        "<mrow><mfrac><mrow><mi>a</mi></mrow><mrow><mi>b</mi></mrow></mfrac></mrow>"
        (Render_mathml.render_math_node
           (Math_cmd ("frac", [Math_text "a"; Math_text "b"])))
    ]
