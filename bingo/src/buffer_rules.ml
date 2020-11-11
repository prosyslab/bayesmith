let duedge = "DUEdge"

let duinteredge = "DUInterEdge"

let dupath = "DUPath"

let truecond = "TrueCond"

let falsecond = "FalseCond"

let truebranch = "TrueBranch"

let falsebranch = "FalseBranch"

let alarm = "Alarm"

let sparrow_alarm = "SparrowAlarm"

let alarm_deref_exp = "AlarmDerefExp"

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

let field = "Field"

let v0 = Datalog.Variable.make_var ()

let v1 = Datalog.Variable.make_var ()

let v2 = Datalog.Variable.make_var ()

let v3 = Datalog.Variable.make_var ()

let v4 = Datalog.Variable.make_var ()

let r_base_cases =
  let r0 =
    Datalog.Rule.make
      (Datalog.Tuple.make dupath [ v0; v1 ])
      [ Datalog.Tuple.make duedge [ v0; v1 ] ]
  in
  let r1 =
    Datalog.Rule.make
      (Datalog.Tuple.make dupath [ v0; v1 ])
      [ Datalog.Tuple.make truebranch [ v0; v1 ] ]
  in
  let r2 =
    Datalog.Rule.make
      (Datalog.Tuple.make dupath [ v0; v1 ])
      [ Datalog.Tuple.make falsebranch [ v0; v1 ] ]
  in
  [ r0; r1; r2 ]

let r_path =
  Datalog.Rule.make
    (Datalog.Tuple.make dupath [ v0; v1 ])
    [
      Datalog.Tuple.make dupath [ v0; v2 ];
      Datalog.Tuple.make duedge [ v2; v1 ];
      Datalog.Tuple.make sparrow_alarm ~hidden:true [ v0; DontCare; DontCare ];
    ]

let r_true_cond =
  Datalog.Rule.make
    (Datalog.Tuple.make dupath [ v0; v1 ])
    [
      Datalog.Tuple.make dupath [ v0; v2 ];
      Datalog.Tuple.make truecond [ v2 ];
      Datalog.Tuple.make truebranch [ v2; v1 ];
    ]

let r_false_cond =
  Datalog.Rule.make
    (Datalog.Tuple.make dupath [ v0; v1 ])
    [
      Datalog.Tuple.make dupath [ v0; v2 ];
      Datalog.Tuple.make falsecond [ v2 ];
      Datalog.Tuple.make falsebranch [ v2; v1 ];
    ]

let b_alarm = Datalog.Variable.make_box ()

let r_sparrow_alarm =
  Datalog.Rule.make
    (Datalog.Tuple.make alarm [ v0; v1 ])
    [
      Datalog.Tuple.make dupath [ v0; v1 ];
      Datalog.Tuple.make sparrow_alarm ~hidden:true [ v0; v1; b_alarm ];
    ]

let r_alarm = Datalog.Rule.dontcare_box r_sparrow_alarm

let fold_rules rules =
  List.fold_left
    (fun s el ->
      let grounded_rule = Datalog.Rule.box_into_var el in
      Datalog.RuleSet.add grounded_rule s)
    Datalog.RuleSet.empty rules

(* reproduce BufferOverflow.dl in PLDI'19 *)
(* DUPath(x,y) :- DUEdge(x,y).
   DUPath(x,y) :- TrueBranch(x,y).
   DUPath(x,y) :- FalseBranch(x,y).
   DUPath(x,y) :- DUPath(x,z), DUEdge(z,y), Alarm(x,_).
   DUPath(x,y) :- DUPath(x,z), TrueCond(z), TrueBranch(z,y).
   DUPath(x,y) :- DUPath(x,z), FalseCond(z), FalseBranch(z,y).
   Alarm(x,y)  :- DUPath(x,y), SparrowAlarm(x,y).
*)
let buffer_overflow_rules_baseline =
  fold_rules (r_base_cases @ [ r_true_cond; r_false_cond; r_path; r_alarm ])

(* Modify this rule for manual rule generation *)
let buffer_overflow_rules =
  fold_rules (r_base_cases @ [ r_true_cond; r_false_cond; r_path; r_alarm ])
