module Generator : sig
  type 'a t

  val generate : Random.State.t -> 'a t -> 'a
  val return : 'a -> 'a t
  val map : 'a t -> ('a -> 'b) -> 'b t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
  val bool : bool t
  val char : char t
  val int_inclusive : int -> int -> int t
  val one_of : 'a t array -> 'a t
  val list : ?length:int t -> 'a t -> 'a list t
  val string : ?length:int t -> unit -> string t
  val pair : 'a t -> 'b t -> ('a * 'b) t
  val triple : 'a t -> 'b t -> 'c t -> ('a * 'b * 'c) t
end

val check :
  ?trials:int ->
  ?seed:int ->
  'a Generator.t ->
  show:('a -> string) ->
  f:('a -> Test_framework.check) ->
  Test_framework.check
