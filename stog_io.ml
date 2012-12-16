(*********************************************************************************)
(*                Stog                                                           *)
(*                                                                               *)
(*    Copyright (C) 2012 Maxence Guesdon. All rights reserved.                   *)
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

open Stog_types;;

let first_that_exists =
  let rec iter = function
    [] -> None
  | (h,data) :: q ->
      if Sys.file_exists h then
        Some (h, data)
      else iter q
  in
  iter
;;

let date_of_string s =
  try Scanf.sscanf s "%d/%d/%d" (fun year month day -> {day; month; year})
  with
  | Scanf.Scan_failure _ -> failwith ("Invalid date: "^s)
  | End_of_file -> failwith (Printf.sprintf "Incomplete date \"%s\"" s)
;;

let topics_of_string s =
  List.map Stog_misc.strip_string
    (Stog_misc.split_string s [','; ';'])
;;
let keywords_of_string = topics_of_string ;;
let sets_of_string = topics_of_string ;;

let bool_of_string s =
  match String.lowercase s with
    "0" | "false" -> false
  | _ -> true
;;

let module_defs_of_xml =
  let f acc xml =
    match xml with
      Xtmpl.D _ -> acc
    | Xtmpl.E (tag, atts, subs) ->
        (tag, atts, subs) :: acc
  in
  List.fold_left f []
;;

let module_requires_of_string str =
  let l = Stog_misc.split_string str [',' ; ';'] in
  let l = List.map Stog_misc.strip_string l in
  let f acc = function
    "" -> acc
  | s -> Stog_types.Str_set.add s acc
  in
  List.fold_left f Stog_types.Str_set.empty l
;;

let read_module stog file =
  let modname = Filename.chop_extension (Filename.basename file) in
  let xml = Xtmpl.xml_of_file file in
  match xml with
    Xtmpl.D _ -> assert false
  | Xtmpl.E (tag, atts, subs) ->
      let mod_requires =
        match Xtmpl.get_arg atts ("","requires") with
            None -> Stog_types.Str_set.empty
        | Some s -> module_requires_of_string s
      in
      let mod_defs = module_defs_of_xml subs in
      let m = { mod_requires ; mod_defs } in
      let modules = Stog_types.Str_map.add modname m stog.stog_modules in
      { stog with stog_modules = modules }

let read_modules stog =
  let mod_dir = Stog_config.modules_dir stog.stog_dir in
  Stog_misc.safe_mkdir mod_dir;
  let files = Stog_find.find_list
    Stog_find.Stderr
    [mod_dir]
    [ Stog_find.Type Unix.S_REG ; Stog_find.Follow ;
      Stog_find.Regexp (Str.regexp ".*\\.stm$")
    ]
  in
  List.fold_left read_module stog files
;;

let used_mods_of_string set s =
  let l = Stog_misc.split_string s [';' ; ','] in
  List.fold_left
    (fun set s ->
     match Stog_misc.strip_string s with
       "" -> set
     | modname -> Stog_types.Str_set.add modname set
     )
     set
     l
;;

let extract_stog_info_from_elt stog elt =
  let stog = { stog with stog_title = elt.elt_title } in
  let rec iter (stog, defs) = function
    [] -> (stog, defs)
  | h:: q ->
      let (stog, opt) =
        match h with
        | (("stog", "site-description"), _, xmls) -> { stog with stog_desc = xmls }, None
        | (("stog", "site-url"), _, xmls) -> { stog with stog_base_url = Xtmpl.string_of_xmls xmls }, None
        | (("stog", "site-email)"), _, xmls) -> { stog with stog_email = Xtmpl.string_of_xmls xmls }, None
        | (("stog", "rss-length"), _,xmls) ->
            { stog with
              stog_rss_length = int_of_string (Xtmpl.string_of_xmls xmls) },
            None
        | (("stog", "use"), _, xmls) ->
            let s = Xtmpl.string_of_xmls xmls in
            let stog =  { stog with stog_used_mods = used_mods_of_string stog.stog_used_mods s } in
            (stog, None)
        | (("stog", name), args, body) ->
            let stog = { stog with stog_defs = (("",name), args, body) :: stog.stog_defs } in
            (stog, None)
        | _ ->
            (stog, Some h)
      in
      let defs = match opt with None -> defs | Some x -> h :: defs in
      iter (stog, defs) q
  in
  let (stog, defs) = iter (stog, []) elt.elt_defs in
  (stog, { elt with elt_defs = defs })
