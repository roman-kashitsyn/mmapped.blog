type t

val empty : t
val is_empty : t -> bool
val length : t -> int
val of_string : string -> t
val of_substr : string -> int -> int -> t
val of_char : char -> t
val to_string : t -> string
val to_substr : t -> string * int * int
val to_seq : t -> char Seq.t
val equal : t -> t -> bool
val equal_string : t -> string -> bool
val compare : t -> t -> int
val hash : t -> int
val get : t -> int -> char
val append : t -> t -> t
val concat : t -> t list -> t
val map : (char -> char) -> t -> t
val mapi : (int -> char -> char) -> t -> t
val iter : (char -> unit) -> t -> unit
val iteri : (int -> char -> unit) -> t -> unit
val exists : (char -> bool) -> t -> bool
val for_all : (char -> bool) -> t -> bool
val index_by : (char -> bool) -> t -> int option
val rindex_by : (char -> bool) -> t -> int option
val split_once_by : (char -> bool) -> t -> t * t
val rsplit_once_by : (char -> bool) -> t -> t * t
val trim_by : (char -> bool) -> t -> t
val trim : t -> t
val fold_left : ('acc -> char -> 'acc) -> 'acc -> t -> 'acc
val fold_right : (char -> 'acc -> 'acc) -> t -> 'acc -> 'acc
val output : out_channel -> t -> unit
val output_to_buffer : Buffer.t -> t -> unit
val sub : t -> int -> int -> t
val split_at : t -> int -> t * t
val insert_at : t -> int -> t -> t
val str_index : t -> string -> int option
val split_on : t -> string -> t list
val debug : t -> string

module Set : Set.S with type elt = t
module Map : Map.S with type key = t
module Table : Hashtbl.S with type key = t
