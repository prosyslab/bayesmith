module F = Format

module Variable = struct
  type t = Var of int | Const of string | DontCare | Box of int

  let compare = compare

  let normalize cnt subst var =
    match var with
    | Const _ | DontCare -> (cnt, subst, var)
    | Var _ -> (
        try (cnt, subst, subst var)
        with Not_found ->
          let new_var = Var cnt in
          (cnt + 1, (fun x -> if x = var then new_var else subst x), new_var) )
    | Box _ -> (
        try (cnt, subst, subst var)
        with Not_found ->
          let new_var = Var cnt in
          (cnt + 1, (fun x -> if x = var then new_var else subst x), new_var) )

  let vid = ref (-1)

  let new_vid () =
    vid := !vid + 1;
    !vid

  let get_vid = function
    | Var i | Box i -> i
    | _ -> failwith "No id for Const nor DontCare"

  let make_var () = Var (new_vid ())

  let make_box () = Box (new_vid ())

  let into_var box =
    match box with
    | Box i -> Var i
    | _ -> failwith "Only a Box can be turn into Var"

  let box_into_var v = match v with Box i -> Var i | _ -> v

  let dontcare_box v = match v with Box _ -> DontCare | _ -> v

  let dontcare_box_except b v = if v = b then box_into_var b else dontcare_box v

  let dontcare_into_box v = match v with DontCare -> make_box () | _ -> v

  let is_box v = match v with Box _ -> true | _ -> false

  let is_var v = match v with Var _ -> true | _ -> false

  let pp fmt = function
    | Var i -> F.fprintf fmt "v%d" i
    | Const s -> F.fprintf fmt "\"%s\"" s
    | DontCare -> F.fprintf fmt "_"
    | Box i -> F.fprintf fmt "b%d" i

  let to_string = function
    | Var i -> "v" ^ string_of_int i
    | Const s -> "\"" ^ s ^ "\""
    | DontCare -> "_"
    | Box i -> "b" ^ string_of_int i

  let of_string s =
    if s = "_" then DontCare
    else if Str.string_match (Str.regexp "v\\([0-9]+\\)") s 0 then
      let i = Str.matched_group 1 s |> int_of_string in
      Var i
    else if Str.string_match (Str.regexp "b\\([0-9]+\\)") s 0 then
      let i = Str.matched_group 1 s |> int_of_string in
      Box i
    else Const s
end

module VariableSet = Set.Make (Variable)
module VariableIdSet = Set.Make (Int)