;;

let add_elt stog elt =
  let (stog, elt) =
    let is_main =
      try match List.find (fun (s,_,_) -> s = ("","main")) elt.elt_defs with
          (_,_,[Xtmpl.D s]) -> bool_of_string s
        | (_,_,xmls) ->
          prerr_endline (Printf.sprintf "elt %S: not main:\n%S" elt.elt_title (Xtmpl.string_of_xmls xmls));
          false
      with Not_found -> false
    in
    if is_main then
      begin
      match stog.stog_main_elt with
          Some id ->
            let elt2 = Stog_types.elt stog id in
            failwith
            (Printf.sprintf "%S: %S is already defined as main stog element"
             elt.elt_src elt2.elt_src)
        | None ->
            extract_stog_info_from_elt stog elt
      end
    else
      (stog, elt)
  in
  Stog_types.add_elt stog elt
;;



let fill_elt_from_atts =
  let rec iter elt = function
    [] -> elt
  | h :: q ->
      let elt =
        match h with
        | (("","with-contents"),_) -> elt
        | (("","title"), s) -> { elt with elt_title = s }
        | (("","keywords"), s) when false -> { elt with elt_keywords = keywords_of_string s }
        | (("","topics"), s) when false -> { elt with elt_topics = topics_of_string s }
        | (("","date"), s) -> { elt with elt_date = Some (date_of_string s) }
        | (("","published"), s) -> { elt with elt_published = bool_of_string s }
        | (("","sets"), s) -> { elt with elt_sets = sets_of_string s }
        | (("","language-dep"), s) -> { elt with elt_lang_dep = bool_of_string s }
        | (("","doctype"), s) -> { elt with elt_xml_doctype = Some s }
        | (("", "use"), s) -> { elt with elt_used_mods = used_mods_of_string elt.elt_used_mods s }
        | (att, v) -> { elt with elt_defs = (att, [], [Xtmpl.D v]) :: elt.elt_defs }
      in
      iter elt q
  in
  iter
;;

let fill_elt_from_nodes =
  let f elt xml =
    match xml with
      Xtmpl.D _ -> elt
    | Xtmpl.E (tag, atts, subs) ->
        let v = Xtmpl.string_of_xmls subs in
        match tag with
        | ("", "contents") -> { elt with elt_body = subs }
        | ("", "title") -> { elt with elt_title = v }
        | ("", "keywords") -> { elt with elt_keywords = keywords_of_string v }
        | ("", "topics") -> { elt with elt_topics = topics_of_string v }
        | ("", "date") -> { elt with elt_date = Some (date_of_string v) }
        | ("", "published") -> { elt with elt_published = bool_of_string v }
        | ("", "sets") -> { elt with elt_sets = sets_of_string v }
        | ("", "language-dep") -> { elt with elt_lang_dep = bool_of_string v }
        | ("", "doctype") -> { elt with elt_xml_doctype = Some v }
        | ("", "use") -> { elt with elt_used_mods = used_mods_of_string elt.elt_used_mods v }
        | s -> { elt with elt_defs = (s, atts, subs) :: elt.elt_defs }
  in
  List.fold_left f
;;

