module F = Format
module P = Printf

module BNetDict = struct
  include Map.Make (String)

  let pp fmt dict = iter (fun k v -> F.fprintf fmt "%d: %s\n" v k) dict
end

module QuerySet = Set.Make (String)

type env = {
  ic : in_channel;
  oc : out_channel;
  bnet_dict : int BNetDict.t;
  base_queries : QuerySet.t;
  oracle_queries : QuerySet.t;
  old_labels : QuerySet.t;
  labelled_tuples : bool BNetDict.t;
  suffix : string;
}

let exec_wrapper_command ic oc cmd =
  P.eprintf "Driver to wrapper: %s\n" cmd;
  output_string oc (cmd ^ "\n");
  flush_all ();
  (* TODO: handle LIBDAI EXCEPTION *)
  let response = input_line ic in
  P.eprintf "Wrapper to driver: %s\n" response;
  flush_all ();
  response

let cmd_belief_propagation ?(tolerance = 1e-6) ?(min_iters = 500)
    ?(max_iters = 1000) ?(hist_length = 100) env =
  if tolerance < 0.0 || tolerance > 1.0 then (
    P.printf "tolerance must be between 0 and 1";
    None )
  else if hist_length < 0 || hist_length > min_iters then (
    P.printf "hist_length must be between 0 and min_iters";
    None )
  else
    P.sprintf "BP %f %d %d %d" tolerance min_iters max_iters hist_length
    |> exec_wrapper_command env.ic env.oc
    |> fun x ->
    P.printf "BP completed\n";
    Some x

let cmd_query env tuple =
  try
    let cmd = F.sprintf "Q %d" (BNetDict.find tuple env.bnet_dict) in
    exec_wrapper_command env.ic env.oc cmd |> float_of_string |> Option.some
  with Not_found ->
    P.eprintf "%s not found\n" tuple;
    None

let cmd_observe env tuple boolean =
  let cmd = F.sprintf "O %d %b" (BNetDict.find tuple env.bnet_dict) boolean in
  exec_wrapper_command env.ic env.oc cmd |> ignore;
  P.printf "%s\n" cmd;
  { env with labelled_tuples = BNetDict.add tuple boolean env.labelled_tuples }

let int_of_bool = function true -> 1 | false -> -1

let get_ranked_alarms env =
  let get_label_int t =
    if BNetDict.mem t env.labelled_tuples then
      BNetDict.find t env.labelled_tuples |> int_of_bool
    else 0
  in
  QuerySet.fold
    (fun t l -> (t, cmd_query env t |> Option.get) :: l)
    env.base_queries []
  |> List.sort (fun (x, px) (y, py) ->
         compare
           (-get_label_int x, -1.0 *. px, x)
           (-get_label_int y, -1.0 *. py, y))

let cmd_print env outfile =
  let alarm_list = get_ranked_alarms env in
  let fc = open_out outfile in
  output_string fc "Rank\tConfidence\tGround\tLabel\tTuple\n";
  List.fold_left
    (fun idx (t, confidence) ->
      let ground =
        if QuerySet.mem t env.oracle_queries then "TrueGround"
        else "FalseGround"
      in
      let label =
        if BNetDict.mem t env.labelled_tuples |> not then "Unlabelled"
        else if BNetDict.find t env.labelled_tuples then "PosLabel"
        else "NegLabel"
      in
      P.sprintf "%d\t%f\t%s\t%s\t%s\n" idx confidence ground label t
      |> output_string fc;
      idx + 1)
    1 alarm_list
  |> ignore;
  close_out fc

let cmd_exit env =
  output_string env.oc "exit\n";
  flush_all ()

let get_inversion_count env alarms =
  List.fold_left
    (fun (num_inversion, num_false) (t, _) ->
      if QuerySet.mem t env.oracle_queries then
        (num_inversion + num_false, num_false)
      else (num_inversion, num_false + 1))
    (0, 0) alarms
  |> fst

let cmd_carousel env problem_dir =
  cmd_belief_propagation env |> ignore;
  let combined_dir = "bingo_combined-" ^ env.suffix in
  let init_file = Filename.concat combined_dir "init.out" in
  Filename.concat problem_dir init_file |> cmd_print env;
  (* TODO: one shot *)
  (* TODO: oldLabel *)
  let num_of_masked = 0 in
  P.eprintf "Carousel start! %d ararms masked\n" num_of_masked;
  let stats_oc =
    Filename.concat problem_dir ("bingo_stats-" ^ env.suffix ^ ".txt")
    |> open_out
  in
  output_string stats_oc
    "Tuple\tConfidence\tGround\tNumTrue\tNumFalse\tFraction\tInversionCount\tYetToConvergeFraction\tTime(s)\n";
  let rec loop t0 num_of_true num_of_false env =
    let yet_to_conv =
      cmd_belief_propagation env |> Option.get |> float_of_string
    in
    let ranked_alarm_list = get_ranked_alarms env in
    let unlabelled_alarms =
      List.filter
        (fun (t, _) -> BNetDict.mem t env.labelled_tuples |> not)
        ranked_alarm_list
    in
    match unlabelled_alarms with
    | [] -> ()
    | _ when num_of_true = QuerySet.cardinal env.oracle_queries -> ()
    | (t, conf) :: _ ->
        let num_of_true, num_of_false =
          if QuerySet.mem t env.oracle_queries then
            (num_of_true + 1, num_of_false)
          else (num_of_true, num_of_false + 1)
        in
        let fraction =
          float_of_int num_of_true
          /. (float_of_int num_of_true +. float_of_int num_of_false)
        in
        let ground =
          if QuerySet.mem t env.oracle_queries then "TrueGround"
          else "FalseGround"
        in
        let inv_count = get_inversion_count env ranked_alarm_list in
        let time = Unix.time () -. t0 |> int_of_float in
        P.sprintf "%s\t%f\t%s\t%d\t%d\t%f\t%d\t%f\t%d\n" t conf ground
          num_of_true num_of_false fraction inv_count yet_to_conv time
        |> output_string stats_oc;
        let out_file_name =
          Filename.concat combined_dir
            ((num_of_true + num_of_false - 1 |> string_of_int) ^ ".out")
          |> Filename.concat problem_dir
        in
        cmd_print env out_file_name;
        cmd_observe env t (QuerySet.mem t env.oracle_queries)
        |> loop (Unix.time ()) num_of_true num_of_false
  in
  loop (Unix.time ()) 0 0 env

