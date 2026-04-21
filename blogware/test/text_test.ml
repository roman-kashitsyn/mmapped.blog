open Blogware
open Test_framework
open Text
open Quickcheck

let test_eq (name : string) (s : string) (t : t) =
  test name (fun () -> assert_equal_string s (to_string t))

let show_string_list xs =
  "[" ^ String.concat "; " (List.map (Printf.sprintf "%S") xs) ^ "]"

let show_pair show_a show_b (a, b) =
  Printf.sprintf "(%s, %s)" (show_a a) (show_b b)

let text_of_chunks chunks =
  List.fold_left
    (fun acc chunk ->
      let part =
        if String.length chunk = 1 then of_char chunk.[0] else of_string chunk
      in
      append acc part)
    empty chunks

let chunk_generator =
  Generator.one_of
    [|
      Generator.return "";
      Generator.string ~length:(Generator.return 1) ();
      Generator.string ~length:(Generator.int_inclusive 0 8) ();
    |]

let text_and_string_generator =
  Generator.map
    (Generator.list ~length:(Generator.int_inclusive 0 8) chunk_generator)
    (fun chunks ->
      let text = text_of_chunks chunks in
      let string = String.concat "" chunks in
      (text, string))

let test_property name gen ~show ~f =
  test name (fun () -> Quickcheck.check gen ~show ~f)

let sign n = if n < 0 then -1 else if n > 0 then 1 else 0

