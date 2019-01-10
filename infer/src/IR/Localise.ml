(*
 * Copyright (c) 2009-2013, Monoidics ltd.
 * Copyright (c) 2013-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd

(** Support for localisation *)

module F = Format
module MF = MarkupFormatter

module Tags = struct
  type t = (string * string) list [@@deriving compare]

  let bucket = &quot;bucket&quot;

  let call_line = &quot;call_line&quot;

  (** expression where a value escapes to *)
  let escape_to = &quot;escape_to&quot;

  let line = &quot;line&quot;

  (** string describing a C value, e.g. &quot;x.date&quot; *)
  let value = &quot;value&quot;

  (** describes a NPE that comes from parameter not nullable *)
  let parameter_not_null_checked = &quot;parameter_not_null_checked&quot;

  (** describes a NPE that comes from field not nullable *)
  let field_not_null_checked = &quot;field_not_null_checked&quot;

  (** @Nullable-annoted field/param/retval that causes a warning *)
  let nullable_src = &quot;nullable_src&quot;

  (** Weak variable captured in a block that causes a warning *)
  let weak_captured_var_src = &quot;weak_captured_var_src&quot;

  let empty_vector_access = &quot;empty_vector_access&quot;

  let create () = ref []

  let add tags tag value = List.Assoc.add ~equal:String.equal tags tag value

  let update tags tag value = tags := add !tags tag value

  let get tags tag = List.Assoc.find ~equal:String.equal tags tag
end

type error_desc = {descriptions: string list; tags: Tags.t; dotty: string option}
[@@deriving compare]

(** empty error description *)
let no_desc : error_desc = {descriptions= []; tags= []; dotty= None}

(** verbatim desc from a string, not to be used for user-visible descs *)
let verbatim_desc s = {no_desc with descriptions= [s]}

(** pretty print an error description *)
let pp_error_desc fmt err_desc = Pp.seq F.pp_print_string fmt err_desc.descriptions

let error_desc_get_dotty err_desc = err_desc.dotty

module BucketLevel = struct
  (** highest likelihood *)
  let b1 = &quot;B1&quot;

  let b2 = &quot;B2&quot;

  let b3 = &quot;B3&quot;

  let b4 = &quot;B4&quot;

  (** lowest likelihood *)
  let b5 = &quot;B5&quot;
end

(** get the bucket value of an error_desc, if any *)
let error_desc_get_bucket err_desc = Tags.get err_desc.tags Tags.bucket

(** set the bucket value of an error_desc *)
let error_desc_set_bucket err_desc bucket =
  let tags = Tags.add err_desc.tags Tags.bucket bucket in
  let descriptions =
    if Config.show_buckets then Printf.sprintf &quot;[%s]&quot; bucket :: err_desc.descriptions
    else err_desc.descriptions
  in
  {err_desc with descriptions; tags}


let error_desc_is_reportable_bucket err_desc =
  let issue_bucket = error_desc_get_bucket err_desc in
  let high_buckets = BucketLevel.[b1; b2] in
  Option.value_map issue_bucket ~default:false ~f:(fun b -&gt;
      List.mem ~equal:String.equal high_buckets b )


(** get the value tag, if any *)
let get_value_line_tag tags =
  try
    let value = snd (List.find_exn ~f:(fun (tag, _) -&gt; String.equal tag Tags.value) tags) in
    let line = snd (List.find_exn ~f:(fun (tag, _) -&gt; String.equal tag Tags.line) tags) in
    Some [value; line]
  with
  | Not_found_s _ | Caml.Not_found -&gt;
      None


(** extract from desc a value on which to apply polymorphic hash and equality *)
let desc_get_comparable err_desc =
  match get_value_line_tag err_desc.tags with Some sl&#39; -&gt; sl&#39; | None -&gt; err_desc.descriptions


(** hash function for error_desc *)
let error_desc_hash desc = Hashtbl.hash (desc_get_comparable desc)

(** equality for error_desc *)
let error_desc_equal desc1 desc2 =
  [%compare.equal: string list] (desc_get_comparable desc1) (desc_get_comparable desc2)


let line_tag_ tags tag loc =
  let line_str = string_of_int loc.Location.line in
  Tags.update tags tag line_str ;
  let s = &quot;line &quot; ^ line_str in
  if loc.Location.col &lt;&gt; -1 then
    let col_str = string_of_int loc.Location.col in
    s ^ &quot;, column &quot; ^ col_str
  else s


let at_line_tag tags tag loc = &quot;at &quot; ^ line_tag_ tags tag loc

let line_ tags loc = line_tag_ tags Tags.line loc

let at_line tags loc = at_line_tag tags Tags.line loc

let call_to proc_name =
  let proc_name_str = Typ.Procname.to_simplified_string proc_name in
  &quot;call to &quot; ^ MF.monospaced_to_string proc_name_str


let call_to_at_line tags proc_name loc =
  call_to proc_name ^ &quot; &quot; ^ at_line_tag tags Tags.call_line loc


let by_call_to proc_name = &quot;by &quot; ^ call_to proc_name

let by_call_to_ra tags ra = &quot;by &quot; ^ call_to_at_line tags ra.PredSymb.ra_pname ra.PredSymb.ra_loc

let add_by_call_to_opt problem_str proc_name_opt =
  match proc_name_opt with
  | Some proc_name -&gt;
      problem_str ^ &quot; &quot; ^ by_call_to proc_name
  | None -&gt;
      problem_str


let mem_dyn_allocated = &quot;memory dynamically allocated&quot;

let lock_acquired = &quot;lock acquired&quot;

let released = &quot;released&quot;

let reachable = &quot;reachable&quot;

(** dereference strings used to explain a dereference action in an error message *)
type deref_str =
  { tags: (string * string) list ref  (** tags for the error description *)
  ; value_pre: string option  (** string printed before the value being dereferenced *)
  ; value_post: string option  (** string printed after the value being dereferenced *)
  ; problem_str: string  (** description of the problem *) }

let pointer_or_object () = if Language.curr_language_is Java then &quot;object&quot; else &quot;pointer&quot;

let deref_str_null_ proc_name_opt problem_str_ =
  let problem_str = add_by_call_to_opt problem_str_ proc_name_opt in
  {tags= Tags.create (); value_pre= Some (pointer_or_object ()); value_post= None; problem_str}


(** dereference strings for null dereference *)
let deref_str_null proc_name_opt =
  let problem_str = &quot;could be null and is dereferenced&quot; in
  deref_str_null_ proc_name_opt problem_str


let access_str_empty proc_name_opt =
  let problem_str = &quot;could be empty and is accessed&quot; in
  deref_str_null_ proc_name_opt problem_str


(** dereference strings for null dereference due to Nullable annotation *)
let deref_str_nullable proc_name_opt nullable_obj_str =
  let tags = Tags.create () in
  Tags.update tags Tags.nullable_src nullable_obj_str ;
  (* to be completed once we know if the deref&#39;d expression is directly or transitively @Nullable*)
  let problem_str = &quot;&quot; in
  deref_str_null_ proc_name_opt problem_str


(** dereference strings for null dereference due to weak captured variable in block *)
let deref_str_weak_variable_in_block proc_name_opt nullable_obj_str =
  let tags = Tags.create () in
  Tags.update tags Tags.weak_captured_var_src nullable_obj_str ;
  let problem_str = &quot;&quot; in
  deref_str_null_ proc_name_opt problem_str


(** dereference strings for nonterminal nil arguments in c/objc variadic methods *)
let deref_str_nil_argument_in_variadic_method pn total_args arg_number =
  let function_method, nil_null =
    if Typ.Procname.is_c_method pn then (&quot;method&quot;, &quot;nil&quot;) else (&quot;function&quot;, &quot;null&quot;)
  in
  let problem_str =
    Printf.sprintf
      &quot;could be %s which results in a call to %s with %d arguments instead of %d (%s indicates \
       that the last argument of this variadic %s has been reached)&quot;
      nil_null
      (Typ.Procname.to_simplified_string pn)
      arg_number (total_args - 1) nil_null function_method
  in
  deref_str_null_ None problem_str


(** dereference strings for an undefined value coming from the given procedure *)
let deref_str_undef (proc_name, loc) =
  let tags = Tags.create () in
  let proc_name_str = Typ.Procname.to_simplified_string proc_name in
  { tags
  ; value_pre= Some (pointer_or_object ())
  ; value_post= None
  ; problem_str=
      &quot;could be assigned by a call to skip function &quot; ^ proc_name_str
      ^ at_line_tag tags Tags.call_line loc
      ^ &quot; and is dereferenced or freed&quot; }


(** dereference strings for a freed pointer dereference *)
let deref_str_freed ra =
  let tags = Tags.create () in
  let freed_or_closed_by_call =
    let freed_or_closed =
      match ra.PredSymb.ra_res with
      | PredSymb.Rmemory _ -&gt;
          &quot;freed&quot;
      | PredSymb.Rfile -&gt;
          &quot;closed&quot;
      | PredSymb.Rignore -&gt;
          &quot;freed&quot;
      | PredSymb.Rlock -&gt;
          &quot;locked&quot;
    in
    freed_or_closed ^ &quot; &quot; ^ by_call_to_ra tags ra
  in
  { tags
  ; value_pre= Some (pointer_or_object ())
  ; value_post= None
  ; problem_str= &quot;was &quot; ^ freed_or_closed_by_call ^ &quot; and is dereferenced or freed&quot; }


(** dereference strings for a dangling pointer dereference *)
let deref_str_dangling dangling_kind_opt =
  let dangling_kind_prefix =
    match dangling_kind_opt with
    | Some PredSymb.DAuninit -&gt;
        &quot;uninitialized &quot;
    | Some PredSymb.DAaddr_stack_var -&gt;
        &quot;deallocated stack &quot;
    | Some PredSymb.DAminusone -&gt;
        &quot;-1 &quot;
    | None -&gt;
        &quot;&quot;
  in
  { tags= Tags.create ()
  ; value_pre= Some (dangling_kind_prefix ^ pointer_or_object ())
  ; value_post= None
  ; problem_str= &quot;could be dangling and is dereferenced or freed&quot; }


(** dereference strings for a pointer size mismatch *)
let deref_str_pointer_size_mismatch typ_from_instr typ_of_object =
  let str_from_typ typ =
    let pp f = Typ.pp_full Pp.text f typ in
    F.asprintf &quot;%t&quot; pp
  in
  { tags= Tags.create ()
  ; value_pre= Some (pointer_or_object ())
  ; value_post= Some (&quot;of type &quot; ^ str_from_typ typ_from_instr)
  ; problem_str= &quot;could be used to access an object of smaller type &quot; ^ str_from_typ typ_of_object
  }


(** dereference strings for an array out of bound access *)
let deref_str_array_bound size_opt index_opt =
  let tags = Tags.create () in
  let size_str_opt =
    match size_opt with
    | Some n -&gt;
        let n_str = IntLit.to_string n in
        Some (&quot;of size &quot; ^ n_str)
    | None -&gt;
        None
  in
  let index_str =
    match index_opt with
    | Some n -&gt;
        let n_str = IntLit.to_string n in
        &quot;index &quot; ^ n_str
    | None -&gt;
        &quot;an index&quot;
  in
  { tags
  ; value_pre= Some &quot;array&quot;
  ; value_post= size_str_opt
  ; problem_str= &quot;could be accessed with &quot; ^ index_str ^ &quot; out of bounds&quot; }


(** Java unchecked exceptions errors *)
let java_unchecked_exn_desc proc_name exn_name pre_str : error_desc =
  { no_desc with
    descriptions=
      [ MF.monospaced_to_string (Typ.Procname.to_string proc_name)
      ; &quot;can throw &quot; ^ MF.monospaced_to_string (Typ.Name.name exn_name)
      ; &quot;whenever &quot; ^ pre_str ] }


let desc_unsafe_guarded_by_access accessed_fld guarded_by_str loc =
  let line_info = at_line (Tags.create ()) loc in
  let accessed_fld_str = Typ.Fieldname.to_string accessed_fld in
  let annot_str = Printf.sprintf &quot;@GuardedBy(\&quot;%s\&quot;)&quot; guarded_by_str in
  let syncronized_str =
    MF.monospaced_to_string (Printf.sprintf &quot;synchronized(%s)&quot; guarded_by_str)
  in
  let msg =
    Format.asprintf
      &quot;The field %a is annotated with %a, but the lock %a is not held during the access to the \
       field %s. Since the current method is non-private, it can be called from outside the \
       current class without synchronization. Consider wrapping the access in a %s block or \
       making the method private.&quot;
      MF.pp_monospaced accessed_fld_str MF.pp_monospaced annot_str MF.pp_monospaced guarded_by_str
      line_info syncronized_str
  in
  {no_desc with descriptions= [msg]}


let desc_custom_error loc : error_desc =
  {no_desc with descriptions= [&quot;detected&quot;; at_line (Tags.create ()) loc]}


(** type of access *)
type access =
  | Last_assigned of int * bool
  (* line, null_case_flag *)
  | Last_accessed of int * bool
  (* line, is_nullable flag *)
  | Initialized_automatically
  | Returned_from_call of int

let nullable_annotation_name proc_name =
  match Config.nullable_annotation with
  | Some name -&gt;
      name
  | None when Typ.Procname.is_java proc_name -&gt;
      &quot;@Nullable&quot;
  | None (* default Clang annotation name *) -&gt;
      &quot;_Nullable&quot;


let access_desc access_opt =
  match access_opt with
  | None -&gt;
      []
  | Some (Last_accessed (n, _)) -&gt;
      let line_str = string_of_int n in
      [&quot;last accessed on line &quot; ^ line_str]
  | Some (Last_assigned (n, _)) -&gt;
      let line_str = string_of_int n in
      [&quot;last assigned on line &quot; ^ line_str]
  | Some (Returned_from_call _) -&gt;
      []
  | Some Initialized_automatically -&gt;
      [&quot;initialized automatically&quot;]


let dereference_string proc_name deref_str value_str access_opt loc =
  let tags = deref_str.tags in
  Tags.update tags Tags.value value_str ;
  let is_call_access = match access_opt with Some (Returned_from_call _) -&gt; true | _ -&gt; false in
  let value_desc =
    String.concat ~sep:&quot;&quot;
      [ (match deref_str.value_pre with Some s -&gt; s ^ &quot; &quot; | _ -&gt; &quot;&quot;)
      ; (if is_call_access then &quot;returned by &quot; else &quot;&quot;)
      ; MF.monospaced_to_string value_str
      ; (match deref_str.value_post with Some s -&gt; &quot; &quot; ^ MF.monospaced_to_string s | _ -&gt; &quot;&quot;) ]
  in
  let problem_desc =
    let problem_str =
      let annotation_name = nullable_annotation_name proc_name in
      match (Tags.get !tags Tags.nullable_src, Tags.get !tags Tags.weak_captured_var_src) with
      | Some nullable_src, _ -&gt;
          if String.equal nullable_src value_str then
            &quot;is annotated with &quot; ^ annotation_name ^ &quot; and is dereferenced without a null check&quot;
          else
            &quot;is indirectly marked &quot; ^ annotation_name ^ &quot; (source: &quot;
            ^ MF.monospaced_to_string nullable_src
            ^ &quot;) and is dereferenced without a null check&quot;
      | None, Some weak_var_str -&gt;
          if String.equal weak_var_str value_str then
            &quot;is a weak pointer captured in the block and is dereferenced without a null check&quot;
          else
            &quot;is equal to the variable &quot;
            ^ MF.monospaced_to_string weak_var_str
            ^ &quot;, a weak pointer captured in the block, and is dereferenced without a null check&quot;
      | None, None -&gt;
          deref_str.problem_str
    in
    [problem_str ^ &quot; &quot; ^ at_line tags loc]
  in
  let access_desc = access_desc access_opt in
  {no_desc with descriptions= (value_desc :: access_desc) @ problem_desc; tags= !tags}


let parameter_field_not_null_checked_desc (desc : error_desc) exp =
  let parameter_not_nullable_desc var =
    let var_s = Pvar.to_string var in
    let param_not_null_desc =
      &quot;Parameter &quot; ^ MF.monospaced_to_string var_s
      ^ &quot; is not checked for null, there could be a null pointer dereference:&quot;
    in
    { desc with
      descriptions= param_not_null_desc :: desc.descriptions
    ; tags= (Tags.parameter_not_null_checked, var_s) :: desc.tags }
  in
  let field_not_nullable_desc exp =
    let rec exp_to_string exp =
      match exp with
      | Exp.Lfield (exp&#39;, field, _) -&gt;
          exp_to_string exp&#39; ^ &quot; -&gt; &quot; ^ Typ.Fieldname.to_string field
      | Exp.Lvar pvar -&gt;
          Mangled.to_string (Pvar.get_name pvar)
      | _ -&gt;
          &quot;&quot;
    in
    let var_s = exp_to_string exp in
    let field_not_null_desc =
      &quot;Instance variable &quot; ^ MF.monospaced_to_string var_s
      ^ &quot; is not checked for null, there could be a null pointer dereference:&quot;
    in
    { desc with
      descriptions= field_not_null_desc :: desc.descriptions
    ; tags= (Tags.field_not_null_checked, var_s) :: desc.tags }
  in
  match exp with
  | Exp.Lvar var -&gt;
      parameter_not_nullable_desc var
  | Exp.Lfield _ -&gt;
      field_not_nullable_desc exp
  | _ -&gt;
      desc


let has_tag (desc : error_desc) tag =
  List.exists ~f:(fun (tag&#39;, _) -&gt; String.equal tag tag&#39;) desc.tags


let is_parameter_not_null_checked_desc desc = has_tag desc Tags.parameter_not_null_checked

let is_field_not_null_checked_desc desc = has_tag desc Tags.field_not_null_checked

let desc_allocation_mismatch alloc dealloc =
  let tags = Tags.create () in
  let using (primitive_pname, called_pname, loc) =
    let by_call =
      if Typ.Procname.equal primitive_pname called_pname then &quot;&quot;
      else
        &quot; by call to &quot; ^ MF.monospaced_to_string (Typ.Procname.to_simplified_string called_pname)
    in
    &quot;using &quot;
    ^ MF.monospaced_to_string (Typ.Procname.to_simplified_string primitive_pname)
    ^ by_call ^ &quot; &quot;
    ^ at_line (Tags.create ()) (* ignore the tag *) loc
  in
  let description =
    Format.sprintf &quot;%s %s is deallocated %s&quot; mem_dyn_allocated (using alloc) (using dealloc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_condition_always_true_false i cond_str_opt loc =
  let tags = Tags.create () in
  let value = match cond_str_opt with None -&gt; &quot;&quot; | Some s -&gt; s in
  let tt_ff = if IntLit.iszero i then &quot;false&quot; else &quot;true&quot; in
  Tags.update tags Tags.value value ;
  let description =
    Format.sprintf &quot;Boolean condition %s is always %s %s&quot;
      (if String.equal value &quot;&quot; then &quot;&quot; else &quot; &quot; ^ MF.monospaced_to_string value)
      tt_ff (at_line tags loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_deallocate_stack_variable var_str proc_name loc =
  let tags = Tags.create () in
  Tags.update tags Tags.value var_str ;
  let description =
    Format.asprintf &quot;Stack variable %a is freed by a %s&quot; MF.pp_monospaced var_str
      (call_to_at_line tags proc_name loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_deallocate_static_memory const_str proc_name loc =
  let tags = Tags.create () in
  Tags.update tags Tags.value const_str ;
  let description =
    Format.asprintf &quot;Constant string %a is freed by a %s&quot; MF.pp_monospaced const_str
      (call_to_at_line tags proc_name loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_class_cast_exception pname_opt typ_str1 typ_str2 exp_str_opt loc =
  let tags = Tags.create () in
  let in_expression =
    match exp_str_opt with
    | Some exp_str -&gt;
        Tags.update tags Tags.value exp_str ;
        &quot; in expression &quot; ^ MF.monospaced_to_string exp_str ^ &quot; &quot;
    | None -&gt;
        &quot; &quot;
  in
  let at_line&#39; () =
    match pname_opt with
    | Some proc_name -&gt;
        &quot;in &quot; ^ call_to_at_line tags proc_name loc
    | None -&gt;
        at_line tags loc
  in
  let description =
    Format.asprintf &quot;%a cannot be cast to %a %s %s&quot; MF.pp_monospaced typ_str1 MF.pp_monospaced
      typ_str2 in_expression (at_line&#39; ())
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_divide_by_zero expr_str loc =
  let tags = Tags.create () in
  Tags.update tags Tags.value expr_str ;
  let description =
    Format.asprintf &quot;Expression %a could be zero %s&quot; MF.pp_monospaced expr_str (at_line tags loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_empty_vector_access pname_opt object_str loc =
  let vector_str = Format.asprintf &quot;Vector %a&quot; MF.pp_monospaced object_str in
  let desc = access_str_empty pname_opt in
  let tags = desc.tags in
  Tags.update tags Tags.empty_vector_access object_str ;
  let descriptions = [vector_str; desc.problem_str; at_line tags loc] in
  {no_desc with descriptions; tags= !tags}


let is_empty_vector_access_desc desc = has_tag desc Tags.empty_vector_access

let desc_frontend_warning desc sugg_opt loc =
  let tags = Tags.create () in
  let sugg = match sugg_opt with Some sugg -&gt; sugg | None -&gt; &quot;&quot; in
  (* If the description ends in a period, we remove it because the sentence continues with
  &quot;at line ...&quot; *)
  let desc = match String.chop_suffix ~suffix:&quot;.&quot; desc with Some desc -&gt; desc | None -&gt; desc in
  let description = Format.sprintf &quot;%s %s. %s&quot; desc (at_line tags loc) sugg in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_leak hpred_type_opt value_str_opt resource_opt resource_action_opt loc bucket_opt =
  let tags = Tags.create () in
  let () =
    match bucket_opt with Some bucket -&gt; Tags.update tags Tags.bucket bucket | None -&gt; ()
  in
  let xxx_allocated_to =
    let value_str, to_, on_ =
      match value_str_opt with
      | None -&gt;
          (&quot;&quot;, &quot;&quot;, &quot;&quot;)
      | Some s -&gt;
          Tags.update tags Tags.value s ;
          (MF.monospaced_to_string s, &quot; to &quot;, &quot; on &quot;)
    in
    let typ_str =
      match hpred_type_opt with
      | Some (Exp.Sizeof {typ= {desc= Tstruct name}}) when Typ.Name.is_class name -&gt;
          &quot; of type &quot; ^ MF.monospaced_to_string (Typ.Name.name name) ^ &quot; &quot;
      | _ -&gt;
          &quot; &quot;
    in
    let desc_str =
      match resource_opt with
      | Some (PredSymb.Rmemory _) -&gt;
          mem_dyn_allocated ^ to_ ^ value_str
      | Some PredSymb.Rfile -&gt;
          &quot;resource&quot; ^ typ_str ^ &quot;acquired&quot; ^ to_ ^ value_str
      | Some PredSymb.Rlock -&gt;
          lock_acquired ^ on_ ^ value_str
      | Some PredSymb.Rignore | None -&gt;
          if is_none value_str_opt then &quot;memory&quot; else value_str
    in
    if String.equal desc_str &quot;&quot; then [] else [desc_str]
  in
  let by_call_to =
    match resource_action_opt with Some ra -&gt; [by_call_to_ra tags ra] | None -&gt; []
  in
  let is_not_rxxx_after =
    let rxxx =
      match resource_opt with
      | Some (PredSymb.Rmemory _) -&gt;
          reachable
      | Some PredSymb.Rfile | Some PredSymb.Rlock -&gt;
          released
      | Some PredSymb.Rignore | None -&gt;
          reachable
    in
    [&quot;is not &quot; ^ rxxx ^ &quot; after &quot; ^ line_ tags loc]
  in
  let bucket_str =
    match bucket_opt with Some bucket when Config.show_buckets -&gt; bucket | _ -&gt; &quot;&quot;
  in
  { no_desc with
    descriptions= (bucket_str :: xxx_allocated_to) @ by_call_to @ is_not_rxxx_after; tags= !tags }


(** kind of precondition not met *)
type pnm_kind = Pnm_bounds | Pnm_dangling

let desc_precondition_not_met kind proc_name loc =
  let tags = Tags.create () in
  let kind_str =
    match kind with
    | None -&gt;
        []
    | Some Pnm_bounds -&gt;
        [&quot;possible array out of bounds&quot;]
    | Some Pnm_dangling -&gt;
        [&quot;possible dangling pointer dereference&quot;]
  in
  {no_desc with descriptions= kind_str @ [&quot;in &quot; ^ call_to_at_line tags proc_name loc]; tags= !tags}


let desc_null_test_after_dereference expr_str line loc =
  let tags = Tags.create () in
  Tags.update tags Tags.value expr_str ;
  let description =
    Format.asprintf &quot;Pointer %a was dereferenced at line %d and is tested for null %s&quot;
      MF.pp_monospaced expr_str line (at_line tags loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_retain_cycle cycle_str loc cycle_dotty =
  Logging.d_strln &quot;Proposition with retain cycle:&quot; ;
  let tags = Tags.create () in
  let desc =
    Format.sprintf &quot;Retain cycle %s involving the following objects:%s&quot; (at_line tags loc)
      cycle_str
  in
  {descriptions= [desc]; tags= !tags; dotty= cycle_dotty}


let registered_observer_being_deallocated_str obj_str =
  &quot;Object &quot; ^ obj_str
  ^ &quot; is registered in a notification center but not being removed before deallocation&quot;


let desc_registered_observer_being_deallocated pvar loc =
  let tags = Tags.create () in
  let obj_str = MF.monospaced_to_string (Pvar.to_string pvar) in
  { no_desc with
    descriptions=
      [ registered_observer_being_deallocated_str obj_str
        ^ at_line tags loc ^ &quot;. Being still registered as observer of the notification &quot;
        ^ &quot;center, the deallocated object &quot; ^ obj_str ^ &quot; may be notified in the future.&quot; ]
  ; tags= !tags }


let desc_unary_minus_applied_to_unsigned_expression expr_str_opt typ_str loc =
  let tags = Tags.create () in
  let expression =
    match expr_str_opt with
    | Some s -&gt;
        Tags.update tags Tags.value s ; &quot;expression &quot; ^ s
    | None -&gt;
        &quot;an expression&quot;
  in
  let description =
    Format.asprintf &quot;A unary minus is applied to %a of type %s %s&quot; MF.pp_monospaced expression
      typ_str (at_line tags loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_skip_function proc_name =
  let tags = Tags.create () in
  let proc_name_str = Typ.Procname.to_string proc_name in
  Tags.update tags Tags.value proc_name_str ;
  {no_desc with descriptions= [proc_name_str]; tags= !tags}


let desc_inherently_dangerous_function proc_name =
  let proc_name_str = Typ.Procname.to_string proc_name in
  let tags = Tags.create () in
  Tags.update tags Tags.value proc_name_str ;
  {no_desc with descriptions= [MF.monospaced_to_string proc_name_str]; tags= !tags}


let desc_stack_variable_address_escape pvar addr_dexp_str loc =
  let expr_str = Pvar.to_string pvar in
  let tags = Tags.create () in
  Tags.update tags Tags.value expr_str ;
  let escape_to_str =
    match addr_dexp_str with
    | Some s -&gt;
        Tags.update tags Tags.escape_to s ;
        &quot;to &quot; ^ s ^ &quot; &quot;
    | None -&gt;
        &quot;&quot;
  in
  let variable_str =
    if Pvar.is_frontend_tmp pvar then &quot;temporary&quot;
    else Format.asprintf &quot;stack variable %a&quot; MF.pp_monospaced expr_str
  in
  let description =
    Format.asprintf &quot;Address of %s escapes %s%s&quot; variable_str escape_to_str (at_line tags loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}


let desc_uninitialized_dangling_pointer_deref deref expr_str loc =
  let tags = Tags.create () in
  Tags.update tags Tags.value expr_str ;
  let prefix = match deref.value_pre with Some s -&gt; s | _ -&gt; &quot;&quot; in
  let description =
    Format.asprintf &quot;%s %a %s %s&quot; prefix MF.pp_monospaced expr_str deref.problem_str
      (at_line tags loc)
  in
  {no_desc with descriptions= [description]; tags= !tags}
