(* A thin wrapper around the [Unix] module. *)

type fd = Unix.file_descr

(* Open a TCP listener on the given port, bound to INADDR_ANY. *)
let listen_on (port : int) : fd =
  let fd = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt fd Unix.SO_REUSEADDR true;
  Unix.bind fd (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen fd 16;
  fd

(* Accept one connection. Returns the client socket. *)
let accept_conn (server_fd : fd) : fd =
  let client_fd, _addr = Unix.accept server_fd in
  client_fd

(* Read up to [max_bytes] bytes from [fd] in a single read. Returns the
   string actually received, which may be empty if the client hangs up. *)
let recv_all (fd : fd) (max_bytes : int) : string =
  let buf = Bytes.create max_bytes in
  let n = Unix.read fd buf 0 max_bytes in
  if n <= 0 then "" else Bytes.sub_string buf 0 n

(* Write the whole string to [fd], retrying until fully sent. *)
let send_all (fd : fd) (data : string) : unit =
  let len = String.length data in
  let rec loop off =
    if off >= len then ()
    else
      let n = Unix.write_substring fd data off (len - off) in
      if n <= 0 then () else loop (off + n)
  in
  loop 0

let close_socket (fd : fd) : unit =
  try Unix.close fd with Unix.Unix_error _ -> ()
