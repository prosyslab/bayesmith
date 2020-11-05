module F = Format

module GroundedTuple = struct
  type t = { name : string; elements : string list }

  let of_string s =
    let tokens = String.split_on_char '(' s in
    let name = List.nth tokens 0 in
    let elements =
      List.nth tokens 1
      |> (fun s -> String.sub s 0 (String.length s - 1))
      |> String.split_on_char ','
    in
    { name; elements }

  let is_negated t = String.sub t.name 0 1 = "!"

  let is_alarm t =
    if is_negated t then false
    else Str.string_match (Str.regexp ".*Alarm.*") t.name 0

  let nth_elt_to_string n t = Printf.sprintf "%s" (List.nth t.elements n)

  let elements_to_string t = Printf.sprintf "%s" (String.concat "," t.elements)

  let to_string t =
    Printf.sprintf "%s(%s)" t.name (String.concat "," t.elements)
end

module GroundedRule = struct
  type t = {
    name : string;
    conclusion : GroundedTuple.t;
    premises : GroundedTuple.t list;
  }

  let of_string s =
    let tokens = Str.split (Str.regexp ": \\|, ") s in
    let name = tokens |> List.hd in
    let literals = tokens |> List.tl in
    let premises =
      BatList.take (List.length literals - 1) literals
      |> List.map (fun s ->
             String.sub s 4 (String.length s - 4) |> GroundedTuple.of_string)
    in
    let conclusion = BatList.last literals |> GroundedTuple.of_string in
    { name; conclusion; premises }

  let to_string s =
    Printf.sprintf "%s: %s%s" s.name
      (List.fold_left
         (fun s t -> s ^ "NOT " ^ GroundedTuple.to_string t ^ ", ")
         "" s.premises)
      (s.conclusion |> GroundedTuple.to_string)
end

module Node = struct
  type name = Tuple of GroundedTuple.t | Rule of GroundedRule.t

  type t = { name : name; comment : string }

  let is_tuple x = match x.name with Tuple _ -> true | _ -> false

  let is_rule x = match x.name with Tuple _ -> false | _ -> true

  let of_tuple ?(comment = "") s =
    { name = Tuple (GroundedTuple.of_string s); comment }

  let of_rule s = { name = Rule s; comment = "" }

  let to_rule n = match n.name with Rule s -> s | _ -> assert false

  let compare x y = Stdlib.compare x.name y.name

  let equal x y = x.name = y.name

  let hash x = Hashtbl.hash x.name

  let to_string_simple n =
    match n.name with
    | Tuple s -> GroundedTuple.to_string s
    | Rule s -> GroundedRule.to_string s

  let to_string n =
    match n.name with
    | Tuple s ->
        Format.sprintf "\"%s\n%s\"" (GroundedTuple.to_string s) n.comment
    | Rule s -> Format.sprintf "\"%s\n%s\"" (GroundedRule.to_string s) n.comment
end

module Network = Graph.Persistent.Digraph.ConcreteBidirectional (Node)

module SimplePrinter = struct
  include Network

  let graph_attributes _ = []

  let default_vertex_attributes _ = []

  let vertex_name x = Node.hash x |> string_of_int

  let vertex_attributes n =
    match n.Node.name with
    | Node.Tuple s when s.name = "Alarm" ->
        [
          `Fillcolor 0xff0000;
          `Style `Filled;
          `Label "";
          `Height 0.2;
          `Width 0.2;
        ]
    | Rule _ -> [ `Shape `Box; `Label ""; `Height 0.2; `Width 0.2 ]
    | _ -> [ `Label ""; `Height 0.2; `Width 0.2 ]

  let get_subgraph _ = None

  let default_edge_attributes _ = []

  let edge_attributes _ = []
end

module VerbosePrinter = struct
  include SimplePrinter

  let vertex_name = Node.to_string

  let vertex_attributes n =
    match n.Node.name with
    | Node.Tuple s when s.name = "Alarm" ->
        [ `Fillcolor 0xff0000; `Style `Filled; `Comment n.comment ]
    | Rule _ -> [ `Shape `Box; `Comment n.comment ]
    | _ -> [ `Comment n.comment ]
end

module Weight = struct
  type edge = Network.edge

  type t = int

  let weight _ = 1

  let compare = Stdlib.compare

  let add = ( + )

  let zero = 0
