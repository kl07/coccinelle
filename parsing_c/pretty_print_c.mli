type type_with_ident =
    (string * Ast_c.info) option ->
    (Ast_c.storage * Ast_c.il) option -> 
    Ast_c.fullType ->
    Ast_c.attribute list -> unit

type 'a printer = 'a -> unit 

type pretty_printers = {
  expression      : Ast_c.expression printer;
  arg_list        : (Ast_c.argument Ast_c.wrap2 list) printer;
  statement       : Ast_c.statement printer;
  decl            : Ast_c.declaration printer;
  init            : Ast_c.initialiser printer;
  param           : Ast_c.parameterType printer;
  ty              : Ast_c.fullType printer;
  type_with_ident : type_with_ident;
  toplevel        : Ast_c.toplevel printer;
  flow            : Control_flow_c.node printer
}

val mk_pretty_printers :
  pr_elem:Ast_c.info printer -> 
  pr_space:unit printer ->
  pr_nl: unit printer -> 
  pr_indent: unit printer ->
  pr_outdent: unit printer -> 
  pr_unindent: unit printer -> 
  pretty_printers

val pp_program_gen : 
  pr_elem:Ast_c.info printer -> 
  pr_space: unit printer -> 
  Ast_c.toplevel printer

val pp_toplevel_simple : 
  Ast_c.toplevel printer

val debug_info_of_node: 
  Ograph_extended.nodei -> Control_flow_c.cflow -> string

val string_of_expression: Ast_c.expression -> string
val string_of_toplevel: Ast_c.toplevel -> string
