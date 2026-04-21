(* Rope-based text data type implementation. *)

let fibs =
  let buf = Dynarray.create () in
  let rec go a b =
    Dynarray.add_last buf a;
    if b < max_int - a then go b (a + b)
  in
  go 0 1;
  Dynarray.to_array buf

type t =
  | Empty
  | Char of char
  | Str of string
  | Sub of string * int * int
  | Fork of int * int * t * t

let length x =
  match x with
  | Empty -> 0
  | Char _ -> 1
  | Str s -> String.length s
  | Sub (_, _, len) -> len
  | Fork (_, n, _, _) -> n

let depth x = match x with Fork (d, _, _, _) -> d | _ -> 0

let fork l r =
  match (l, r) with
  | Empty, _ -> r
  | _, Empty -> l
  | _, _ -> Fork (1 + max (depth l) (depth r), length l + length r, l, r)

let empty = Empty
let of_char c = Char c
let of_string s = if String.length s == 0 then Empty else Str s
let of_substr s pos len = if len == 0 then Empty else Sub (s, pos, len)
let is_empty = function Empty -> true | _ -> false

let collect_leaves t =
  let buf = Dynarray.create () in
  let rec go x buf =
    match x with
    | Empty -> ()
    | Char _ -> Dynarray.add_last buf x
    | Str _ -> Dynarray.add_last buf x
    | Sub (_, _, _) -> Dynarray.add_last buf x
    | Fork (_, _, l, r) ->
        go l buf;
        go r buf
  in
  go t buf;
  buf

let rec merge leaves s e =
  match e - s with
  | 0 -> Empty
  | 1 -> Dynarray.get leaves s
  | 2 -> fork (Dynarray.get leaves s) (Dynarray.get leaves (s + 1))
  | n ->
      let m = s + (n / 2) in
      fork (merge leaves s m) (merge leaves m e)

let is_balanced = function
  | Fork (d, n, _, _) -> d < Array.length fibs - 2 && fibs.(d + 2) <= n
  | _ -> true

let rebalance t =
  if is_balanced t then t
  else
    let leaves = collect_leaves t in
    merge leaves 0 (Dynarray.length leaves)

let rec output o t =
  match t with
  | Empty -> ()
  | Char c -> output_char o c
  | Str s -> output_string o s
  | Sub (s, pos, len) -> output_substring o s pos len
  | Fork (_, _, l, r) ->
      output o l;
      output o r

let rec output_to_buffer b t =
  match t with
  | Empty -> ()
  | Char c -> Buffer.add_char b c
  | Str s -> Buffer.add_string b s
  | Sub (s, pos, len) -> Buffer.add_substring b s pos len
  | Fork (_, _, l, r) ->
      output_to_buffer b l;
      output_to_buffer b r

let to_string = function
  | Empty -> ""
  | Char c -> String.make 1 c
  | Str s -> s
  | Sub (s, pos, len) -> String.sub s pos len
  | x ->
      let buf = Bytes.create (length x) in
      let rec go x buf i =
        match x with
        | Empty -> ()
        | Char c -> Bytes.unsafe_set buf i c
        | Str s -> Bytes.blit_string s 0 buf i (String.length s)
        | Sub (s, pos, len) -> Bytes.blit_string s pos buf i len
        | Fork (_, _, l, r) -> begin
            go l buf i;
            go r buf (i + length l)
          end
      in
      go x buf 0;
      Bytes.unsafe_to_string buf

let to_substr = function
  | Sub (s, pos, len) -> (s, pos, len)
  | t ->
      let s = to_string t in
      (s, 0, String.length s)

let to_seq t =
  let rec go stack () =
    match stack with
    | [] -> Seq.Nil
    | Empty :: rest -> go rest ()
    | Char c :: rest -> Seq.Cons (c, go rest)
    | Str s :: rest -> go_str s 0 (String.length s) rest ()
    | Sub (s, pos, len) :: rest -> go_str s pos (pos + len) rest ()
    | Fork (_, _, l, r) :: rest -> go (l :: r :: rest) ()
  and go_str s i n rest () =
    if i >= n then go rest ()
    else Seq.Cons (String.unsafe_get s i, go_str s (i + 1) n rest)
  in
  go [ t ]

