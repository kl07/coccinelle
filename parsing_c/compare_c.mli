type compare_result = 
  | Correct 
  | Pb of string
  | PbOnlyInNotParsedCorrectly of string


(* the string list is the output of diff *)

val compare_ast : 
 Common.filename -> Common.filename -> compare_result * string list 
val compare_token :
  Common.filename -> Common.filename -> compare_result * string list

val compare_default : 
  Common.filename -> Common.filename -> compare_result * string list


val compare_result_to_string : compare_result * string list -> string
val compare_result_to_bool : compare_result -> bool
