open Base
open Common
open Ast_intf
open Result

let new_tyvar () = TyVar (Type_variable.create())

let rec derive context = function
  | Val c ->
     Ok (TyConstant c, Empty)
  | Var v ->
     begin match Context.find context v with
     | Some ty ->
        Ok (ty, Empty)
     | None ->
        Error ("unknown type variable: " ^ v)
     end
  | Struct exprs ->
     result_map_m ~f:(derive context) exprs
     >>| List.unzip
     >>| fun (tys, cs) -> (TyStruct tys, Conj cs)
  | App (f, args) ->
     derive context f >>= fun (tyf, cf) ->
     result_map_m
       ~f:(fun arg ->
           derive context arg >>|
           fun (ty, c) ->
             let alpha = new_tyvar () in
             (alpha, [Subtype (ty, alpha); c]))
       args
     >>= fun derived_form_args_with_alpha ->
     let alpha = new_tyvar () in
     let beta = new_tyvar () in
     let alphas = List.map ~f:fst derived_form_args_with_alpha in
     let args_constraints =
       derived_form_args_with_alpha
       |> List.map ~f:snd
       |> List.concat
     in
     let constraints =
         Eq (tyf, TyFun (alphas, alpha)) ::
         Subtype (beta, alpha) ::
         cf ::
         args_constraints
     in
     Ok (beta, Conj constraints)
  | Abs (vs, e) ->
     let new_tyvars = List.map ~f:(fun v -> (v, (new_tyvar ()))) vs in
     let added_context =
       List.fold_left
         ~f:(fun context (v, tyvar) -> Context.add v tyvar context)
         ~init:context
         new_tyvars in
     derive added_context e >>= fun (ty_e, c) ->
     let tyvar = new_tyvar () in
     Ok (tyvar, Eq (tyvar, TyConstraint (TyFun (List.map ~f:snd new_tyvars, ty_e), c)))
  | Let (v, e1, e2) ->
     derive context e1 >>= fun (ty_e1, c1) ->
     derive (Context.add v ty_e1 context) e2 >>= fun (ty_e2, c2) ->
     Ok (ty_e2, Conj [c1; c2])
  | Letrec (lets , e) ->
     let new_tyvars = List.map ~f:(fun (v, f) -> (v, f, (new_tyvar ()))) lets in
     let added_context =
       List.fold_left
         ~f:(fun context (v, _, tyvar) -> Context.add v tyvar context)
         ~init:context
         new_tyvars in
     let constraints_result =
       new_tyvars
       |> result_map_m ~f:(fun (_, f, tyvar) -> derive added_context f >>| fun(ty, c) -> (ty, c, tyvar))
       >>| List.map ~f:(fun (ty, c, tyvar) -> [Eq (tyvar, ty); c])
       >>| List.concat
     in
     constraints_result >>= fun constraints ->
     derive added_context e >>= fun (ty, c) ->
     Ok (ty, Conj (c :: constraints))
  | Case (e, clauses) ->
    (* assume that p is variable pattern temporarily *)
    let rec collect_vars = function
      | PatVar (v) -> [v]
      | PatStruct (elems) -> elems |> List.map ~f:(fun e -> collect_vars e)
                                   |> List.fold_left ~init:[] ~f:(fun a b -> List.append a b)
    in
    let new_tyvars = List.map ~f:(fun (p, b) -> (p, new_tyvar ())) clauses in
    Error (Printf.sprintf "WIP")