module Tuple = struct
  type t = {
    name : string;
    vars : Variable.t list;
    (* for optimization. hidden in Bayesian network *)
    hidden : bool;
    negation : bool;
    prob : float;
    neg_prob : float;
  }

  let normalize cnt subst tuple =
    let cnt, subst, vars =
      List.fold_left
        (fun (cnt, subst, vars) var ->
          let cnt, subst, var = Variable.normalize cnt subst var in
          (cnt, subst, vars @ [ var ]))
        (cnt, subst, []) tuple.vars
    in
    (cnt, subst, { tuple with vars })

  let make ?(hidden = false) ?(negation = false) ?(prob = 1.0) ?(neg_prob = 1.0)
      name vars =
    { name; vars; hidden; negation; prob; neg_prob }

  let assign_prob prob tup =
    {
      name = tup.name;
      vars = tup.vars;
      hidden = tup.hidden;
      negation = tup.negation;
      prob;
      neg_prob = tup.neg_prob;
    }

  let assign_neg_prob neg_prob tup =
    {
      name = tup.name;
      vars = tup.vars;
      hidden = tup.hidden;
      negation = tup.negation;
      prob = tup.prob;
      neg_prob;
    }

  let box_into_var tup =
    {
      name = tup.name;
      vars = List.map Variable.box_into_var tup.vars;
      hidden = tup.hidden;
      negation = tup.negation;
      prob = tup.prob;
      neg_prob = tup.neg_prob;
    }

  let dontcare_box tup =
    {
      name = tup.name;
      vars = List.map Variable.dontcare_box tup.vars;
      hidden = tup.hidden;
      negation = tup.negation;
      prob = tup.prob;
      neg_prob = tup.neg_prob;
    }

  let dontcare_box_except b tup =
    { tup with vars = List.map (Variable.dontcare_box_except b) tup.vars }

  let dontcare_into_box tup =
    { tup with vars = List.map Variable.dontcare_into_box tup.vars }

  let negate tup =
    {
      name = tup.name;
      vars = tup.vars;
      hidden = tup.hidden;
      negation = not tup.negation;
      prob = tup.prob;
      neg_prob = tup.neg_prob;
    }

  let negate_stop tup = tup |> negate |> dontcare_box

  let compare = compare

  let get_name tup = tup.name

  let get_full_name tup = (if tup.negation then "!" else "") ^ tup.name

  let get_first_var tup = List.nth (tup.vars |> List.filter Variable.is_var) 0

  let is_negated tup = tup.negation

  let is_alarm tup =
    if is_negated tup then false
    else if Str.string_match (Str.regexp ".*SparrowAlarm.*") tup.name 0 then
      false
    else Str.string_match (Str.regexp ".*Alarm.*") tup.name 0

  let boxes_in_alarm tup =
    if is_alarm tup then List.filter Variable.is_box tup.vars else []

  let boxes_in_tuple tup =
    if is_negated tup then [] else List.filter Variable.is_box tup.vars

  let occupied_head_vars tup =
    if is_negated tup then VariableSet.empty
    else
      match tup.name with
      | "SparrowAlarm" | "DUPath" | "DUEdge" | "FalseCond" | "TrueCond"
      | "FalseBranch" | "TrueBranch" ->
          VariableSet.empty
      | _ -> VariableSet.singleton (List.nth tup.vars 0)

  let get_negated_tup_head_vars ind tup =
    if is_negated tup then [ (List.nth tup.vars 0, ind) ] else []

  let find_box b tup =
    let rec find i v vars =
      match vars with
      | [] -> failwith (Variable.to_string v ^ " not found in " ^ tup.name)
      | h :: t -> if v = h then i else find (i + 1) v t
    in
    find 0 b tup.vars

  let is_v_present v tup =
    if is_negated tup then false
    else tup.vars |> VariableSet.of_list |> VariableSet.mem v

  let filter_box tup =
    let filtered =
      List.filter (fun v -> v |> Variable.is_box |> not) tup.vars
    in
    {
      name = tup.name;
      vars = filtered;
      hidden = tup.hidden;
      negation = tup.negation;
      prob = tup.prob;
      neg_prob = tup.neg_prob;
    }

  let make_v_var v tup =
    let new_vars =
      List.map
        (fun tv -> if tv = v then Variable.box_into_var v else tv)
        tup.vars
    in
    { tup with vars = new_vars }

  let extract_var_set tup =
    List.filter Variable.is_var tup.vars
    |> List.map Variable.get_vid |> VariableIdSet.of_list

  let pp fmt t =
    if t.negation then F.fprintf fmt "!%s(" t.name
    else F.fprintf fmt "%s(" t.name;
    match t.vars with
    | [ h ] -> F.fprintf fmt "%a)" Variable.pp h
    | h :: t ->
        F.fprintf fmt "%a" Variable.pp h;
        List.iter (fun v -> F.fprintf fmt ", %a" Variable.pp v) t;
        F.fprintf fmt ")"
    | [] -> failwith ("invalid tuple: " ^ t.name)

  let to_string t = F.asprintf "%a" pp t

  let equal_name n1 n2 =
    if
      String.length n1 > 6
      && String.length n2 > 6
      && String.sub n1 0 6 = "Deriv_"
      && String.sub n2 0 6 = "Deriv_"
    then
      let re = Str.regexp "Deriv_[a-zA-Z]+" in
      let b1 = Str.string_match re n1 0 in
      let s1 = if b1 then Some (Str.matched_string n1) else None in
      let b2 = Str.string_match re n2 0 in
      let s2 = if b2 then Some (Str.matched_string n2) else None in
      b1 && b2 && s1 = s2
    else n1 = n2

  let equal t1 t2 =
    equal_name t1.name t2.name
    && (try List.for_all2 ( = ) t1.vars t2.vars with _ -> false)
    && t1.hidden = t2.hidden && t1.negation = t2.negation && t1.prob = t2.prob
    && t1.neg_prob = t2.neg_prob

  let of_string s =
    let negation = Str.string_match (Str.regexp "!.*") s 0 in
    let _ =
      if negation then Str.search_forward (Str.regexp "!\\(.*\\)(\\(.*\\))") s 0
      else Str.search_forward (Str.regexp "\\(.*\\)(\\(.*\\))") s 0
    in
    let name = Str.matched_group 1 s in
    let tup_vars = Str.matched_group 2 s in
    let hidden = Str.string_match (Str.regexp "SparrowAlarm.*") name 0 in
    let vars_lst = Str.split (Str.regexp ", ") tup_vars in
    let vars = List.map (fun s -> Variable.of_string s) vars_lst in
    make name vars ~hidden ~negation