let rec eq_range s1 o1 s2 o2 n =
  if n = 0 then true
  else if String.unsafe_get s1 o1 <> String.unsafe_get s2 o2 then false
  else eq_range s1 (o1 + 1) s2 (o2 + 1) (n - 1)

let equal l r =
  if length l <> length r then false
  else
    match (l, r) with
    | Empty, Empty -> true
    | Char c1, Char c2 -> c1 == c2
    | Str s1, Str s2 -> String.equal s1 s2
    | Char c, Str s | Str s, Char c -> s.[0] == c
    | Sub (s, pos, _), Char c | Char c, Sub (s, pos, _) -> s.[pos] == c
    | Sub (s1, p1, l1), Sub (s2, p2, _) -> eq_range s1 p1 s2 p2 l1
    | Str s1, Sub (s2, p2, l2) -> eq_range s1 0 s2 p2 l2
    | Sub (s1, p1, l1), Str s2 -> eq_range s1 p1 s2 0 l1
    | _, _ -> String.equal (to_string l) (to_string r)

let equal_string t s =
  if length t <> String.length s then false
  else
    match t with
    | Empty -> true
    | Char c -> s.[0] == c
    | Str st -> String.equal st s
    | Sub (st, pos, len) -> eq_range st pos s 0 len
    | _ -> String.equal (to_string t) s

let compare_ranges s1 p1 l1 s2 p2 l2 =
  let n = min l1 l2 in
  let rec go i =
    if i = n then Int.compare l1 l2
    else
      let c =
        Char.compare
          (String.unsafe_get s1 (p1 + i))
          (String.unsafe_get s2 (p2 + i))
      in
      if c = 0 then go (i + 1) else c
  in
  go 0

let compare l r =
  match (l, r) with
  | Empty, Empty -> 0
  | Empty, _ -> -1
  | _, Empty -> 1
  | Char c1, Char c2 -> Char.compare c1 c2
  | Char c, Str s ->
      let d = Char.compare c (String.unsafe_get s 0) in
      if d = 0 then Int.compare 1 (String.length s) else d
  | Str s, Char c ->
      let d = Char.compare (String.unsafe_get s 0) c in
      if d = 0 then Int.compare (String.length s) 1 else d
  | Char c, Sub (s, pos, len) ->
      let d = Char.compare c (String.unsafe_get s pos) in
      if d = 0 then Int.compare 1 len else d
  | Sub (s, pos, len), Char c ->
      let d = Char.compare (String.unsafe_get s pos) c in
      if d = 0 then Int.compare len 1 else d
  | Str s1, Str s2 -> String.compare s1 s2
  | Sub (s1, p1, l1), Sub (s2, p2, l2) -> compare_ranges s1 p1 l1 s2 p2 l2
  | Str s1, Sub (s2, p2, l2) -> compare_ranges s1 0 (String.length s1) s2 p2 l2
  | Sub (s1, p1, l1), Str s2 -> compare_ranges s1 p1 l1 s2 0 (String.length s2)
  | _, _ -> String.compare (to_string l) (to_string r)

let hash t =
  let prime = 16_777_619 in
  let mix h c = h lxor Char.code c * prime land max_int in
  let rec go h = function
    | Empty -> h
    | Char c -> mix h c
    | Str s -> go_string h s 0 (String.length s)
    | Sub (s, pos, len) -> go_string h s pos (pos + len)
    | Fork (_, _, l, r) -> go (go h l) r
  and go_string h s i n =
    if i = n then h else go_string (mix h (String.unsafe_get s i)) s (i + 1) n
  in
  go 2_166_136_261 t

