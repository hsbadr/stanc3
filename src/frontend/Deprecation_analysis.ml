open Core
open Ast
open Middle

let current_removal_version = (2, 35)

let expired (major, minor) =
  let removal_major, removal_minor = current_removal_version in
  removal_major > major || (removal_major = major && removal_minor >= minor)

let deprecated_functions = String.Map.of_alist_exn []
let stan_lib_deprecations = deprecated_functions

(* TODO deprecate other pre-variadics like algebra_solver? *)
let deprecated_odes =
  String.Map.of_alist_exn
    [ ("integrate_ode", ("ode_rk45", (3, 0)))
    ; ("integrate_ode_rk45", ("ode_rk45", (3, 0)))
    ; ("integrate_ode_bdf", ("ode_bdf", (3, 0)))
    ; ("integrate_ode_adams", ("ode_adams", (3, 0))) ]

let rename_deprecated map name =
  Map.find map name |> Option.map ~f:fst |> Option.value ~default:name

let userdef_functions program =
  match program.functionblock with
  | None -> Hash_set.Poly.create ()
  | Some {stmts; _} ->
      List.filter_map stmts ~f:(function
        | {stmt= FunDef {body= {stmt= Skip; _}; _}; _} -> None
        | {stmt= FunDef {funname; arguments; _}; _} ->
            Some (funname.name, Ast.type_of_arguments arguments)
        | _ -> None)
      |> Hash_set.Poly.of_list

let is_redundant_forwarddecl fundefs funname arguments =
  Hash_set.mem fundefs (funname.name, Ast.type_of_arguments arguments)

let lkj_cov_message =
  "lkj_cov is deprecated and will be removed in Stan 3.0. Use lkj_corr with an \
   independent lognormal distribution on the scales, see: \
   https://mc-stan.org/docs/reference-manual/deprecations.html#lkj_cov-distribution"

let functions_block_contains_jac_pe (stmts : untyped_statement list) =
  (* tracking if 'jacobian' is a variable in scope *)
  let jacobian_scope_id = ref 0 in
  let is_jacobian_in_scope () = !jacobian_scope_id > 0 in
  let current_scope_id = ref 1 in
  let found_jacobian () =
    if not (is_jacobian_in_scope ()) then jacobian_scope_id := !current_scope_id
  in
  let push_scope () = current_scope_id := !current_scope_id + 1 in
  let pop_scope () =
    current_scope_id := !current_scope_id - 1;
    (* if the scope we just left was the one defining jacobian, reset it *)
    if !jacobian_scope_id > !current_scope_id then jacobian_scope_id := 0 in
  (* walk over the tree, looking for usages of jacobian+= where
     there is no variable called jacobian already in scope *)
  let rec f (s : untyped_statement) =
    match s.stmt with
    | FunDef {body; funname; _}
      when String.is_suffix funname.name ~suffix:"_jacobian" ->
        push_scope ();
        let res = f body in
        pop_scope ();
        res
    | Block stmts | Profile (_, stmts) ->
        push_scope ();
        let res = List.exists ~f stmts in
        pop_scope ();
        res
    | For {loop_body; _} | While (_, loop_body) | ForEach (_, _, loop_body) ->
        push_scope ();
        let res = f loop_body in
        pop_scope ();
        res
    | IfThenElse (_, s1, s2_opt) ->
        push_scope ();
        let res1 = f s1 in
        pop_scope ();
        push_scope ();
        let res2 = match s2_opt with Some s2 -> f s2 | None -> false in
        pop_scope ();
        res1 || res2
    | JacobianPE _ -> true
    | Assignment
        { assign_lhs= LValue {lval= LVariable {name; _}; _}
        ; assign_op= OperatorAssign Plus
        ; _ }
      when String.equal name "jacobian" ->
        not (is_jacobian_in_scope ())
    | VarDecl {variables; _} ->
        if
          List.exists
            ~f:(fun {identifier; _} -> String.equal identifier.name "jacobian")
            variables
        then found_jacobian ();
        false
    | _ -> false in
  let res = List.exists ~f stmts in
  (* sanity check that pushes and pops are balanced *)
  if !current_scope_id <> 1 then
    Common.ICE.internal_compiler_error
      [%message
        "functions_block_contains_jac_pe: scope tracking failed"
          (!current_scope_id : int)
          (!jacobian_scope_id : int)
          (stmts : untyped_statement list)];
  res