end

module ExMap = Map.Make (Variable)
module ExSet = Set.Make (String)
module ConMap = Map.Make (Variable)

module TF = struct
  type t = Bot | False | True | Top

  let init obs = if obs then True else False

  let observe tf obs =
    if obs then match tf with Bot | True -> True | _ -> Top
    else match tf with Bot | False -> False | _ -> Top
end

module TFMap = Map.Make (String)
module TupleSet = Set.Make (Tuple)

module Rule = struct
  type t = { head : Tuple.t; tail : Tuple.t list; prob : float }

  let make ?(prob = 0.99) head tail = { head; tail; prob }

  let normalize r =
    let cnt, subst, head =
      Tuple.normalize 0 (function _ -> raise Not_found) r.head
    in
    let _, _, tail =
      List.fold_left
        (fun (cnt, subst, tail) tuple ->
          let cnt, subst, tuple = Tuple.normalize cnt subst tuple in
          (cnt, subst, tail @ [ tuple ]))
        (cnt, subst, []) r.tail
    in
    { head; tail; prob = r.prob }

  let assign_prob prob rule = { head = rule.head; tail = rule.tail; prob }

  let compute_prob rule =
    let p =
      List.fold_left
        (fun p (tup : Tuple.t) ->
          let p_mult = if tup.negation then tup.neg_prob else tup.prob in
          p *. p_mult)
        1.0 rule.tail
    in
    let p_final = p *. rule.prob in
    assign_prob p_final rule

  let append tuples rule =
    { head = rule.head; tail = tuples @ rule.tail; prob = rule.prob }

  let box_into_var rule =
    {
      head = rule.head;
      tail = List.map Tuple.box_into_var rule.tail;
      prob = rule.prob;
    }

  let dontcare_box rule =
    {
      head = rule.head;
      tail = List.map Tuple.dontcare_box rule.tail;
      prob = rule.prob;
    }

  let dontcare_box_except b rule =
    { rule with tail = List.map (Tuple.dontcare_box_except b) rule.tail }

  let dontcare_into_box rule =
    { rule with tail = List.map Tuple.dontcare_into_box rule.tail }

  let get_alarm_tuple rule = List.nth (List.filter Tuple.is_alarm rule.tail) 0

  let boxes_in_alarm rule =
    List.fold_left (fun lst t -> lst @ Tuple.boxes_in_alarm t) [] rule.tail
    |> VariableSet.of_list |> VariableSet.elements

  let boxes_in_rule rule =
    List.fold_left (fun lst t -> lst @ Tuple.boxes_in_tuple t) [] rule.tail
    |> VariableSet.of_list |> VariableSet.elements

  let occupied_head_vars rule =
    List.fold_left
      (fun s t -> VariableSet.union s (Tuple.occupied_head_vars t))
      VariableSet.empty rule.tail

  let get_negated_tup_head_vars rule =
    let occupied_vars = occupied_head_vars rule in
    List.fold_left
      (fun (lst, i) tup -> (lst @ Tuple.get_negated_tup_head_vars i tup, i + 1))
      ([], 0) rule.tail
    |> fst
    |> List.fold_left
         (fun (lst, s) (v, i) ->
           if VariableSet.mem v s || VariableSet.mem v occupied_vars then
             (lst, s)
           else (lst @ [ (v, i) ], VariableSet.add v s))
         ([], VariableSet.empty)
    |> fst

  let find_box b rule =
    let box_containing_tups =
      List.filter
        (fun t ->
          (not (Tuple.is_negated t))
          && VariableSet.mem b (VariableSet.of_list t.Tuple.vars))
        rule.tail
    in
    assert (List.length box_containing_tups = 1);
    let ind_within_rule = List.nth box_containing_tups 0 |> Tuple.find_box b in
    ind_within_rule - 1

  let compare x y =
    let c = compare (List.length x.tail) (List.length y.tail) in
    if c = 0 then compare x y else c

  let derive_id = ref (-1)

  let new_derive_id () =
    derive_id := !derive_id + 1;
    !derive_id

  let derive_rule rule =
    let name = "Deriv_" ^ rule.head.name ^ string_of_int (new_derive_id ()) in
    let vars =
      List.fold_left
        (fun vars t ->
          VariableSet.of_list t.Tuple.vars |> VariableSet.union vars)
        VariableSet.empty rule.tail
      |> VariableSet.remove Variable.DontCare
      |> VariableSet.filter (fun e ->
             match e with
             | Variable.Const _ | Variable.Box _ -> false
             | _ -> true)
    in
    let vars = VariableSet.fold (fun x l -> x :: l) vars [] |> List.rev in
    { head = Tuple.make name vars; tail = rule.tail; prob = rule.prob }

  let make_ex_map ex rule =
    let inc_or_init tup v =
      let tup_name = Tuple.get_name tup in
      if (not (Tuple.is_negated tup)) && List.mem tup_name ex then
        match v with
        | Some s -> Some (ExSet.union (ExSet.singleton tup_name) s)
        | None -> Some (ExSet.singleton tup_name)
      else match v with None -> Some ExSet.empty | _ -> v
    in
    List.fold_left
      (fun m tup ->
        let first_var = Tuple.get_first_var tup in
        ExMap.update first_var (inc_or_init tup) m)
      ExMap.empty rule.tail

  let is_exclusive ex rule =
    rule |> make_ex_map ex |> ExMap.exists (fun _ v -> ExSet.cardinal v > 1)

  let make_con_map rule =
    let inc_or_init tup v =
      let tup_name = Tuple.get_name tup in
      let is_neg = Tuple.is_negated tup in
      let update_tf tf_val =
        Some (TF.observe (Option.get tf_val) (not is_neg))
      in
      match v with
      | Some m ->
          if TFMap.mem tup_name m then Some (TFMap.update tup_name update_tf m)
          else Some (TFMap.add tup_name (TF.init (not is_neg)) m)
      | None -> Some (TFMap.singleton tup_name (TF.init (not is_neg)))
    in
    List.fold_left
      (fun m tup ->
        let first_var = Tuple.get_first_var tup in
        ConMap.update first_var (inc_or_init tup) m)
      ConMap.empty rule.tail

  (* TODO: Consider one variable coupled with disjoint tuple head - e.g. one var to multiple alarms *)
  let is_self_contradiction rule =
    rule |> make_con_map
    |> ConMap.exists (fun _ v -> TFMap.exists (fun _ u -> u = TF.Top) v)

  let sort_tail rule =
    let compare a b =
      let aid = a |> Tuple.get_first_var |> Variable.get_vid in
      let bid = b |> Tuple.get_first_var |> Variable.get_vid in
      Int.compare aid bid
    in
    let new_tail = List.sort compare rule.tail in
    { head = rule.head; tail = new_tail; prob = rule.prob }

  let remove_trivial_duplicates rule =
    let new_tail = rule.tail |> TupleSet.of_list |> TupleSet.elements in
    { head = rule.head; tail = new_tail; prob = rule.prob }

  let dfs_tail rule_sorted =
    (* assume rule.tail is sorted and removed duplicates *)
    let rec traverse tail seen_vars result =
      let update_seen_vars seen_tup s =
        VariableIdSet.union (Tuple.extract_var_set seen_tup) s
      in
      if tail = [] then result
      else if VariableIdSet.is_empty seen_vars then
        traverse (List.tl tail)
          (update_seen_vars (List.hd tail) seen_vars)
          (List.hd tail :: result)
      else
        let compare a b =
          let get_score tup =
            let var_set = Tuple.extract_var_set tup in
            let inter =
              VariableIdSet.inter var_set seen_vars |> VariableIdSet.cardinal
            in
            let diff =
              VariableIdSet.diff var_set seen_vars |> VariableIdSet.cardinal
            in
            diff - inter
          in
          let ascore = get_score a in
          let bscore = get_score b in
          Int.compare ascore bscore
        in
        let new_sorted_tail = List.sort compare tail in
        let new_tup = List.nth new_sorted_tail 0 in
        let rec remove_item a i l =
          match l with
          | [] -> a
          | h :: t -> if h = i then a @ t else remove_item (a @ [ h ]) i t
        in
        let removed_tail = remove_item [] new_tup tail in
        traverse removed_tail
          (update_seen_vars new_tup seen_vars)
          (new_tup :: result)
    in
    let new_tail =
      traverse rule_sorted.tail VariableIdSet.empty [] |> List.rev
    in
    { head = rule_sorted.head; tail = new_tail; prob = rule_sorted.prob }

  let ground_internals rule =
    (* TODO: Remove suspicious List.rev *)
    let old_tail = rule.tail |> List.rev in
    let rec loop_for_grounding acc tail =
      match tail with
      | [] -> failwith "Empty list is impossible"
      | hd :: t ->
          if t = [] then acc @ [ hd ]
          else loop_for_grounding (acc @ [ Tuple.box_into_var hd ]) t
    in
    let new_tail = loop_for_grounding [] old_tail in
    { rule with tail = new_tail }

  let extract_all_variables rule =
    List.fold_left (fun l tup -> l @ tup.Tuple.vars) [] rule.tail

  let extract_boxes rule =
    extract_all_variables rule |> List.filter Variable.is_box

  let extract_vars rule =
    extract_all_variables rule |> List.filter Variable.is_var

  let num_negated_tups rule =
    rule.tail |> List.filter Tuple.is_negated |> List.length

  let pp ?(is_debug = false) fmt rule =
    F.fprintf fmt "%a :- " Tuple.pp rule.head;
    match rule.tail with
    | [ h ] ->
        if is_debug then F.fprintf fmt "%a. p: %f" Tuple.pp h rule.prob
        else F.fprintf fmt "%a." Tuple.pp h
    | h :: t ->
        F.fprintf fmt "%a" Tuple.pp h;
        List.iter (fun tuple -> F.fprintf fmt ", %a" Tuple.pp tuple) t;
        if is_debug then F.fprintf fmt ". p: %f" rule.prob
        else F.fprintf fmt "."
    | [] -> failwith "invalid rule"

  let to_string ?(is_debug = false) rule = F.asprintf "%a" (pp ~is_debug) rule

  let equal r1 r2 =
    Tuple.equal r1.head r2.head
    && (try List.for_all2 Tuple.equal r1.tail r2.tail with _ -> false)
    && string_of_float r1.prob = string_of_float r2.prob

  let make_v_var v rule =
    if Variable.is_box v then
      let new_tail =
        List.fold_left
          (fun acc tup -> Tuple.make_v_var v tup :: acc)
          [] rule.tail
        |> List.rev
      in
      { rule with tail = new_tail }
    else rule