let cmd_factor_marginal env clause_idx val_idx =
  let cmd = F.sprintf "FQ %s %s" clause_idx val_idx in
  exec_wrapper_command env.ic env.oc cmd |> float_of_string |> Option.some

let repl env cmd =
  let components = Str.split (Str.regexp "[ \t]+") cmd in
  match components with
  | [ "BP" ] ->
      cmd_belief_propagation env |> ignore;
      Some env
  | [ "BP"; tolerance; min_iters; max_iters; hist_length ] ->
      let tolerance = float_of_string tolerance in
      let min_iters = int_of_string min_iters in
      let max_iters = int_of_string max_iters in
      let hist_length = int_of_string hist_length in
      cmd_belief_propagation ~tolerance ~min_iters ~max_iters ~hist_length env
      |> ignore;
      Some env
  | [ "Q"; tuple ] -> (
      match cmd_query env tuple with
      | Some prob ->
          P.printf "%s %f\n" tuple prob;
          Some env
      | None -> Some env )
  | [ "O"; tuple; boolean ] ->
      cmd_observe env tuple (bool_of_string boolean) |> Option.some
  | [ "P"; outfile ] ->
      cmd_print env outfile;
      Some env
  | [ "exit" ] -> None
  | [ "AC"; problem_dir ] ->
      cmd_carousel env problem_dir;
      None
  | [ "FQ"; clause_idx; val_idx ] -> (
      match cmd_factor_marginal env clause_idx val_idx with
      | Some prob ->
          P.printf "%f\n" prob;
          Some env
      | None -> None )
  | [] -> Some env
  | _ ->
      P.eprintf "Invalid command\n";
      Some env

let rec user_input prompt env cb =
  match LNoise.linenoise prompt with
  | None -> ()
  | Some v -> (
      let env' = repl env v in
      flush_all ();
      cb v;
      match env' with
      | Some env -> user_input prompt env cb
      | None -> cmd_exit env )
  | exception Sys.Break -> cmd_exit env

let populate_bnet dict_file_name =
  let oc = open_in dict_file_name in
  let rec read dict =
    match input_line oc with
    | s -> (
        match String.split_on_char ':' s with
        | [ id; node ] ->
            BNetDict.add
              (String.sub node 1 (String.length node - 1))
              (int_of_string id) dict
            |> read
        | _ -> failwith "Invalid format" )
    | exception End_of_file -> dict
  in
  read BNetDict.empty

let read_queries filename =
  let oc = open_in filename in
  let rec read queries =
    match input_line oc with
    | s -> QuerySet.add s queries |> read
    | exception End_of_file -> queries
  in
  read QuerySet.empty

let initialize () =
  LNoise.history_load ~filename:"history.txt" |> ignore;
  LNoise.history_set ~max_length:100 |> ignore;
  LNoise.set_completion_callback (fun line_so_far ln_completions ->
      if line_so_far <> "" && line_so_far.[0] = 'h' then
        [ "Hey"; "Howard"; "Hughes"; "Hocus" ]
        |> List.iter (LNoise.add_completion ln_completions))

let main argv =
  let dict_file_name = argv.(1) in
  let fg_file_name = argv.(2) in
  let base_query_file_name = argv.(3) in
  let oracle_query_file_name = argv.(4) in
  let wrapper_executable = argv.(5) in
  let old_labels_file_name = argv.(7) in
  let suffix = argv.(8) in
  let bnet_dict = populate_bnet dict_file_name in
  let base_queries = read_queries base_query_file_name in
  let oracle_queries = read_queries oracle_query_file_name in
  let old_labels = read_queries old_labels_file_name in
  assert (QuerySet.subset oracle_queries base_queries);
  P.eprintf "Populated %d oracle queries\n" (QuerySet.cardinal oracle_queries);
  P.eprintf "Populated %d base queries\n" (QuerySet.cardinal base_queries);
  P.eprintf "Loaded %d old labels\n" (QuerySet.cardinal old_labels);
  flush_all ();
  (* parent to child *)
  let fd_in1, fd_out1 = Unix.pipe () in
  (* child to parent *)
  let fd_in2, fd_out2 = Unix.pipe () in
  match
    Unix.create_process wrapper_executable
      [| wrapper_executable; "--no-history"; fg_file_name |]
      fd_in1 fd_out2 Unix.stderr
  with
  | 0 ->
      (* child *)
      ()
  | pid ->
      (* parent *)
      let env =
        {
          ic = Unix.in_channel_of_descr fd_in2;
          oc = Unix.out_channel_of_descr fd_out1;
          bnet_dict;
          base_queries;
          oracle_queries;
          old_labels;
          labelled_tuples = BNetDict.empty;
          suffix;
        }
      in
      initialize ();
      (fun from_user ->
        LNoise.history_add from_user |> ignore;
        LNoise.history_save ~filename:"history.txt" |> ignore)
      |> user_input "bingo> " env;
      Unix.waitpid [ Unix.WNOHANG; Unix.WUNTRACED ] pid |> ignore

let _ = main Sys.argv