end

module Path = Graph.Path.Dijkstra (Network) (Weight)
module NodeMap = Map.Make (String)
include Network

let json_assoc name = function
  | Some (`Assoc l) -> Some (List.assoc name l)
  | _ -> None

let build_node_info node_file_name =
  let node_info_json = Yojson.Basic.from_file node_file_name in
  match json_assoc "nodes" (Some node_info_json) with
  | Some (`Assoc l) -> List.to_seq l |> NodeMap.of_seq
  | _ ->
      prerr_endline "ERRROR";
      NodeMap.empty

let make_comment node_info tuple =
  String.split_on_char '(' tuple
  |> BatList.last |> String.split_on_char ')' |> List.hd
  |> String.split_on_char ','
  |> List.fold_left
       (fun s cfgnode ->
         match NodeMap.find cfgnode node_info with
         | info -> (
             let loc = Some info |> json_assoc "loc" in
             match loc with
             | Some (`String loc) -> s ^ cfgnode ^ ": " ^ loc ^ "\n"
             | _ -> s )
         | exception Not_found -> s)
       ""

let build cons_file_name node_file_name =
  let node_info = build_node_info node_file_name in
  let ic = open_in cons_file_name in
  let rec read graph =
    match input_line ic with
    | s ->
        let literals = Str.split (Str.regexp ": \\|, ") s |> List.tl in
        let premises = BatList.take (List.length literals - 1) literals in
        let conclusion = BatList.last literals in
        let comment = make_comment node_info conclusion in
        let conclusion = Node.of_tuple ~comment conclusion in
        let rule = GroundedRule.of_string s |> Node.of_rule in
        let graph =
          List.fold_left
            (fun graph premise ->
              (* remove NOT *)
              let premise = String.sub premise 4 (String.length premise - 4) in
              let comment = make_comment node_info premise in
              let node = Node.of_tuple ~comment premise in
              Network.add_edge graph node rule)
            graph premises
        in
        Network.add_edge graph rule conclusion |> read
    | exception End_of_file -> graph
  in
  let graph = read Network.empty in
  close_in ic;
  graph

let rec to_grounded_rules : (Node.t * Node.t) list -> GroundedRule.t list =
  function
  | (_, n) :: t when Node.is_rule n -> Node.to_rule n :: to_grounded_rules t
  | _ :: t -> to_grounded_rules t
  | [] -> []

exception Best_effort_not_found

(* Suppose alarm1 is a false alarm and alarm2 is a true (victim) alarm *)
let compute_common_ancestor graph alarm1 alarm2 =
  let queue = Queue.create () in
  Queue.push alarm2 queue;
  let rec loop queue =
    let node =
      (* Catch error for debugging *)
      try Queue.pop queue
      with Queue.Empty ->
        prerr_endline
          ( "Error: No common ancestor between "
          ^ Node.to_string_simple alarm2
          ^ " and "
          ^ Node.to_string_simple alarm1 );
        raise Not_found
    in
    match Path.shortest_path graph node alarm1 |> fst with
    | edge_list2 ->
        let edge_list1 = Path.shortest_path graph node alarm2 |> fst in
        let graph =
          List.fold_left
            (fun graph (src, dst) -> Network.add_edge graph src dst)
            Network.empty edge_list1
        in
        let graph =
          List.fold_left
            (fun graph (src, dst) -> Network.add_edge graph src dst)
            graph edge_list2
        in
        (graph, edge_list2 |> to_grounded_rules |> List.rev)
    | exception Not_found ->
        let preds = try Network.pred graph node with _ -> [] in
        List.iter (fun n -> Queue.push n queue) preds;
        if Queue.length queue > 100 then raise Best_effort_not_found
        else loop queue
  in
  loop queue

let pp_tuple ?(space = false) fmt t =
  F.fprintf fmt "(";
  match t with
  | [ h ] -> F.fprintf fmt "%s)" h
  | h :: t ->
      F.fprintf fmt "%s" h;
      if space then List.iter (fun v -> F.fprintf fmt ", %s" v) t
      else List.iter (fun v -> F.fprintf fmt ",%s" v) t;
      F.fprintf fmt ")"
  | [] -> failwith "invalid tuple"

let rec read ic l =
  match input_line ic with
  | s -> String.split_on_char '\t' s :: l |> read ic
  | exception End_of_file -> l

let project_home =
  Sys.executable_name |> Filename.dirname |> Filename.dirname
  |> Filename.dirname |> Filename.dirname |> Filename.dirname

let run_souffle sparrow_out analysis_type bnet_dir datalog =
  let souffle_bin =
    Filename.concat project_home "souffle"
    |> Fun.flip Filename.concat "src"
    |> Fun.flip Filename.concat "souffle"
  in
  let analysis_dir = Filename.concat sparrow_out analysis_type in
  let datalog_dir = Filename.concat analysis_dir "datalog" in
  let datalog_file =
    if analysis_type = "interval" then
      Filename.concat bnet_dir "BufferOverflow.dl"
    else Filename.concat bnet_dir "IntegerOverflow.dl"
  in
  let oc = open_out datalog_file in
  let fmt = F.formatter_of_out_channel oc in
  Datalog.pp fmt datalog;
  close_out oc;
  let pid =
    Unix.create_process souffle_bin
      [| souffle_bin; "-F"; datalog_dir; "-D"; bnet_dir; datalog_file |]
      Unix.stdin Unix.stdout Unix.stderr
  in
  match Unix.waitpid [] pid |> snd with
  | Unix.WEXITED 0 -> ()
  | _ -> assert false

let generate_rule_prob_txt file_path datalog =
  let oc_prob = open_out file_path in
  let fmt_prob = F.formatter_of_out_channel oc_prob in
  Datalog.RuleSet.iter
    (fun rule ->
      let rule_name =
        String.sub rule.head.name 6 (String.length rule.head.name - 6)
      in
      if rule.prob <> 0.99 then
        F.fprintf fmt_prob "%s: %f\n%!" rule_name rule.prob)
    datalog.Datalog.derive_rules;
  close_out oc_prob

let generate_named_cons sparrow_out analysis_type bnet_dir datalog =
  let analysis_dir = Filename.concat sparrow_out analysis_type in
  let bnet_dir = Filename.concat analysis_dir bnet_dir in
  run_souffle sparrow_out analysis_type bnet_dir datalog;
  let oc_cons = open_out (Filename.concat bnet_dir "named_cons_all.txt") in
  let fmt_cons = F.formatter_of_out_channel oc_cons in
  let rule_prob_path = Filename.concat bnet_dir "rule-prob.txt" in
  generate_rule_prob_txt rule_prob_path datalog;
  Datalog.RuleSet.iter
    (fun rule ->
      let filename = Filename.concat bnet_dir (rule.head.name ^ ".csv") in
      let ic = open_in filename in
      let l = read ic [] in
      (* e.g., DUPath1 *)
      let rule_name =
        String.sub rule.head.name 6 (String.length rule.head.name - 6)
      in
      (* e.g., DUPath *)
      let tuple_name =
        if
          Str.string_match
            (Str.regexp "Deriv_\\([A-Za-z]+\\)[0-9]+")
            rule.head.name 0
        then Str.matched_group 1 rule.head.name
        else failwith "invalid rule name"
      in
      List.iter
        (fun l ->
          let subst =
            List.fold_left2
              (fun subst param arg x -> if x = param then arg else subst x)
              (fun x -> failwith ("unknown: " ^ Datalog.Variable.to_string x))
              rule.head.vars l
          in
          F.fprintf fmt_cons "%s: " rule_name;
          List.iter
            (fun t ->
              if not t.Datalog.Tuple.hidden then
                F.fprintf fmt_cons "NOT %s%a, "
                  ( if t.negation then "!" ^ t.Datalog.Tuple.name
                  else t.Datalog.Tuple.name )
                  (pp_tuple ~space:false)
                  (List.fold_left
                     (fun l var ->
                       match var with
                       | Datalog.Variable.Var _ -> l @ [ subst var ]
                       | _ -> l)
                     [] t.Datalog.Tuple.vars))
            rule.tail;
          let vars =
            BatList.take
              ( try Datalog.RelationMap.find tuple_name datalog.Datalog.outputs
                with Not_found ->
                  F.eprintf "ERROR: %s\n" tuple_name;
                  raise Not_found )
              l
          in
          F.fprintf fmt_cons "%s%a\n" tuple_name (pp_tuple ~space:false) vars)
        l;
      close_in ic)
    datalog.Datalog.derive_rules;
  close_out oc_cons