end

module RuleSet = struct
  include Set.Make (Rule)

  let normalize ruleset = map Rule.normalize ruleset

  let pp ?(is_debug = false) fmt s =
    s |> elements
    |> List.iteri (fun i r ->
           if i = cardinal s - 1 then F.fprintf fmt "%a" (Rule.pp ~is_debug) r
           else F.fprintf fmt "%a\n" (Rule.pp ~is_debug) r)

  let equal s1 s2 =
    for_all
      (fun e1 -> exists (fun e2 -> Rule.equal e1 e2) (normalize s2))
      (normalize s1)
end

module RelationMap = struct
  include Map.Make (String)

  let add k v m =
    try
      if find k m = v then m
      else failwith ("relation " ^ k ^ " has two different arities")
    with Not_found -> add k v m
end

module RuleProbMap = Map.Make (String)

type t = {
  rules : RuleSet.t;
  derive_rules : RuleSet.t;
  inputs : int RelationMap.t;
  outputs : int RelationMap.t;
}
[@@deriving eq]

let eq d1 d2 =
  RuleSet.equal d1.rules d2.rules
  && RuleSet.equal d1.derive_rules d2.derive_rules

module NameSet = Set.Make (String)

let pp_decl fmt datalog =
  let all =
    RelationMap.union
      (fun k v1 v2 ->
        if v1 = v2 then Some v1
        else failwith ("relation " ^ k ^ " has two different arities"))
      datalog.inputs datalog.outputs
  in
  let pure_outputs =
    RelationMap.fold
      (fun k _ s -> NameSet.add k s)
      datalog.outputs NameSet.empty
  in
  let pure_inputs =
    RelationMap.fold
      (fun k _ s ->
        if RelationMap.mem k datalog.outputs then s else NameSet.add k s)
      datalog.inputs NameSet.empty
  in
  RelationMap.iter
    (fun k i ->
      F.fprintf fmt ".decl %s(" k;
      if i = 1 then F.fprintf fmt "v0: Node)\n"
      else (
        F.fprintf fmt "v0: Node";
        BatList.range 1 `To (i - 1)
        |> List.iter (fun x -> F.fprintf fmt ", v%d: Node" x);
        F.fprintf fmt ")\n" ))
    all;
  F.fprintf fmt "\n";
  NameSet.iter (fun x -> F.fprintf fmt ".input %s\n" x) pure_inputs;
  NameSet.iter (fun x -> F.fprintf fmt ".output %s\n" x) pure_outputs

let pp_derive fmt s =
  let outputs =
    RuleSet.fold
      (fun rule outputs ->
        RelationMap.add rule.head.name
          (List.length rule.head.Tuple.vars)
          outputs)
      s RelationMap.empty
  in
  let pure_outputs =
    RelationMap.fold (fun k _ s -> NameSet.add k s) outputs NameSet.empty
  in
  RelationMap.iter
    (fun k i ->
      F.fprintf fmt ".decl %s(" k;
      if i = 1 then F.fprintf fmt "v0: Node)\n"
      else (
        F.fprintf fmt "v0: Node";
        List.init (i - 1) (fun x -> x)
        |> List.iter (fun x -> F.fprintf fmt ", v%d: Node" (x + 1));
        F.fprintf fmt ")\n" ))
    outputs;
  F.fprintf fmt "\n";
  NameSet.iter (fun x -> F.fprintf fmt ".output %s\n" x) pure_outputs

let pp fmt p =
  F.fprintf fmt ".type Node <: symbol\n\n";
  pp_decl fmt p;
  pp_derive fmt p.derive_rules;
  F.fprintf fmt "\n";
  RuleSet.pp fmt p.rules;
  F.fprintf fmt "\n";
  RuleSet.pp fmt p.derive_rules;
  F.fprintf fmt "\n"

let make rules =
  let outputs, inputs =
    RuleSet.fold
      (fun rule (outputs, inputs) ->
        ( RelationMap.add rule.head.name
            (List.length
               (List.filter (fun v -> Variable.is_box v |> not) rule.head.vars))
            outputs,
          List.fold_left
            (fun inputs t ->
              RelationMap.add t.Tuple.name (List.length t.vars) inputs)
            inputs rule.tail ))
      rules
      (RelationMap.empty, RelationMap.empty)
  in
  if RuleSet.is_empty rules then prerr_endline "Rule EmpTY";
  if RelationMap.is_empty outputs then prerr_endline "EMPTY";
  Rule.derive_id := -1;
  { rules; derive_rules = RuleSet.map Rule.derive_rule rules; inputs; outputs }

let remove_deriv_tok head =
  if Str.string_match (Str.regexp "Deriv_\\(.*\\)") head 0 then
    Str.matched_group 1 head
  else ""

let of_file dl_file_path rule_prob_txt_path =
  let rec read_dl ic lines deriv_lines =
    match input_line ic with
    | s ->
        if Str.string_match (Str.regexp "Deriv_.*") s 0 then
          read_dl ic lines (s :: deriv_lines)
        else if
          Str.string_match (Str.regexp "\\..*") s 0
          || Str.string_match (Str.regexp "$") s 0
        then read_dl ic lines deriv_lines
        else read_dl ic (s :: lines) deriv_lines
    | exception End_of_file -> (lines, deriv_lines)
  in
  let rec read_txt ic map =
    match input_line ic with
    | s ->
        let _ = Str.string_match (Str.regexp "\\(.*\\): \\(.*\\)") s 0 in
        let rule_name = Str.matched_group 1 s in
        let prob = Str.matched_group 2 s |> Float.of_string in
        map |> RuleProbMap.add rule_name prob |> read_txt ic
    | exception End_of_file -> map
  in
  let ic_dl = open_in dl_file_path in
  let rule_lines, derive_rule_lines = read_dl ic_dl [] [] in
  let rule_prob_map =
    if rule_prob_txt_path = "" then RuleProbMap.empty
    else
      let ic_txt = open_in rule_prob_txt_path in
      let map = read_txt ic_txt RuleProbMap.empty in
      close_in ic_txt;
      map
  in
  close_in ic_dl;
  let make_rules l1 l2 =
    let get_head_and_tail line =
      let _ = Str.search_forward (Str.regexp "\\(.*\\) :- \\(.*\\).") line 0 in
      let head_string = Str.matched_group 1 line in
      let tail_string = Str.matched_group 2 line in
      let head = Tuple.of_string head_string in
      let tail_toks_splitted = Str.split (Str.regexp "), ") tail_string in
      let rec recover_toks acc = function
        | [] -> failwith "IMPOSSIBLE"
        | h :: t ->
            if t = [] then acc @ [ h ] else recover_toks (acc @ [ h ^ ")" ]) t
      in
      let tail_toks = recover_toks [] tail_toks_splitted in
      let tail = List.map Tuple.of_string tail_toks in
      (head, tail)
    in
    List.fold_left2
      (fun (s1, s2) line1 line2 ->
        let head, tail = get_head_and_tail line1 in
        let derive_head, derive_tail = get_head_and_tail line2 in
        let head_key = remove_deriv_tok derive_head.name in
        let prob =
          try RuleProbMap.find head_key rule_prob_map with Not_found -> 0.99
        in
        ( RuleSet.add (Rule.make ~prob head tail) s1,
          RuleSet.add (Rule.make ~prob derive_head derive_tail) s2 ))
      (RuleSet.empty, RuleSet.empty)
      l1 l2
  in
  let rules, derive_rules = make_rules rule_lines derive_rule_lines in
  let res = make rules in
  { res with derive_rules }
