open Common open Commonop

(*****************************************************************************)
(*
 * statement, compound, 
 * return,
 * if, 
 * 
 * switch
 * 
 * for, while, dowhile
 * break/continue
 * goto, labels
 * 
 * todo: maintain a todo list of labels.
 * If two todos, then ambiguity. Can disambiguate some case by analysing and 
 * look if dependency, if one label  lead to another "naturally" (by a 
 * sequence of Direct without jump, in a compound).
 *
 *)
(*****************************************************************************)

open Ast_c
open Control_flow_c

open Ograph_extended
open Oassoc
open Oassocb
open Oset
open Osetb


(*---------------------------------------------------------------------------*)
let get_next_node g nodei = 
  match (g#successors nodei)#tolist with
  | [nexti, Direct] -> nexti,  unwrap (g#nodes#find nexti)
  | x -> raise Impossible
   

let get_next_nodes_ifthenelse_sorted g nodei = 
  (g#successors nodei)#tolist +> List.map (fun (nodei, Direct) -> 
    let node = unwrap (g#nodes#find nodei) in
    nodei, node,
    (match node with
    | TrueNode        -> 0
    | FalseNode       -> 1
    | FallThroughNode -> 2
    | AfterNode       -> 3
    | _ -> raise Impossible
    )
   ) +> List.sort (fun (_, _, a) (_, _, b) -> compare a b)
     +> List.map (fun (x,y,z) -> (x,y))


(* todo: return also a special node, when has no default case, there is a 
 * direct edge from startswitch to endswitch. 
 *)
let get_next_nodes_switch_sorted g nodei = 
  (g#successors nodei)#tolist +> List.map (fun (nodei, Direct) -> 
    nodei,
    get_next_node g nodei +> fst, 
    (match unwrap (g#nodes#find nodei) with
    | CaseNode i -> i
    | _ -> raise Impossible
    ))
   +> List.sort (fun (_, _, a) (_, _, b) -> compare a b)
   +> List.map (fun (a,b,c) -> (a,b))


let rec find_until_good_brace g level lasti = 
  match get_next_node g lasti with
  | nexti, SeqEnd (level2, i2) -> 
      assert (level2 >= level);
      if level2 = level 
      then (nexti,  i2)
      else find_until_good_brace g level nexti
  | _ -> raise Impossible


(*---------------------------------------------------------------------------*)
type returnkind = 
  | LastCurrentNode of nodei 
  | NoNextNode of nodei (* the node where we stopped *)


(*---------------------------------------------------------------------------*)
let (control_flow_to_ast: cflow -> definition) = fun g ->
  
  let nodes = g#nodes  in

  (* Add each time use a nodei, so that we know if have managed all the nodes.
   * Maybe it will help to spot some bugs, such as do we manage well the goto.
   *)
  let _visited = ref (new osetb Setb.empty) in
  let add_visited nodei = _visited := !_visited#add nodei in

  (* I add in _visited only for get_next_node, so for other functions
   * such as get_next_nodes_ifthenelse_sorted, you have to call explicitely
   * add_visited 
   *)
  let get_next_node g nodei = 
    add_visited nodei;
    (* call upper one *)
    let (nexti, node) = get_next_node g nodei in
    add_visited nexti;
    (nexti, node)
  in



  (* ------------------------- *)        
  let rec (rebuild_compound_instr_list: nodei -> int -> compound * returnkind)
   = fun starti level -> 
    add_visited starti;
    match unwrap (nodes#find starti) with
    | SeqEnd (level2,_) -> 
        if level = level2 
        then [], LastCurrentNode starti
        (* can raise Todo instead ? cos all opening { are correctly ended
           with a } *)
        else raise Impossible
    | x -> 
        let (st, return) = rebuild_statement starti in
        (match return with
        | NoNextNode _ -> [st], return (* because of a Goto or Return *)
        | LastCurrentNode nodei -> 
            let nexti = get_next_node g nodei +> fst in
            let (compound, return) = rebuild_compound_instr_list nexti level in
            st::compound, return
        )
       

  (* ------------------------- *)        
  and (rebuild_statement: nodei -> (statement * returnkind)) = fun starti -> 
    add_visited starti;
    match unwrap (nodes#find starti) with

    (* ------------------------- *)        
    | SeqStart (_fullst, level, i1) -> 
        let nexti = get_next_node g starti +> fst in

        let (compound, return) = rebuild_compound_instr_list  nexti level in

        (* look for the info of the endbrace *)
        let i2 = 
          match return with
          | LastCurrentNode lasti -> 
              (match unwrap (nodes#find lasti) with
              | SeqEnd (level2,i2) -> 
                  assert (level = level2);
                  i2
              | _ -> raise Impossible
              )
          | NoNextNode lasti -> 
              find_until_good_brace g level lasti +> snd
        in
        (Compound compound, [i1;i2]),  return
    (* ------------------------- *)        
    | Label (_fullst, (s, ii)) -> 

        let nexti =  get_next_node g starti +> fst in
        let (st, return) = rebuild_statement nexti in
        (Labeled (Ast_c.Label (s, st)),ii),  return

    | Goto (_fullst, (s,ii)) -> 
        
        (Jump (Ast_c.Goto s), ii), NoNextNode starti

    (* ------------------------- *)        
    | ExprStatement (_fullst, (e,ii)) -> 
        (Ast_c.ExprStatement e, ii), LastCurrentNode starti

          
    (* ------------------------- *)        
    | IfHeader (_fullst, (e,iiheader)) -> 
       (* TODO endif trick *)

         (match get_next_nodes_ifthenelse_sorted g starti with
         | [(theni, TrueNode);  (elsei, FalseNode); (afteri, AfterNode)] -> 
           add_visited theni; add_visited elsei; add_visited afteri;
               
           let theni' = get_next_node g theni +> fst in
           let elsei' = get_next_node g elsei +> fst in
           
           let (iielse, elsei') = 
             match unwrap (nodes#find elsei') with
             | Else iielse -> iielse,  get_next_node g elsei' +> fst
             | _ -> raise Impossible
           in
           let fullii = iiheader ++ [iielse] in
   
           let (st1, return1) = rebuild_statement theni' in
           let (st2, return2) = rebuild_statement elsei' in

   
           (* assert next of return1 = next of return 2 *)
           (match return1, return2 with
           | LastCurrentNode return1, LastCurrentNode return2 -> 
               assert ((fst (get_next_node g return1)  =|= 
                        fst (get_next_node g return2)) && 
                       (fst (get_next_node g return1) =|= 
                        fst (get_next_node g afteri)));
               (Selection (Ast_c.If (e, st1, st2)),fullii), 
                LastCurrentNode (get_next_node g return1 +> fst)
           | LastCurrentNode return, NoNextNode _  
           | NoNextNode _ , LastCurrentNode return ->
               (Selection (Ast_c.If (e, st1, st2)),fullii), 
                LastCurrentNode (get_next_node g return +> fst)
           | NoNextNode i1 , NoNextNode i2  -> 
               (Selection (Ast_c.If (e, st1, st2)),fullii), 
                NoNextNode i1 (* could be i2 *)
           )
   
         | [(theni, TrueNode);(falli, FallThroughNode);(afteri, AfterNode)] ->
             add_visited theni; add_visited falli; add_visited afteri;

             let theni' = get_next_node g theni +> fst in
             let (st1, return1) = rebuild_statement theni' in
             let (st2) = (Ast_c.ExprStatement (None), []) in
             let fullii = iiheader in

             (match return1 with
             | LastCurrentNode return -> 
                 assert (fst (get_next_node g return) =|= 
                         fst (get_next_node g afteri));
                 (Selection (Ast_c.If (e, st1, st2)),fullii), 
                  LastCurrentNode (get_next_node g afteri +> fst)
             | NoNextNode _ -> 
                 (Selection (Ast_c.If (e, st1, st2)),fullii), 
                  LastCurrentNode (get_next_node g afteri +> fst)
             )
   
         | [(theni, TrueNode);  (elsei, FalseNode)] -> 
             add_visited theni; add_visited elsei;
          (* if no after node, that means that the two branches go wild *)
               
           let theni' = get_next_node g theni +> fst in
           let elsei' = get_next_node g elsei +> fst in

           let (iielse, elsei') = 
             match unwrap (nodes#find elsei') with
             | Else iielse -> iielse,  get_next_node g elsei' +> fst
             | _ -> raise Impossible
           in
           let fullii = iiheader ++ [iielse] in
   
           let (st1, return1) = rebuild_statement theni' in
           let (st2, return2) = rebuild_statement elsei' in
   
           (* assert next of return1 = next of return 2 *)
           (match return1, return2 with
           | NoNextNode i1 , NoNextNode i2  -> 
               (Selection (Ast_c.If (e, st1, st2)),fullii), 
               NoNextNode i1 (* could be i2 *)

           (* if no after node, that means that the two branches go wild 
            * so can't have something different than NoNext, NoNext 
            *)
           | x -> raise Impossible 
           )
         | x -> raise Impossible
         )

    (* ------------------------- *)        
    | SwitchHeader (_fullst, (e,ii)) -> 

     (* Can have 2 successors, when there is no default case, we also directy
      * go to the end.
      *)
        let succ = 
          (g#successors starti)#tolist +> List.map (fun (nodei, Direct) -> 
              nodei, unwrap (g#nodes#find nodei)
          )
        in
        let nexti, endswitchiopt = 
          match succ with
          | [nexti, SeqStart _]                   -> nexti, None
          | [nexti, SeqStart _; endswitchi, Fake] 
          | [endswitchi, Fake; nexti, SeqStart _] -> nexti, Some endswitchi
          | _ -> raise Impossible
        in

        add_visited nexti;
        let (st, return) = 
          match unwrap (g#nodes#find nexti) with
          | SeqStart (_fullst2, level, i1) -> 

              let nodes_sorted = get_next_nodes_switch_sorted g nexti in
              
              let list_list_statement = 
                nodes_sorted +> map_filter (fun (casenodei, nodei) -> 
                  (* todo: do only if the 'case:' in question have only 1 
                     predecessor *)
                  add_visited casenodei;
                  if ((g#predecessors nodei)#tolist +> List.length) >= 2
                  then None
                  else Some (rebuild_compound_instr_list nodei level)
                ) in
              let compound = list_list_statement +> List.map fst +> List.concat
              in

              (* find the endswitch, it must be after the }level node *)
              let i2_candidat         = ref None in
              let endswitchi_candidat = ref None in

              list_list_statement +> List.map snd +> List.iter 
                 (function
                    (* can be because a return, or a break, but if a break,
                       when after there should be a close brace level and after the 
                       endswitch. *)
                    | NoNextNode nodei -> 
                        (match unwrap (nodes#find nodei) with
                        | Break _ -> 
                            (match get_next_node g nodei with
                            | nexti, SeqEnd (level2,i2) when level2 = level -> 
                                if !i2_candidat = None then 
                                  i2_candidat := Some (nexti, i2);
                                
                                (match get_next_node g nexti with
                                (* todo? assert the s = "[endswitch]" *)
                                | nextii, Fake -> 
                                    endswitchi_candidat := Some nextii
                                | _ -> raise Impossible
                                )
                            | _ -> raise Impossible
                            )
                        (* goto  or return *)
                        | _ -> 
                            let (lasti, i2) = 
                              find_until_good_brace g level nodei in
                            if !i2_candidat = None then 
                              i2_candidat := Some (lasti, i2);
                            
                        )
  
                     (* there was no break or return, certainly the default 
                        case *)
                    | LastCurrentNode nodei -> 
                        (match get_next_node g nodei with
                        | nexti, SeqEnd (level2,i2) when level2 = level -> 
                            i2_candidat := Some (nexti, i2);
                            (match get_next_node g nexti with
                            | nextii, Fake -> 
                               endswitchi_candidat := Some nextii
                            | _ -> raise Impossible
                            )
                        | _ -> raise Impossible
                        )
                          
                  );
               endswitchiopt +> do_option (fun nodei -> 
                  endswitchi_candidat := Some nodei
               );
                
               let return, i2 = 
                 match !endswitchi_candidat, !i2_candidat  with 
                   (* take first one *)
                 | Some x, Some (lasti, i2) -> 
                     add_visited x;
                     LastCurrentNode x, i2
                 | None,  Some (lasti, i2) -> NoNextNode lasti, i2
                 | _ -> raise Impossible
               in
              (Compound compound, [i1;i2]), return
       

          | _ -> raise Impossible
          
       in
      (Selection (Switch (e, st)), ii), return


    (* alt: would like to return None, cos it will be handle elsewhere
       or can handle it, but when handle a case in the iter of the
       switch, check that have no 2 predecessors, which would mean
       that this case has certainly be already handled. *)      

    | Case  (_fullst, (e, ii)) -> 
        let nexti =  get_next_node g starti +> fst in
        let (st, return) = rebuild_statement nexti in
        (Labeled (Ast_c.Case (e, st)),ii),  return

    | CaseRange _ -> raise Todo

    | Default  (_fullst, ((),ii)) -> 
        let nexti =  get_next_node g starti +> fst in
        let (st, return) = rebuild_statement nexti in
        (Labeled (Ast_c.Default st),ii),  return


    (* ------------------------- *)        
    | WhileHeader (_fullst, (e,ii)) -> 
        (match get_next_nodes_ifthenelse_sorted g starti with
         | [(theni, TrueNode);  (endfori, FalseNode)] -> 
               
           let theni' = get_next_node g theni +> fst in
           let (st, return) = rebuild_statement theni' in
           (* check? if return is LastCurrentNode, it must be = endfori *)
           (Iteration  (Ast_c.While (e, st)), ii), LastCurrentNode endfori
         | _ -> raise Impossible           
        )

    | DoHeader (_fullst, iido) -> 
        raise Todo

    | ForHeader (_fullst, ((e1opt, e2opt, e3opt), ii)) -> 
        (match get_next_nodes_ifthenelse_sorted g starti with
         | [(theni, TrueNode);  (endfori, FalseNode)] -> 
               
           let theni' = get_next_node g theni +> fst in
           let (st, return) = rebuild_statement theni' in
           (* check? if return is LastCurrentNode, it must be = endfori *)
           (Iteration  (Ast_c.For (e1opt, e2opt, e3opt, st)), ii), 
           LastCurrentNode endfori
         | _ -> raise Impossible           
        )



    (* ------------------------- *)        
    | Break (_fullst, ((),ii)) ->  
        (Jump (Ast_c.Break), ii), NoNextNode starti
    | Continue (_fullst, ((),ii)) ->  
        (Jump (Ast_c.Continue), ii), NoNextNode starti
        

    | Return (_fullst, ((),ii)) -> 
        (Jump Ast_c.Return, ii), NoNextNode starti
    | ReturnExpr (_fullst, (e,ii)) -> 
        (Jump (Ast_c.ReturnExpr e), ii), NoNextNode starti


    (* ------------------------- *)        
    | Decl decl -> 
        let iiempty = [] in
        (Ast_c.Decl decl, iiempty), LastCurrentNode starti


    (* ------------------------- *)        
    | Asm -> 
        let iiempty = [] in
        (Ast_c.Asm, iiempty), LastCurrentNode starti

    | CaseNode _ | DoWhileTail _ | Else _ | SeqEnd _ | FunHeader _ -> 
        raise Impossible

    | Exit|Enter
    | ErrorExit 
    | FallThroughNode|AfterNode
    | FalseNode|TrueNode 
    | Fake
      -> raise Impossible
  in

  (* todo?: assert stuff on returnkind of compound ? 
   * normally lead to an exit node, or nothing 
   *)

  let starti = get_first_node g in
  add_visited starti;

  let ((funcs, functype, sto), iifuncheader) =  
    match unwrap (nodes#find starti) with 
    | FunHeader funcdef -> funcdef  
    | _ -> raise Impossible
  in

  let (topcompound, returnkind) = 
    (match get_next_node g starti with
    | (nexti,  Enter)  -> 
        let nextii = get_next_node g nexti +> fst in
        rebuild_statement nextii
    | x -> raise Impossible (* there must be an Enter node after the HeadFun *)
    )
  in

  let (cpfunc, iicp) = 
    match topcompound with 
    | (Compound st, ii) -> st, ii
    | x -> raise Impossible
  in

  (* sanity checks *)
  let visited_nodesi = !_visited in
  let all_nodesi = (new osetb Setb.empty)#fromlist (List.map fst nodes#tolist)
  in
  let diff = (all_nodesi $--$ visited_nodesi)#tolist in
  let diffnodes = diff +> List.map (fun nodei -> nodei, nodes#find nodei) in

  diffnodes +> List.iter (fun (nodei, node) -> 
     match unwrap node with
     | Exit | ErrorExit -> ()
     | SeqEnd _ -> () (* TODO ?*)
     | _ -> failwith "pb in flow_to_ast, some nodes have not been visited"
      );


  match iifuncheader, iicp with
  | iidb::ioparenb::icparenb::iistob, [i1;i2] -> 
      (funcs, functype, sto, cpfunc), iidb::ioparenb::icparenb::i1::i2::iistob
  | _ -> raise Impossible
 


(*****************************************************************************)

let test def = 
  let g = Ast_to_flow.ast_to_control_flow def in
  Ast_to_flow.check_control_flow g;
  print_ograph_extended g;
  assert (
  def =*= def +> Ast_to_flow.ast_to_control_flow +>control_flow_to_ast
 );