let set_jacobian_compatibility_mode stmts =
  Fun_kind.jacobian_compat_mode := not (functions_block_contains_jac_pe stmts)

let rec collect_deprecated_expr (acc : (Location_span.t * string) list)
    ({expr; emeta} : (typed_expr_meta, fun_kind) expr_with) :
    (Location_span.t * string) list =
  match expr with
  | CondDistApp ((StanLib _ | UserDefined _), {name; _}, l)
   |FunApp ((StanLib _ | UserDefined _), {name; _}, l) ->
      let w =
        match Map.find stan_lib_deprecations name with
        | Some (rename, (major, minor)) ->
            if expired (major, minor) then []
            else
              let version = string_of_int major ^ "." ^ string_of_int minor in
              [ ( emeta.loc
                , name ^ " is deprecated and will be removed in Stan " ^ version
                  ^ ". Use " ^ rename
                  ^ " instead. This can be automatically changed using the \
                     canonicalize flag for stanc" ) ]
        | _ -> (
            match Map.find deprecated_odes name with
            | Some (rename, (major, minor)) ->
                let version = string_of_int major ^ "." ^ string_of_int minor in
                [ ( emeta.loc
                  , name ^ " is deprecated and will be removed in Stan "
                    ^ version ^ ". Use " ^ rename
                    ^ " instead. \n\
                       The new interface is slightly different, see: \
                       https://mc-stan.org/users/documentation/case-studies/convert_odes.html"
                  ) ]
            | _ ->
                if String.equal name "lkj_cov_lpdf" then
                  [(emeta.loc, lkj_cov_message)]
                else []) in
      acc @ w @ List.concat_map l ~f:(fun e -> collect_deprecated_expr [] e)
  | _ -> fold_expression collect_deprecated_expr (fun l _ -> l) acc expr

let collect_deprecated_lval acc l =
  fold_lval_with collect_deprecated_expr (fun x _ -> x) acc l

let rec collect_deprecated_stmt fundefs (acc : (Location_span.t * string) list)
    {stmt; _} : (Location_span.t * string) list =
  match stmt with
  | FunDef {body= {stmt= Skip; _}; funname; arguments; _}
    when is_redundant_forwarddecl fundefs funname arguments ->
      acc
      @ [ ( funname.id_loc
          , "Functions do not need to be declared before definition; all user \
             defined function names are always in scope regardless of \
             definition order." ) ]
  | FunDef {funname; body; _}
    when !Fun_kind.jacobian_compat_mode
         && String.is_suffix funname.name ~suffix:"_jacobian" ->
      let acc =
        ( funname.id_loc
        , "Functions that end in _jacobian will change meaning in Stan 2.39. \
           They will be used for the encapsulating usages of 'jacobian +=', \
           and therefore not available to be called in all the same places as \
           this function is now. To avoid any issues, please rename this \
           function to not end in _jacobian." )
        :: acc in
      fold_statement collect_deprecated_expr
        (collect_deprecated_stmt fundefs)
        collect_deprecated_lval
        (fun l _ -> l)
        acc body.stmt
  | Tilde {distribution; _} when String.equal distribution.name "lkj_cov" ->
      let acc = (distribution.id_loc, lkj_cov_message) :: acc in
      fold_statement collect_deprecated_expr
        (fun s _ -> s)
        collect_deprecated_lval
        (fun l _ -> l)
        acc stmt
  | _ ->
      fold_statement collect_deprecated_expr
        (collect_deprecated_stmt fundefs)
        collect_deprecated_lval
        (fun l _ -> l)
        acc stmt

let collect_warnings (program : typed_program) =
  let fundefs = userdef_functions program in
  fold_program (collect_deprecated_stmt fundefs) [] program

let remove_unneeded_forward_decls program =
  let fundefs = userdef_functions program in
  let drop_forwarddecl = function
    | {stmt= FunDef {body= {stmt= Skip; _}; funname; arguments; _}; _}
      when is_redundant_forwarddecl fundefs funname arguments ->
        false
    | _ -> true in
  { program with
    functionblock=
      Option.map program.functionblock ~f:(fun x ->
          {x with stmts= List.filter ~f:drop_forwarddecl x.stmts}) }