module Set = Set.Make (struct
  type nonrec t = t

  let compare = compare
end)

module Map = Map.Make (struct
  type nonrec t = t

  let compare = compare
end)

module Table = Hashtbl.Make (struct
  type nonrec t = t

  let equal = equal
  let hash = hash
end)

let invalid_get_arg () =
  raise (Invalid_argument "Text.get: index out of bounds")

let rec get x i =
  match x with
  | Empty -> invalid_get_arg ()
  | Char c -> if i == 0 then c else invalid_get_arg ()
  | Str s -> String.get s i
  | Sub (s, pos, len) -> if i >= len then invalid_get_arg () else s.[pos + i]
  | Fork (_, _, l, r) ->
      let m = length l in
      if i < m then get l i else get r (i - m)

let map_substr f s pos len =
  let buf = Bytes.create len in
  for i = 0 to len - 1 do
    Bytes.unsafe_set buf i (f (String.unsafe_get s (pos + i)))
  done;
  Bytes.unsafe_to_string buf

let rec map f = function
  | Empty -> Empty
  | Char c -> Char (f c)
  | Str s -> Str (String.map f s)
  | Sub (s, pos, len) -> Str (map_substr f s pos len)
  | Fork (d, n, l, r) -> Fork (d, n, map f l, map f r)

let rec iter f = function
  | Empty -> ()
  | Char c -> f c
  | Str s -> String.iter f s
  | Sub (s, pos, len) ->
      for i = pos to pos + len - 1 do
        f s.[i]
      done
  | Fork (_, _, l, r) ->
      iter f l;
      iter f r

let iteri f t =
  let rec go offset f t =
    match t with
    | Empty -> ()
    | Char c -> f offset c
    | Str s ->
        for i = 0 to String.length s - 1 do
          f (offset + i) (String.unsafe_get s i)
        done
    | Sub (s, pos, len) ->
        for i = 0 to len - 1 do
          f (offset + i) (String.unsafe_get s (pos + i))
        done
    | Fork (_, _, l, r) ->
        go offset f l;
        go (offset + length l) f r
  in
  go 0 f t

let imap_substr f offset s pos len =
  let buf = Bytes.create len in
  for i = 0 to len - 1 do
    Bytes.unsafe_set buf i (f (offset + i) s.[pos + i])
  done;
  Bytes.unsafe_to_string buf

let mapi f t =
  let rec go offset f t =
    match t with
    | Empty -> Empty
    | Char c -> Char (f offset c)
    | Str s -> Str (String.mapi (fun i c -> f (offset + i) c) s)
    | Sub (s, pos, len) -> Str (imap_substr f offset s pos len)
    | Fork (d, n, l, r) -> Fork (d, n, go offset f l, go (offset + length l) f r)
  in
  go 0 f t

let rec substr_exists p s pos n =
  if pos == n then false
  else if p s.[pos] then true
  else substr_exists p s (pos + 1) n

let rec exists p = function
  | Empty -> false
  | Char c -> p c
  | Str s -> String.exists p s
  | Sub (s, pos, len) -> substr_exists p s pos (pos + len)
  | Fork (_, _, l, r) -> exists p l || exists p r

let rec substr_forall p s pos n =
  if pos == n then true
  else if p s.[pos] then substr_forall p s (pos + 1) n
  else false

let rec for_all p = function
  | Empty -> true
  | Char c -> p c
  | Str s -> String.for_all p s
  | Sub (s, pos, len) -> substr_forall p s pos (pos + len)
  | Fork (_, _, l, r) -> for_all p l && for_all p r

let rec str_index_by p s i n =
  if i == n then None
  else if p (String.unsafe_get s i) then Some i
  else str_index_by p s (i + 1) n

let rec str_rindex_by p s i start =
  if i < start then None
  else if p (String.unsafe_get s i) then Some i
  else str_rindex_by p s (i - 1) start

