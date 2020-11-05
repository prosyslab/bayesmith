let truecond = "TrueCond"

let falsecond = "FalseCond"

let truebranch = "TrueBranch"

let falsebranch = "FalseBranch"

let alarm = "Alarm"

let sparrow_alarm = "SparrowAlarm"

let alarm_deref_exp = "AlarmDerefExp"

let alarm_array_exp = "AlarmArrayExp"

let alarm_strcpy = "AlarmStrcpy"

let alarm_buffer_overrun_lib = "AlarmBufferOverrunLib"

let lval_exp = "LvalExp"

let loophead = "LoopHead"

let join = "Join"

let assume = "Assume"

let unop = "UnOpExp"

let binop = "BinOpExp"

let libcall = "LibCall"

let entry = "Entry"

let exit = "Exit"

let assign = "Assign"

let cast = "CastExp"

let ne = "Ne"

let eq = "Eq"

let pluspi = "PlusPI"

let minuspp = "MinusPP"

let path_exclusives = [ libcall; loophead; assume; cast; unop; binop; lval_exp ]

let alarm_exclusives =
  [ alarm_deref_exp; alarm_strcpy; alarm_array_exp; alarm_buffer_overrun_lib ]

let exclusives = [ path_exclusives; alarm_exclusives ]

let filter_exclusive rules =
  rules
  |> List.filter (fun rule ->
         rule |> Datalog.Rule.is_exclusive path_exclusives |> not)
  |> List.filter (fun rule ->
         rule |> Datalog.Rule.is_exclusive alarm_exclusives |> not)

let filter_self_contradiction rules =
  rules
  |> List.filter (fun rule -> rule |> Datalog.Rule.is_self_contradiction |> not)

let sort_within_rule_tail rules = rules |> List.map Datalog.Rule.sort_tail

let dfs_rule_tail rules = rules |> List.map Datalog.Rule.dfs_tail

let ground_internals rules = rules |> List.map Datalog.Rule.ground_internals

let make_v_var v rules = rules |> List.map (Datalog.Rule.make_v_var v)

let remove_trivial_rule_tail_dup rules =
  rules |> List.map Datalog.Rule.remove_trivial_duplicates

let rec populate_tuples tup_l acc result =
  match tup_l with
  | [] -> result
  | h :: t -> (
      match t with
      | [] -> [ h :: acc; Datalog.Tuple.negate h :: acc ] @ result
      | _ ->
          populate_tuples t (h :: acc)
            ([ Datalog.Tuple.negate_stop h :: acc ] @ result) )

let populate ?(prob = 1.0) v make_tuple rules =
  List.fold_left
    (fun l rule ->
      let new_tuple_list = make_tuple v prob in
      let new_tuples = populate_tuples new_tuple_list [] [] in
      let append = Datalog.Rule.append in
      let new_rules =
        List.map
          (fun t -> append t rule |> Datalog.Rule.compute_prob)
          new_tuples
      in
      l @ new_rules)
    [] rules
  |> make_v_var v |> ground_internals |> filter_exclusive
  |> filter_self_contradiction |> remove_trivial_rule_tail_dup
  |> sort_within_rule_tail |> dfs_rule_tail
