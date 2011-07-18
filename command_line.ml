(* ---------------------------------------------------------------------- *)
(* useful functions *)

let starts_with c s =
  if String.length s > 0 && String.get s 0 = c
  then Some (String.sub s 1 ((String.length s) - 1))
  else None

let ends_with c s =
  if String.length s > 0 && String.get s ((String.length s) - 1) = c
  then Some (String.sub s 0 ((String.length s) - 1))
  else None

let split_when fn l =
  let rec loop acc = function
  | []    -> raise Not_found
  | x::xs ->
      (match fn x with
	Some x -> List.rev acc, x, xs
      |	None -> loop (x :: acc) xs) in
  loop [] l

(* ---------------------------------------------------------------------- *)
(* make a semantic patch from a string *)

let find_metavariables tokens =
  let rec loop env = function
      [] -> (env,[])
    | x :: xs ->
	(* single upper case letter is a metavariable *)
	let (x,xs,env) =
	  if String.length x = 1 && String.uppercase x = x
	  then
	    begin
	      try let _ = Some(List.assoc x env) in (x,xs,env)
	      with Not_found ->
		let env = (x,(Printf.sprintf "metavariable %s;\n" x)) :: env in
		(x,xs,env)
	    end
	  else
	    begin
	      match Str.split (Str.regexp ":") x with
		[before;after] ->
		  let (ty,endty,afterty) =
		    split_when (ends_with ':') (after::xs) in
		  (try
		    let _ = List.assoc x env in failwith (x^"already declared")
		  with Not_found ->
		    let env =
		      (before,
		       (Printf.sprintf "%s %s;\n"
			  (String.concat " " (ty@[endty]))
			  before)) ::
			env in
		    (before,afterty,env))
	      | _ -> (x,xs,env)
	    end in
	let (env,sp) = loop env xs in
	(env,x::sp) in
  loop [] tokens

let find_when_dots tokens =
  let rec loop = function
      [] -> []
    | "when" :: "!=" :: e :: rest ->
	"when" :: "!=" :: e :: "\n" :: (loop rest)
    | "when" :: "==" :: e :: rest ->
	"when" :: "==" :: e :: "\n" :: (loop rest)
    | "when" :: e :: rest ->
	"when" :: e :: "\n" :: (loop rest)
    | "..." :: "when" :: rest -> "\n" :: "..." :: (loop ("when" :: rest))
    | "..." :: rest -> "\n" :: "..." :: "\n" :: (loop rest)
    | x::xs -> x::(loop xs) in
  loop tokens

let add_stars tokens =
  let rec loop = function
      [] -> []
    | "when" :: rest -> "when" :: skip rest
    | "..." :: rest -> "..." :: skip rest
    | "\n" :: rest -> "\n" :: loop rest
    | x :: xs -> ("* " ^ x) :: (skip xs)
  and skip = function
      [] -> []
    | "\n" :: rest -> "\n" :: loop rest
    | x :: xs -> x :: skip xs in
  loop tokens

let rec add_spaces = function
    [] -> []
  | x :: "\n" :: rest -> x :: "\n" :: (add_spaces rest)
  | "\n" :: rest -> "\n" :: (add_spaces rest)
  | x :: rest -> x :: " " :: (add_spaces rest)

let reparse tokens =
  let (env,code) = find_metavariables tokens in
  let env = String.concat " " (List.map snd env) in
  let code = find_when_dots code in
  let code = add_stars code in
  let code = add_spaces code in
  let code = String.concat "" code in
  let res = "@@\n"^env^"\n@@\n"^code in
  Printf.printf "semantic patch:\n%s\n" res;
  let out = Common.new_temp_file "sp" ".cocci" in
  let o = open_out out in
  Printf.fprintf o "%s\n" res;
  close_out o;
  out

(* ---------------------------------------------------------------------- *)
(* entry point *)

let command_line args =
  let info =
    try Some (Common.split_when (function x -> x = "-sp") args)
    with Not_found -> None in
  match info with
    None -> args
  | Some(pre_args,sp,post_args) ->
      (match post_args with
	first::post_args ->
	  pre_args @ "-sp_file" ::
		     (reparse (Str.split (Str.regexp " ") first)) ::
		     post_args
      | [] -> failwith "-sp needs an argument")