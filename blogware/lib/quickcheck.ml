module Generator = struct
  type 'a t = Random.State.t -> 'a

  let generate state gen = gen state
  let return x _state = x
  let map gen f state = f (gen state)
  let bind gen f state = f (gen state) state
  let bool state = Random.State.bool state

  let int_inclusive lo hi state =
    if lo > hi then
      invalid_arg "Quickcheck.Generator.int_inclusive: empty range"
    else
      let range = hi - lo in
      if range < 0 then
        invalid_arg "Quickcheck.Generator.int_inclusive: range overflow"
      else lo + Random.State.int state (range + 1)

  let char state = Char.chr (Random.State.int state 256)

  let one_of gens state =
    if Array.length gens = 0 then
      invalid_arg "Quickcheck.Generator.one_of: empty generator array"
    else gens.(Random.State.int state (Array.length gens)) state

  let list ?(length = int_inclusive 0 16) gen state =
    let n = length state in
    List.init n (fun _ -> gen state)

  let string ?(length = int_inclusive 0 16) () state =
    let n = length state in
    String.init n (fun _ -> char state)

  let pair a b state = (a state, b state)
  let triple a b c state = (a state, b state, c state)
end

let check ?(trials = 100) ?seed gen ~show ~f =
  let seed = match seed with Some seed -> seed | None -> Random.bits () in
  let state = Random.State.make [| seed |] in
  let rec run trial =
    if trial > trials then Test_framework.Pass
    else
      let sample = Generator.generate state gen in
      match f sample with
      | Test_framework.Pass -> run (trial + 1)
      | Test_framework.Fail message ->
          Test_framework.Fail
            (Printf.sprintf "trial=%d seed=%d\ninput=%s\n%s" trial seed
               (show sample) message)
  in
  run 1