let elt_of_file stog file =
  let rel_file = Stog_misc.path_under ~parent: stog.stog_dir file in
  let hid =
    let s = try Filename.chop_extension rel_file with _ -> rel_file in
    let s = "/"^s in
    Stog_types.human_id_of_string s
  in
  Stog_msg.verbose ~level: 3 (Printf.sprintf "reading element file %S" file);
  let xml = Xtmpl.xml_of_file file in
  let (typ, atts, subs) =
    match xml with
      Xtmpl.D _ -> failwith (Printf.sprintf "File %S does not content an XML tree" file)
    | Xtmpl.E ((_,tag), atts, subs) -> (tag, atts, subs)
  in
  let elt = Stog_types.make_elt ~hid ~typ () in
  let elt = { elt with elt_src = rel_file } in
  let elt =
    match Xtmpl.get_arg atts ("","hid") with
      None -> elt
    | Some s -> { elt with elt_human_id = Stog_types.human_id_of_string s }
  in
  let elt = fill_elt_from_atts elt atts in
  match Xtmpl.get_arg atts ("", "with-contents") with
    Some s when bool_of_string s ->
      (* arguments are also passed in sub nodes, and contents is in
         subnode "contents" *)
      fill_elt_from_nodes elt subs
  | _ ->
      (* all arguments are passed in attributes, subnodes are the contents *)
      { elt with elt_body = subs }
;;

let read_files cfg stog dir =
  let stog_cfg_dir = Stog_config.config_dir dir in
  let on_error (e,s1,s2) =
    let msg =  Printf.sprintf "%s: %s %s" (Unix.error_message e) s1 s2 in
    Stog_msg.error ~info: "Stog_io.read_files" msg
  in
  let pred_ign =
    let make_pred re =
      let re = Str.regexp re in
      fun s -> Str.string_match re s 0
    in
    let preds = List.map make_pred cfg.Stog_config.ignored in
    fun entry ->
      entry <> stog_cfg_dir &&
      (let base = Filename.basename entry in base <> "." && base <> "..") &&
      (
       let k = (Unix.stat entry).Unix.st_kind in
       match k with
         Unix.S_REG | Unix.S_DIR -> not (List.exists (fun f -> f entry) preds)
       | _ -> false
      )
  in
  let pred_elt =
    let make_pred s_re =
      let re = Str.regexp s_re in
      fun s -> Str.string_match re s 0
    in
    let preds_ok = List.map make_pred cfg.Stog_config.elements in
    let preds_ko = List.map make_pred cfg.Stog_config.not_elements in
    fun entry ->
      let result =
        (List.exists (fun f -> f entry) preds_ok) &&
        not (List.exists (fun f -> f entry) preds_ko)
      in
      Stog_msg.verbose ~level:5
        (Printf.sprintf "File %S %s be processed."
           entry (if result then "will" else "will not"));
      result
  in
  let is_dir file = (Unix.stat file).Unix.st_kind = Unix.S_DIR in
  let rec iter stog dir =
    let entries =
      Stog_find.find_list
      (Stog_find.Custom on_error)
      [dir]
      [ Stog_find.Maxdepth 1 ;
        Stog_find.Predicate pred_ign ;
      ]
    in
    let entries = List.filter ((<>) dir) entries in
    let (dirs, files) = List.partition is_dir entries in
    (*prerr_endline ("dirs=" ^ String.concat ", " dirs);*)
    let (elt_files, files) = List.partition pred_elt files in
    let files = List.map Filename.basename files in
    let files = List.fold_right Str_set.add files Str_set.empty in
    let elts = List.map (elt_of_file stog) elt_files in
    let stog = List.fold_left add_elt stog elts in
    let (stog, dirs) = List.fold_left
      (fun (stog, map) dir ->
        let base = Filename.basename dir in
        let (stog, tree) = iter stog dir in
        (stog, Str_map.add base tree map)
      )
      (stog, Str_map.empty)
      dirs
    in
    let tree = { files ; dirs } in
    (stog, tree)
  in
  let (stog, tree) = iter stog dir in
  { stog with stog_files = tree }
;;

let read_stog dir =
  let len_dir_sep = String.length Filename.dir_sep in
  let rec remove_ending_sep s =
    let len = String.length s in
    if len <= 0 then failwith (Printf.sprintf "Invalid directory %S" dir);
    if len <= len_dir_sep then
      s
    else
      (
       if String.sub s (len - len_dir_sep) len_dir_sep = Filename.dir_sep then
         remove_ending_sep (String.sub s 0 (len - len_dir_sep))
       else
         s
      )
  in
  let dir = remove_ending_sep dir in
  let stog = Stog_types.create_stog dir in
  let cfg = Stog_config.read_config dir in
  let stog = read_files cfg stog dir in
  let stog = read_modules stog in
  stog
;;

