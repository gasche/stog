(*********************************************************************************)
(*                Stog                                                           *)
(*                                                                               *)
(*    Copyright (C) 2012-2014 Maxence Guesdon. All rights reserved.              *)
(*                                                                               *)
(*    This program is free software; you can redistribute it and/or modify       *)
(*    it under the terms of the GNU General Public License as                    *)
(*    published by the Free Software Foundation, version 3 of the License.       *)
(*                                                                               *)
(*    This program is distributed in the hope that it will be useful,            *)
(*    but WITHOUT ANY WARRANTY; without even the implied warranty of             *)
(*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the               *)
(*    GNU Library General Public License for more details.                       *)
(*                                                                               *)
(*    You should have received a copy of the GNU General Public                  *)
(*    License along with this program; if not, write to the Free Software        *)
(*    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA                   *)
(*    02111-1307  USA                                                            *)
(*                                                                               *)
(*    As a special exception, you have permission to link this program           *)
(*    with the OCaml compiler and distribute executables, as long as you         *)
(*    follow the requirements of the GNU GPL in regard to all of the             *)
(*    software in the executable aside from the OCaml compiler.                  *)
(*                                                                               *)
(*    Contact: Maxence.Guesdon@inria.fr                                          *)
(*                                                                               *)
(*********************************************************************************)

(** *)


module S = Cohttp_lwt_unix.Server
let (>>=) = Lwt.bind

let handle_preview sock req body path =
  S.respond_string ~status:`OK ~body: ("preview of "^(String.concat "/" path)) ()

(*  Cohttp.Connection.t ->
      Cohttp.Request.t ->
      Cohttp_lwt_body.t ->
      (Cohttp.Response.t * Cohttp_lwt_body.t) Lwt.t;
*)
let handler sock req body =
  let uri = Cohttp.Request.uri req in
  let path = Stog_misc.split_string (Uri.path uri) ['/'] in
  match path with
    "preview" :: path -> handle_preview sock req body path
  | _ ->
      let body = Printf.sprintf "<html><header><title>Stog-server</title></header>
    <body>Hello world !</body></html>"
      in
      S.respond_string ~status:`OK ~body ()

let start_server dir port host =
  Lwt_io.write Lwt_io.stdout
    (Printf.sprintf "Listening for HTTP request on: %s:%d\n" host port)
  >>= fun _ ->
  let conn_closed id () =
    ignore(Lwt_io.write Lwt_io.stdout
      (Printf.sprintf "connection %s closed\n%!" (Cohttp.Connection.to_string id)))
  in
  let config = { S.callback = handler; conn_closed } in
  S.create ~address:host ~port config

let port = ref 8080
let host = ref "0.0.0.0"
let root_dir = ref "."

let options = [
  "-p", Arg.Set_int port, "<p> set port to listen on" ;
  "-h", Arg.Set_string host,"<host> set hostname to listen on" ;
  "-d", Arg.Set_string root_dir, "<dir> set stog root directory to watch" ;
  ]

let _ =
  try
    Arg.parse options (fun _ -> ())
      (Printf.sprintf "Usage: %s [options]\nwhere options are:" Sys.argv.(0));
    Lwt_unix.run (start_server !root_dir !port !host)
  with
  e ->
      let msg =
        match e with
          Failure msg | Sys_error msg -> msg
        | _ -> Printexc.to_string e
      in
      prerr_endline msg;
      exit 1
