(* Calendar date type. Replacement for Data.Time.Calendar.Day from
   Haskell's [time] package. We only need YYYY-MM-DD parsing/formatting,
   ordering, and a "today" helper. *)

type t = { year : int; month : int; (* 1..12 *) day : int (* 1..31 *) }

let make ~year ~month ~day = { year; month; day }
let year d = d.year
let month d = d.month
let day d = d.day

let compare a b =
  let c = Int.compare a.year b.year in
  if c <> 0 then c
  else
    let c = Int.compare a.month b.month in
    if c <> 0 then c else Int.compare a.day b.day

let equal a b = compare a b = 0

(* Render in YYYY-MM-DD form. *)
let to_string d = Printf.sprintf "%04d-%02d-%02d" d.year d.month d.day

(* Parse "YYYY-MM-DD". Returns None on any malformed input. *)
let of_string s =
  if String.length s <> 10 then None
  else if s.[4] <> '-' || s.[7] <> '-' then None
  else
    try
      let y = int_of_string (String.sub s 0 4) in
      let m = int_of_string (String.sub s 5 2) in
      let d = int_of_string (String.sub s 8 2) in
      if m < 1 || m > 12 || d < 1 || d > 31 then None
      else Some { year = y; month = m; day = d }
    with Failure _ -> None

(* RFC3339 timestamp at midnight UTC, used by the Atom feed renderer. *)
let to_rfc3339_midnight d =
  Printf.sprintf "%04d-%02d-%02dT00:00:00Z" d.year d.month d.day

(* Today, derived from the local clock. *)
let today () =
  let tm = Unix.gmtime (Unix.time ()) in
  {
    year = tm.Unix.tm_year + 1900;
    month = tm.Unix.tm_mon + 1;
    day = tm.Unix.tm_mday;
  }
