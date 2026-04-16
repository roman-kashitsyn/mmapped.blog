(* Math parser tests. Minimal smoke coverage at this phase. *)

open Blogware
open Test_framework
open Syntax

let parse_math input : (math_node list, Error.parse_error) result =
  (* Wrap input in $...$ and pick the math payload out of the resulting AST. *)
  match Tex_parser.parse_document ~source_name:"<test>" ("$" ^ input ^ "$") with
  | Error _ as e -> e
  | Ok [ NMath (_, _, ns) ] -> Ok ns
  | Ok _ ->
      Error
        {
          Error.pe_source_name = "<test>";
          pe_pos = Parser.Pos.make 0;
          pe_message = "unexpected top-level structure";
        }

let show_math_list ns =
  let rec go = function
    | Math_text s -> "text(" ^ s ^ ")"
    | Math_num s -> "num(" ^ s ^ ")"
    | Math_op (s, _) -> "op(" ^ s ^ ")"
    | Math_sym c -> "sym(" ^ String.make 1 c ^ ")"
    | Math_cmd (n, args) ->
        "cmd(" ^ n ^ "," ^ String.concat "," (List.map go args) ^ ")"
    | Math_group xs -> "grp[" ^ String.concat ";" (List.map go xs) ^ "]"
    | Math_term (nuc, sub, sup) ->
        "term(" ^ go nuc ^ ","
        ^ (match sub with Some s -> go s | None -> "_")
        ^ ","
        ^ (match sup with Some s -> go s | None -> "_")
        ^ ")"
    | Math_frac (n, d) -> "frac(" ^ go n ^ "," ^ go d ^ ")"
  in
  String.concat " " (List.map go ns)

let math_expect name input expected : Test_framework.t =
  test name (fun () ->
      match parse_math input with
      | Error e -> Fail ("parse error: " ^ e.pe_message)
      | Ok ns -> assert_equal_string expected (show_math_list ns))

let tests : Test_framework.t list =
  group "math"
    [
      math_expect "single letter" "x" "text(x)";
      math_expect "single number" "42" "num(42)";
      math_expect "plus" "a+b" "text(a) op(+) text(b)";
      math_expect "minus sign" "-1" "num(-1)";
      math_expect "multi-digit negative number" "-42" "num(-42)";
      math_expect "bare minus stays operator" "-" "op(-)";
      math_expect "subtraction is binary" "a-1" "text(a) op(-) num(1)";
      math_expect "subscript" "x_i" "term(text(x),text(i),_)";
      math_expect "superscript" "x^2" "term(text(x),_,num(2))";
      math_expect "frac command" "\\frac{a}{b}"
        "cmd(frac,grp[text(a)],grp[text(b)])";
    ]