let index_by p t =
  let rec go offset p t =
    match t with
    | Empty -> None
    | Char c -> if p c then Some offset else None
    | Str s ->
        Option.map (fun i -> offset + i) (str_index_by p s 0 (String.length s))
    | Sub (s, pos, len) ->
        Option.map
          (fun i -> offset + i - pos)
          (str_index_by p s pos (pos + len))
    | Fork (_, _, l, r) -> (
        match go offset p l with
        | Some _ as result -> result
        | None -> go (offset + length l) p r)
  in
  go 0 p t

let rindex_by p t =
  let rec go offset p t =
    match t with
    | Empty -> None
    | Char c -> if p c then Some offset else None
    | Str s ->
        Option.map
          (fun i -> offset + i)
          (str_rindex_by p s (String.length s - 1) 0)
    | Sub (s, pos, len) ->
        Option.map
          (fun i -> offset + i - pos)
          (str_rindex_by p s (pos + len - 1) pos)
    | Fork (_, _, l, r) -> (
        match go (offset + length l) p r with
        | Some _ as result -> result
        | None -> go offset p l)
  in
  go 0 p t

let rec fold_left f acc x =
  match x with
  | Empty -> acc
  | Char c -> f acc c
  | Str s -> String.fold_left f acc s
  | Sub (s, pos, len) ->
      let result = ref acc in
      for i = pos to pos + len - 1 do
        result := f !result s.[i]
      done;
      !result
  | Fork (_, _, l, r) -> fold_left f (fold_left f acc l) r

let rec fold_right f x acc =
  match x with
  | Empty -> acc
  | Char c -> f c acc
  | Str s -> String.fold_right f s acc
  | Sub (s, pos, len) ->
      let result = ref acc in
      for i = pos + len - 1 downto pos do
        result := f s.[i] !result
      done;
      !result
  | Fork (_, _, l, r) -> fold_right f l (fold_right f r acc)

let append l r = fork l r |> rebalance

let concat sep = function
  | [] -> Empty
  | xs ->
      let buf = Dynarray.create () in
      let rec add = function
        | Empty -> ()
        | (Char _ | Str _ | Sub _) as leaf -> Dynarray.add_last buf leaf
        | Fork (_, _, l, r) ->
            add l;
            add r
      in
      let rec go = function
        | [] -> ()
        | [ x ] -> add x
        | x :: xs ->
            add x;
            add sep;
            go xs
      in
      go xs;
      merge buf 0 (Dynarray.length buf)

let invalid_sub_arg () = raise (Invalid_argument "Text.sub: invalid substring")

let sub t i n =
  if i < 0 || n < 0 || i + n > length t then invalid_sub_arg ();
  let rec go t i n =
    if n == 0 then Empty
    else
      match t with
      | Empty -> invalid_sub_arg ()
      | Char _ -> if i == 0 && n == 1 then t else invalid_sub_arg ()
      | Str s ->
          let s_len = String.length s in
          if i == 0 && n == s_len then t
          else if i + n > s_len then invalid_sub_arg ()
          else of_substr s i n
      | Sub (s, pos, len) ->
          if i + n > len then invalid_sub_arg () else of_substr s (pos + i) n
      | Fork (_, _, l, r) ->
          let nl = length l in
          let left = if i < nl then go l i (min n (nl - i)) else Empty in
          let right =
            if i >= nl then go r (i - nl) n
            else if i + n > nl then go r 0 (i + n - nl)
            else Empty
          in
          fork left right |> rebalance
  in
  go t i n

let invalid_split_at_arg () =
  raise (Invalid_argument "Text.split_at: invalid split index")