let tests : Test_framework.t list =
  group "text"
    [
      test_eq "append" "abcd" (append (of_string "abc") (of_char 'd'));
      test "equal" (fun () ->
          assert_bool "text not equal"
            (equal
               (append (append (of_string "a") (of_char 'b')) empty)
               (of_string "ab")));
      test_property "of_string roundtrip"
        (Generator.string ~length:(Generator.int_inclusive 0 32) ())
        ~show:(Printf.sprintf "%S")
        ~f:(fun s -> assert_equal_string s (to_string (of_string s)));
      test_property "is_empty matches string emptiness"
        (Generator.string ~length:(Generator.int_inclusive 0 32) ())
        ~show:(Printf.sprintf "%S")
        ~f:(fun s ->
          assert_bool "empty predicate mismatch"
            (is_empty (of_string s) = (String.length s = 0)));
      test_property "equal matches string equality"
        (Generator.pair
           (Generator.string ~length:(Generator.int_inclusive 0 24) ())
           (Generator.string ~length:(Generator.int_inclusive 0 24) ()))
        ~show:(show_pair (Printf.sprintf "%S") (Printf.sprintf "%S"))
        ~f:(fun (left, right) ->
          assert_bool "equality mismatch"
            (equal (of_string left) (of_string right) = (left = right)));
      test_property "hash is representation-independent"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let same =
            if String.length s < 2 then of_string s
            else
              let mid = String.length s / 2 in
              append (of_substr s 0 mid)
                (of_substr s mid (String.length s - mid))
          in
          assert_bool "equal text values must hash equally"
            (equal text same && hash text = hash same));
      test_property "compare matches String.compare"
        (Generator.pair text_and_string_generator text_and_string_generator)
        ~show:
          (show_pair
             (show_pair debug (Printf.sprintf "%S"))
             (show_pair debug (Printf.sprintf "%S")))
        ~f:(fun ((left, left_s), (right, right_s)) ->
          assert_equal_int
            (sign (String.compare left_s right_s))
            (sign (compare left right)));
      test_property "compare is representation-independent"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let same =
            if String.length s < 2 then of_string s
            else
              let mid = String.length s / 2 in
              append (of_substr s 0 mid)
                (of_substr s mid (String.length s - mid))
          in
          assert_equal_int 0 (compare text same));
      test_property "append matches string concatenation"
        (Generator.pair text_and_string_generator text_and_string_generator)
        ~show:
          (show_pair
             (show_pair debug (Printf.sprintf "%S"))
             (show_pair debug (Printf.sprintf "%S")))
        ~f:(fun ((left, left_s), (right, right_s)) ->
          assert_equal_string (left_s ^ right_s) (to_string (append left right)));
      test_property "fold_left matches String.fold_left"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          assert_equal_int
            (String.fold_left (fun acc c -> acc + Char.code c) 0 s)
            (fold_left (fun acc c -> acc + Char.code c) 0 text));
      test_property "fold_right matches String.fold_right"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          assert_equal_string
            (String.fold_right (fun c acc -> String.make 1 c ^ acc) s "")
            (fold_right (fun c acc -> String.make 1 c ^ acc) text ""));
      test_property "to_seq preserves characters" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          assert_equal ~show:show_string_list
            (List.of_seq (String.to_seq s) |> List.map (String.make 1))
            (List.of_seq (to_seq text) |> List.map (String.make 1)));
      test_property "get matches string indexing"
        (Generator.bind
           (Generator.string ~length:(Generator.int_inclusive 1 32) ())
           (fun s ->
             Generator.map
               (Generator.int_inclusive 0 (String.length s - 1))
               (fun i -> (s, i))))
        ~show:(show_pair (Printf.sprintf "%S") string_of_int)
        ~f:(fun (s, i) ->
          let text = of_string s in
          assert_bool "indexed character mismatch" (get text i = String.get s i));
      test_property "sub matches String.sub on ropes"
        (Generator.bind text_and_string_generator (fun (text, s) ->
             Generator.map
               (Generator.pair
                  (Generator.int_inclusive 0 (String.length s))
                  (Generator.int_inclusive 0 (String.length s)))
               (fun (i, n) -> (text, s, i, n))))
        ~show:(fun (_text, s, i, n) -> Printf.sprintf "(%S, %d, %d)" s i n)
        ~f:(fun (text, s, i, n) ->
          if i + n > String.length s then Pass
          else assert_equal_string (String.sub s i n) (to_string (sub text i n)));
      test_property "map matches String.map" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let f c = Char.chr (Char.code c lxor 1) in
          assert_equal_string (String.map f s) (to_string (map f text)));
      test "map on Sub node with pos > 0" (fun () ->
          let text = of_substr "hello" 1 3 in
          let f c = Char.chr (Char.code c + 1) in
          assert_equal_string (String.map f "ell") (to_string (map f text)));
      test_property "mapi matches String.mapi" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let f i c = Char.chr ((Char.code c + i) mod 256) in
          assert_equal_string (String.mapi f s) (to_string (mapi f text)));
      test_property "split_at matches sub pairs"
        (Generator.bind text_and_string_generator (fun (text, s) ->
             Generator.map
               (Generator.int_inclusive 0 (String.length s))
               (fun i -> (text, s, i))))
        ~show:(fun (_text, s, i) -> Printf.sprintf "(%S, %d)" s i)
        ~f:(fun (text, s, i) ->
          let l, r = split_at text i in
          let check_l = assert_equal_string (String.sub s 0 i) (to_string l) in
          match check_l with
          | Fail _ -> check_l
          | Pass ->
              assert_equal_string
                (String.sub s i (String.length s - i))
                (to_string r));
      test_property "exists matches String.exists" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let f c = Char.code c > 127 in
          assert_bool "exists mismatch" (exists f text = String.exists f s));
      test_property "for_all matches String.for_all" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let f c = Char.code c <= 127 in
          assert_bool "for_all mismatch" (for_all f text = String.for_all f s));
      test_property "of_substr matches String.sub" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (_text, s) ->
          let n = String.length s in
          if n = 0 then Pass
          else
            let i = Random.int n in
            let len = Random.int (n - i + 1) in
            assert_equal_string (String.sub s i len)
              (to_string (of_substr s i len)));
      test_property "index_by matches string scan" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let p c = c > 'a' in
          let expected =
            let rec go i =
              if i >= String.length s then None
              else if p s.[i] then Some i
              else go (i + 1)
            in
            go 0
          in
          assert_equal
            ~show:(fun o ->
              match o with None -> "None" | Some i -> string_of_int i)
            expected (index_by p text));
      test_property "rindex_by matches string scan" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let p c = c > 'a' in
          let expected =
            let rec go i =
              if i < 0 then None else if p s.[i] then Some i else go (i - 1)
            in
            go (String.length s - 1)
          in
          assert_equal
            ~show:(fun o ->
              match o with None -> "None" | Some i -> string_of_int i)
            expected (rindex_by p text));
      test_property "split_once_by matches index_by + split_at"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let p c = c = ',' in
          let l, r = split_once_by p text in
          match String.index_opt s ',' with
          | None -> (
              let check_l = assert_equal_string s (to_string l) in
              match check_l with
              | Fail _ -> check_l
              | Pass -> assert_bool "right should be empty" (is_empty r))
          | Some i -> (
              let check_l =
                assert_equal_string (String.sub s 0 i) (to_string l)
              in
              match check_l with
              | Fail _ -> check_l
              | Pass ->
                  assert_equal_string
                    (String.sub s i (String.length s - i))
                    (to_string r)));
      test_property "rsplit_once_by matches rindex_by + split_at"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let p c = c = ',' in
          let l, r = rsplit_once_by p text in
          let rindex =
            let rec go i =
              if i < 0 then None else if s.[i] = ',' then Some i else go (i - 1)
            in
            go (String.length s - 1)
          in
          match rindex with
          | None -> (
              let check_r = assert_equal_string s (to_string r) in
              match check_r with
              | Fail _ -> check_r
              | Pass -> assert_bool "left should be empty" (is_empty l))
          | Some i -> (
              let check_l =
                assert_equal_string (String.sub s 0 i) (to_string l)
              in
              match check_l with
              | Fail _ -> check_l
              | Pass ->
                  assert_equal_string
                    (String.sub s i (String.length s - i))
                    (to_string r)));
      test_property "trim matches String.trim" text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          assert_equal_string (String.trim s) (to_string (trim text)));
      test_property "insert_at splits and joins"
        (Generator.bind text_and_string_generator (fun (text, s) ->
             Generator.bind
               (Generator.int_inclusive 0 (String.length s))
               (fun i ->
                 Generator.map
                   (Generator.string ~length:(Generator.int_inclusive 0 8) ())
                   (fun ins -> (text, s, i, ins)))))
        ~show:(fun (_text, s, i, ins) -> Printf.sprintf "(%S, %d, %S)" s i ins)
        ~f:(fun (text, s, i, ins) ->
          let expected =
            String.sub s 0 i ^ ins ^ String.sub s i (String.length s - i)
          in
          assert_equal_string expected
            (to_string (insert_at text i (of_string ins))));
      test_property "str_index matches naive search"
        (Generator.pair text_and_string_generator
           (Generator.string ~length:(Generator.int_inclusive 0 4) ()))
        ~show:
          (show_pair
             (show_pair debug (Printf.sprintf "%S"))
             (Printf.sprintf "%S"))
        ~f:(fun ((text, s), pat) ->
          let expected =
            let m = String.length pat in
            if m = 0 then Some 0
            else
              let n = String.length s in
              let rec go i =
                if i + m > n then None
                else if String.sub s i m = pat then Some i
                else go (i + 1)
              in
              go 0
          in
          assert_equal
            ~show:(fun o ->
              match o with None -> "None" | Some i -> string_of_int i)
            expected (str_index text pat));
      test_property "split_on matches String.split_on_char for single char"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let expected = String.split_on_char ',' s in
          let actual = List.map to_string (split_on text ",") in
          assert_equal ~show:show_string_list expected actual);
      test_property "split_on roundtrips with join"
        (Generator.pair text_and_string_generator
           (Generator.one_of [| Generator.return "::"; Generator.return "ab" |]))
        ~show:
          (show_pair
             (show_pair debug (Printf.sprintf "%S"))
             (Printf.sprintf "%S"))
        ~f:(fun ((text, s), sep) ->
          let parts = split_on text sep in
          let joined = String.concat sep (List.map to_string parts) in
          assert_equal_string s joined);
      test_property "concat matches String.concat"
        (Generator.pair
           (Generator.string ~length:(Generator.int_inclusive 0 3) ())
           (Generator.list
              ~length:(Generator.int_inclusive 0 6)
              text_and_string_generator))
        ~show:
          (show_pair (Printf.sprintf "%S") (fun xs ->
               show_string_list (List.map (fun (_, s) -> s) xs)))
        ~f:(fun (sep, parts) ->
          let expected = String.concat sep (List.map snd parts) in
          let actual =
            concat (of_string sep) (List.map fst parts) |> to_string
          in
          assert_equal_string expected actual);
      test_property "output_to_buffer matches to_string"
        text_and_string_generator
        ~show:(show_pair debug (Printf.sprintf "%S"))
        ~f:(fun (text, s) ->
          let buf = Buffer.create 16 in
          output_to_buffer buf text;
          assert_equal_string s (Buffer.contents buf));
    ]
