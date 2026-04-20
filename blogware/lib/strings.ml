let rec eq_from s p i j n =
  if j = n then true
  else if s.[i + j] <> p.[j] then false
  else eq_from s p i (j + 1) n

let is_infix_of pat s =
  let s_len = String.length s in
  let pat_len = String.length pat in
  if pat_len = 0 then true
  else
    let rec go i =
      if i + pat_len > s_len then false
      else if eq_from s pat i 0 pat_len then true
      else go (i + 1)
    in
    go 0

let has_prefix_at (src : string) (offset : int) (pat : string) : bool =
  let n = String.length pat in
  let len = String.length src in
  if offset + n > len then false else eq_from src pat offset 0 n

let split_on (s : string) (pat : string) : string list =
  let len = String.length s in
  let pat_len = String.length pat in
  if pat_len = 0 then [ s ]
  else begin
    let parts = ref [] in
    let start = ref 0 in
    let i = ref 0 in
    while !i + pat_len <= len do
      if has_prefix_at s !i pat then begin
        parts := String.sub s !start (!i - !start) :: !parts;
        i := !i + pat_len;
        start := !i
      end
      else incr i
    done;
    parts := String.sub s !start (len - !start) :: !parts;
    List.rev !parts
  end

let strip_prefix ~prefix (s : string) : string option =
  if String.starts_with ~prefix s then
    let n = String.length prefix in
    Some (String.sub s n (String.length s - n))
  else None