let rec split_at t i =
  match t with
  | Empty -> if i == 0 then (Empty, Empty) else invalid_split_at_arg ()
  | Char _ ->
      begin match i with
      | 0 -> (Empty, t)
      | 1 -> (t, Empty)
      | _ -> invalid_split_at_arg ()
      end
  | Str s ->
      let n = String.length s in
      if i > n then invalid_split_at_arg ()
      else (of_substr s 0 i, of_substr s i (n - i))
  | Sub (s, pos, len) ->
      if i > len then invalid_split_at_arg ()
      else (of_substr s pos i, of_substr s (pos + i) (len - i))
  | Fork (_, n, l, r) ->
      if i > n then invalid_split_at_arg ()
      else
        let nl = length l in
        if i < nl then
          let a, b = split_at l i in
          (a, fork b r |> rebalance)
        else
          let b, c = split_at r (i - nl) in
          (fork l b |> rebalance, c)

let debug t =
  let buf = Buffer.create 64 in
  let rec go indent x =
    Buffer.add_string buf indent;
    match x with
    | Empty -> Buffer.add_string buf "Empty\n"
    | Char c -> Printf.bprintf buf "Char %C\n" c
    | Str s -> Printf.bprintf buf "Str %S\n" s
    | Sub (s, pos, len) -> Printf.bprintf buf "Sub %S\n" (String.sub s pos len)
    | Fork (d, n, l, r) ->
        Printf.bprintf buf "Fork (depth=%d, len=%d)\n" d n;
        let indent' = indent ^ "  " in
        go indent' l;
        go indent' r
  in
  go "" t;
  Buffer.contents buf

let split_once_by p t =
  match index_by p t with Some i -> split_at t i | None -> (t, Empty)

let rsplit_once_by p t =
  match rindex_by p t with Some i -> split_at t i | None -> (Empty, t)

let trim_by p t =
  let suffix =
    match index_by p t with None -> t | Some i -> snd (split_at t i)
  in
  match rindex_by p suffix with
  | None -> suffix
  | Some i -> fst (split_at suffix (i + 1))

let not_whitespace = function
  | ' ' | '\r' | '\t' | '\n' | '\012' -> false
  | _ -> true

let trim = trim_by not_whitespace

let insert_at dst i t =
  let l, r = split_at dst i in
  fork (fork l t) r |> rebalance

let kmp_table pat =
  let m = String.length pat in
  let t = Array.make m 0 in
  if m > 1 then begin
    t.(0) <- -1;
    let pos = ref 2 in
    let cnd = ref 0 in
    while !pos < m do
      if pat.[!pos - 1] = pat.[!cnd] then begin
        t.(!pos) <- !cnd + 1;
        incr pos;
        incr cnd
      end
      else if !cnd > 0 then cnd := t.(!cnd)
      else begin
        t.(!pos) <- 0;
        incr pos
      end
    done
  end;
  t

let str_index t pat =
  let m = String.length pat in
  if m = 0 then Some 0
  else
    let table = kmp_table pat in
    let step j c =
      let j = ref j in
      while !j > 0 && pat.[!j] <> c do
        j := table.(!j)
      done;
      if pat.[!j] = c then !j + 1 else 0
    in
    let rec go_str s pos len i j =
      if j = m then (Some (i - m), j)
      else if pos >= len then (None, j)
      else
        let j = step j (String.unsafe_get s pos) in
        go_str s (pos + 1) len (i + 1) j
    and go i j t =
      match t with
      | Empty -> (None, j)
      | Char c ->
          let j = step j c in
          if j = m then (Some (i + 1 - m), j) else (None, j)
      | Str s -> go_str s 0 (String.length s) i j
      | Sub (s, pos, len) -> go_str s pos (pos + len) i j
      | Fork (_, _, l, r) -> (
          match go i j l with
          | (Some _, _) as found -> found
          | None, j -> go (i + length l) j r)
    in
    fst (go 0 0 t)

let split_on t sep =
  let m = String.length sep in
  if m = 0 then invalid_arg "Text.split_on: empty separator"
  else
    let rec loop acc t =
      match str_index t sep with
      | None -> List.rev (t :: acc)
      | Some i ->
          let l, r = split_at t i in
          let _, r = split_at r m in
          loop (l :: acc) r
    in
    loop [] t
