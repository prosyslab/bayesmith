module P = Printf
module GraphVizSimple = Graph.Graphviz.Dot (BNet.SimplePrinter)
module GraphViz = Graph.Graphviz.Dot (BNet.VerbosePrinter)
module Node = BNet.Node

type env = { graph : BNet.t option; bnet_dir : string }

let cmd_exit () =
  flush_all ();
  exit 0

let cmd_search_common_ancestor env alarm1 alarm2 filename =
  prerr_string "Searching for a common ancestor...";
  let queue = Queue.create () in
  let alarm1 = Node.of_tuple alarm1 in
  Queue.push alarm1 queue;
  let t0 = Sys.time () in
  match env.graph with
  | Some graph ->
      let graph =
        try
          BNet.compute_common_ancestor graph alarm1 (Node.of_tuple alarm2)
          |> fst
        with BNet.Best_effort_not_found ->
          prerr_endline "\nDone best effort but not found";
          exit 1
      in
      prerr_endline ("Done (" ^ string_of_float (Sys.time () -. t0) ^ ")");
      let oc = open_out (filename ^ ".dot") in
      GraphViz.output_graph oc graph;
      close_out oc;
      Unix.create_process "dot"
        [| "dot"; "-Tsvg"; "-o"; filename ^ ".svg"; filename ^ ".dot" |]
        Unix.stdin Unix.stdout Unix.stderr
      |> ignore;
      Unix.wait () |> ignore
  | None -> prerr_endline "Bayesian Network has not yet built"

let cmd_build env typ =
  let cons_file_name =
    if typ = "" then Filename.concat env.bnet_dir "named_cons_all.txt"
    else Filename.concat env.bnet_dir ("named_cons_all.txt" ^ "." ^ typ)
  in
  let sparrow_out = Filename.dirname env.bnet_dir |> Filename.dirname in
  let node_file_name = Filename.concat sparrow_out "node.json" in
  prerr_string "Build graph...";
  let t0 = Sys.time () in
  let graph = BNet.build cons_file_name node_file_name in
  prerr_endline ("Done (" ^ string_of_float (Sys.time () -. t0) ^ ")");
  { env with graph = Some graph }

let cmd_store env filename =
  let oc = open_out filename in
  Marshal.to_channel oc env [];
  close_out oc

let cmd_load filename =
  let ic = open_in filename in
  let env = Marshal.from_channel ic in
  close_in ic;
  env

module NodeSet = Set.Make (Node)

let rec compute_all_ancestors size graph alarm queue nodeset =
  if Queue.is_empty queue then
    BNet.fold_vertex
      (fun n g -> if NodeSet.mem n nodeset then g else BNet.remove_vertex g n)
      graph graph
  else if NodeSet.cardinal nodeset > size then
    let _ = P.eprintf "WARN: too many dependent nodes (> 100)\n" in
    BNet.fold_vertex
      (fun n g -> if NodeSet.mem n nodeset then g else BNet.remove_vertex g n)
      graph graph
  else
    let node = Queue.pop queue in
    let nodeset = NodeSet.add node nodeset in
    match BNet.pred graph node with
    | node_list ->
        List.fold_left
          (fun nodeset n ->
            if NodeSet.mem n nodeset then nodeset
            else (
              Queue.push n queue;
              NodeSet.add n nodeset ))
          nodeset node_list
        |> compute_all_ancestors size graph alarm queue
    | exception Not_found ->
        compute_all_ancestors size graph alarm queue nodeset

let cmd_single env alarm size filename =
  prerr_string "Searching for all ancestors...";
  let queue = Queue.create () in
  let alarm = Node.of_tuple alarm in
  Queue.push alarm queue;
  let t0 = Sys.time () in
  match env.graph with
  | Some graph ->
      let graph = compute_all_ancestors size graph alarm queue NodeSet.empty in
      prerr_endline ("Done (" ^ string_of_float (Sys.time () -. t0) ^ ")");
      let oc = open_out (filename ^ ".dot") in
      GraphViz.output_graph oc graph;
      close_out oc;
      Unix.create_process "dot"
        [| "dot"; "-Tsvg"; "-o"; filename ^ ".svg"; filename ^ ".dot" |]
        Unix.stdin Unix.stdout Unix.stderr
      |> ignore;
      Unix.wait () |> ignore
  | None -> prerr_endline "Bayesian Network has not yet built"

let cmd_all env filename =
  match env.graph with
  | Some graph ->
      let oc = open_out (filename ^ ".dot") in
      GraphVizSimple.output_graph oc graph;
      close_out oc;
      Unix.create_process "dot"
        [| "dot"; "-Tsvg"; "-o"; filename ^ ".svg"; filename ^ ".dot" |]
        Unix.stdin Unix.stdout Unix.stderr
      |> ignore;
      Unix.wait () |> ignore
  | None -> prerr_endline "Bayesian Network has not yet built"

let cmd_info env =
  match env.graph with
  | Some graph -> P.printf "#Nodes: %d\n" (BNet.nb_vertex graph)
  | None -> P.printf "Bayesian Network has not yet built"

let cmd_help () =
  P.printf
    "    build                               : build graph\n\
    \    info                                : statistics\n\
    \    store [filename]                    : store graph\n\
    \    load [filename]                     : load graph\n\
    \    common [alarm1] [alarm2] [filename] : common ancestor\n\
    \    single [alarm] [filename]           : dependency of a single alarm\n\
    \    all [filename]                      : whole graph (experimental)\n"

let repl env cmd =
  let components = Str.split (Str.regexp "[ \t]+") cmd in
  match components with
  | [ "build" ] -> cmd_build env ""
  | [ "build"; suffix ] -> cmd_build env suffix
  | [ "store"; filename ] ->
      cmd_store env filename;
      env
  | [ "load"; filename ] -> cmd_load filename
  | [ "all"; filename ] ->
      cmd_all env filename;
      env
  | [ "single"; alarm; filename ] ->
      cmd_single env alarm 100 filename;
      env
  | [ "single"; alarm; size; filename ] ->
      cmd_single env alarm (int_of_string size) filename;
      env
  | [ "common"; alarm1; alarm2; filename ] ->
      cmd_search_common_ancestor env alarm1 alarm2 filename;
      env
  | [ "info" ] ->
      cmd_info env;
      env
  | [ "help" ] ->
      cmd_help ();
      env
  | [ "exit" ] -> cmd_exit ()
  | _ ->
      P.eprintf "Invalid command\nTry help";
      env

let history_filename = ".visualizer-history.txt"

let initialize () =
  LNoise.history_load ~filename:history_filename |> ignore;
  LNoise.history_set ~max_length:100 |> ignore;
  LNoise.set_completion_callback (fun line_so_far ln_completions ->
      if line_so_far <> "" && line_so_far.[0] = 'c' then
        [ "common" ] |> List.iter (LNoise.add_completion ln_completions))

let rec user_input prompt env cb =
  match LNoise.linenoise prompt with
  | None -> env
  | Some v ->
      let env = repl env v in
      flush_all ();
      cb v;
      user_input prompt env cb
  | exception Sys.Break -> cmd_exit ()

let main argv =
  let bnet_dir = argv.(1) in
  initialize ();
  let env = { graph = None; bnet_dir } in
  (fun from_user ->
    LNoise.history_add from_user |> ignore;
    LNoise.history_save ~filename:history_filename |> ignore)
  |> user_input "visualizer> " env

let _ = main Sys.argv
