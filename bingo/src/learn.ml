module F = Format
module P = Printf
module GTuple = BNet.GroundedTuple
module GRule = BNet.GroundedRule
module Rule = Datalog.Rule
module RuleSet = Datalog.RuleSet
module Tuple = Datalog.Tuple

(* Options *)
let reuse = ref false

let min_v = ref 0.0

let alpha = ref 0.99

let max_epoch = ref 100

let out_dir = ref "learn-out"

let is_debug = ref false

let analysis_type = ref "interval"

let min_improved_ratio = ref 0.5

let dl_from = ref ""

let rule_prob_from = ref ""

let is_parallel = ref false

let is_test = ref false

let force_rerun = ref false

let use_baseline = ref false

let baseline_iters = ref (-1)

let baseline_iters_lst = ref []

let targets = ref []

(* Default constants *)
let prob = 0.99

let weights = [ 1.0 ]

let alarm_array_exp = "AlarmArrayExp"

let alarm_deref_exp = "AlarmDerefExp"

let alarm_strcpy = "AlarmStrcpy"

let alarm_memchr = "AlarmMemchr"

let alarm_strncmp = "AlarmStrncmp"

let alarm_buffer_overrun_lib = "AlarmBufferOverrunLib"

let alarm_div_exp = "AlarmDivExp"

let alarm_memcpy = "AlarmMemcpy"

let alarm_memmove = "AlarmMemmove"

let alarm_strcat = "AlarmStrcat"

let alarm_strncpy = "AlarmStrncpy"

let alarm_alloc_size = "AlarmAllocSize"

let alarm_printf = "AlarmPrintf"

let alarm_taint = "AlarmTaint"

let assign = "Assign"

let loophead = "LoopHead"

let libcall = "LibCall"

let assume = "Assume"

let call = "Call"

let unop = "UnOpExp"

let binop = "BinOpExp"

let lval_exp = "LvalExp"

let cast_exp = "CastExp"

let field = "Field"

let b_and = "BAnd"

let b_not = "BNot"

let b_or = "BOr"

let b_xor = "BXor"

let div = "Div"

let eq = "Eq"

let ne = "Ne"

let ge = "Ge"

let gt = "Gt"

let le = "Le"

let lt = "Lt"

let l_and = "LAnd"

let l_not = "LNot"

let l_or = "LOr"

let modulo = "Mod"

let mult = "Mult"

let neg = "Neg"

let minus_a = "Minus_A"

let minus_pi = "Minus_PI"

let minus_pp = "Minus_PP"

let plus_a = "Plus_A"

let plus_pi = "Plus_PI"

let shift_l = "ShiftLt"

let shift_r = "ShiftRt"

let string_of_current_time () =
  Unix.time () |> Unix.localtime |> fun tm ->
  P.sprintf "%d%02d%02d-%02d:%02d:%02d" (1900 + tm.tm_year) (tm.tm_mon + 1)
    tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec

let timestamp = ref (string_of_current_time ())

let target = ref ""

let ( $> ) : 'a -> ('a -> unit) -> 'a =
 fun x f ->
  f x;
  x

(* Basic paths *)
let project_home =
  Sys.executable_name |> Filename.dirname |> Filename.dirname
  |> Filename.dirname |> Filename.dirname |> Filename.dirname

let benchmark_home = Filename.concat project_home "benchmarks"

let run_script_path = Filename.concat project_home "bin/run.py"

let devnull = Unix.openfile "/dev/null" [ Unix.O_WRONLY ] 0o644

let not_found = "NOT_FOUND"

let interval_benchmarks =
  [
    "wget/1.12";
    "readelf/2.24";
    "grep/2.19";
    "sed/4.3";
    "patch/2.7.1";
    "sort/7.2";
    "tar/1.28";
    "cflow/1.5";
    "bc/1.06";
    "fribidi/1.0.7";
    "gzip/1.2.4a";
  ]

let taint_benchmarks =
  [
    "a2ps/4.14";
    "optipng/0.5.3";
    "shntool/3.0.5";
    "urjtag/0.8";
    "autotrace/0.31.1";
    "sam2p/0.49.4";
    "latex2rtf/2.1.1";
    "jhead/3.0.0";
    "sdop/0.61";
  ]

let get_benchmark_pool () =
  match !analysis_type with
  | "interval" -> interval_benchmarks
  | "taint" -> taint_benchmarks
  | _ -> failwith "Unsupported analysis type"

let leave_one_out target_benchs =
  let num_target_benchs = List.length target_benchs in
  let benchmark_pool = get_benchmark_pool () in
  let filtered =
    List.filter
      (fun b ->
        List.for_all
          (fun target_bench ->
            let len = String.length target_bench in
            let b_name =
              try String.sub b 0 len with Invalid_argument _ -> "NO_MATCH"
            in
            b_name <> target_bench)
          target_benchs)
      benchmark_pool
  in
  let num_all = List.length benchmark_pool in
  let num_filtered = List.length filtered in
  if num_all - num_filtered = num_target_benchs then filtered
  else failwith (String.concat " " target_benchs ^ " not in benchmark list")

let get_test_benchmark target_benchs =
  let num_target_benchs = List.length target_benchs in
  let benchmark_pool = get_benchmark_pool () in
  let filtered =
    List.filter
      (fun b ->
        List.exists
          (fun target_bench ->
            let len = String.length target_bench in
            let b_name =
              try String.sub b 0 len with Invalid_argument _ -> "NO_MATCH"
            in
            b_name = target_bench)
          target_benchs)
      benchmark_pool
  in
  let num_filtered = List.length filtered in
  if num_filtered = num_target_benchs then filtered
  else failwith (String.concat " " target_benchs ^ " not in benchmark list")

(* Logging *)
let log_file = ref None

let log_formatter = ref None

let log fmt =
  match !log_formatter with
  | Some log_formatter ->
      F.fprintf log_formatter "[%s] " (string_of_current_time ());
      F.kfprintf
        (fun log_formatter ->
          F.fprintf log_formatter "\n";
          F.pp_print_flush log_formatter ())
        log_formatter fmt
  | None -> failwith "Cannot open logfile"

(* Main data types *)
module VCurve = struct
  type t = {
    benchmark : string;
    bnet_dir : string;
    false_alarm : string;
    true_alarm : string;
    height : int;
    height_ratio : float;
  }

  let empty =
    {
      benchmark = "";
      bnet_dir = "";
      false_alarm = "";
      true_alarm = "";
      height = -1;
      height_ratio = -1.0;
    }

  let to_string vc =
    P.sprintf
      "{ benchmark: %s, false: %s, true: %s, height: %d, height_ratio: %f }"
      vc.benchmark vc.false_alarm vc.true_alarm vc.height vc.height_ratio
end

module RuleSetCache = Map.Make (RuleSet)

type environment = {
  current_timestamp : string;
  current_v_curve : VCurve.t;
  current_rules : RuleSet.t;
  best_timestamp : string;
  best_iters : int;
  best_iters_lst : int list;
  best_rules : RuleSet.t;
  total_num_alarms : int;
  total_num_bugs : int;
  benchmarks : string list;
  epoch : int;
  epoch_v_curve : int;
  epoch_rule : int;
  epoch_tuple : int;
  history : (string * int) list;
  (* timestamp * iters *)
  ruleset_cache : int RuleSetCache.t;
}

let empty_env =
  {
    current_timestamp = "";
    current_v_curve = VCurve.empty;
    current_rules = RuleSet.empty;
    best_timestamp = "";
    best_iters = -1;
    best_iters_lst = [];
    best_rules = RuleSet.empty;
    total_num_alarms = -1;
    total_num_bugs = -1;
    benchmarks = [];
    epoch = 0;
    epoch_v_curve = 0;
    epoch_rule = 0;
    epoch_tuple = 0;
    history = [];
    ruleset_cache = RuleSetCache.empty;
  }

let string_of_environment env =
  F.sprintf
    "{ current_timestamp: %s, best_timestamp: %s, best_iters: %d / %d (%.2f), \
     bugs: %d / %d }"
    env.current_timestamp env.best_timestamp env.best_iters env.total_num_alarms
    (float_of_int env.best_iters /. float_of_int env.total_num_alarms)
    env.total_num_bugs env.total_num_alarms

module Evaluation = struct
  type t = {
    total_iters : int;
    quality : float;
    mean : float;
    stddev : float;
    diff_benchmarks : (string * int) list;
    improved_ratio : float;
    env : environment;
  }

  let get_num_iters_lst env =
    List.map
      (fun bench ->
        let bench_dir = Filename.concat benchmark_home bench in
        let combined_dir =
          Filename.concat bench_dir
            ( "sparrow-out/" ^ !analysis_type ^ "/bingo_combined-"
            ^ env.current_timestamp )
        in
        let num_iter =
          Sys.readdir combined_dir |> Array.to_list
          |> List.filter (fun x -> x <> "init.out" && x <> ".done")
          |> List.length
        in
        log "- Test score of %s : %d" bench num_iter;
        num_iter)
      env.benchmarks

  let run env =
    let num_bench = List.length env.benchmarks |> float_of_int in
    let current_num_iters_lst = get_num_iters_lst env in
    let total_iters = List.fold_left ( + ) 0 current_num_iters_lst in
    let criteria_lst =
      if !use_baseline then !baseline_iters_lst else env.best_iters_lst
    in
    if env.best_iters_lst = [] then (
      log "# Current total iters: %d" total_iters;
      {
        total_iters;
        quality = 0.0;
        mean = 0.0;
        stddev = 0.0;
        diff_benchmarks = [];
        improved_ratio = 0.0;
        env;
      } )
    else
      let diff_lst =
        List.fold_left2
          (fun acc a b -> (b - a) :: acc)
          [] criteria_lst current_num_iters_lst
      in
      let diff_sum = List.fold_left ( + ) 0 diff_lst in
      let mean = float_of_int diff_sum /. num_bench in
      let squared_diff_sum =
        List.fold_left
          (fun s n -> s +. ((mean -. float_of_int n) ** 2.))
          0. diff_lst
      in
      let var = squared_diff_sum /. num_bench in
      let stddev = sqrt var in
      let quality = mean /. stddev in
      let rec loop benchmarks old_stat_lst new_stat_lst =
        match (benchmarks, old_stat_lst, new_stat_lst) with
        | h1 :: t1, h2 :: t2, h3 :: t3 ->
            let diff = h3 - h2 in
            log "%s: %d -> %d (%d)" h1 h2 h3 diff;
            (h1, diff) :: loop t1 t2 t3
        | _ -> []
      in
      let diff_benchmarks =
        loop env.benchmarks criteria_lst current_num_iters_lst
      in
      let num_improved =
        List.filter (fun (_, d) -> d < 0) diff_benchmarks
        |> List.length |> float_of_int
      in
      let num_unchanged =
        List.filter (fun (_, d) -> d = 0) diff_benchmarks
        |> List.length |> float_of_int
      in
      let num_changed = num_bench -. num_unchanged in
      let improved_ratio =
        if num_changed = 0. then 1. else num_improved /. num_changed
      in
      log "%s" env.current_timestamp;
      log "# Last best iters: %d" env.best_iters;
      log "# Current total iters: %d" total_iters;
      log "- mean: %f" mean;
      log "- stddev: %f" stddev;
      log "- quality: %f" quality;
      log "- improved ratio: %f" improved_ratio;
      {
        total_iters;
        quality;
        mean;
        stddev;
        diff_benchmarks;
        improved_ratio;
        env;
      }

  let run_weights envs =
    let results =
      List.map run envs |> List.sort (fun a b -> a.total_iters - b.total_iters)
    in
    List.nth results 0
end

module StringSet = Set.Make (String)
module FeatureMap = Map.Make (String) (* String -> TupleMap *)

module TupleMap = Map.Make (String) (* String -> String list *)

type features = {
  (* alarm features *)
  alarm_array_exp : StringSet.t * int;
  alarm_deref_exp : StringSet.t * int;
  alarm_strcpy : StringSet.t * int;
  alarm_strncmp : StringSet.t * int;
  alarm_memchr : StringSet.t * int;
  alarm_buffer_overrun_lib : StringSet.t * int;
  alarm_div_exp : StringSet.t * int;
  alarm_memcpy : StringSet.t * int;
  alarm_memmove : StringSet.t * int;
  alarm_strcat : StringSet.t * int;
  alarm_strncpy : StringSet.t * int;
  alarm_alloc_size : StringSet.t * int;
  alarm_printf : StringSet.t * int;
  alarm_taint : StringSet.t * int;
  (* node features *)
  assign : StringSet.t * int;
  loophead : StringSet.t * int;
  libcall : StringSet.t * int;
  assume : StringSet.t * int;
  call : StringSet.t * int;
  (* exp features *)
  unop : StringSet.t * int;
  binop : StringSet.t * int;
  lval_exp : StringSet.t * int;
  cast_exp : StringSet.t * int;
  (* lval features *)
  field : StringSet.t * int;
  (* operator features *)
  b_and : StringSet.t * int;
  b_not : StringSet.t * int;
  b_or : StringSet.t * int;
  b_xor : StringSet.t * int;
  div : StringSet.t * int;
  eq : StringSet.t * int;
  ne : StringSet.t * int;
  ge : StringSet.t * int;
  gt : StringSet.t * int;
  le : StringSet.t * int;
  lt : StringSet.t * int;
  l_and : StringSet.t * int;
  l_not : StringSet.t * int;
  l_or : StringSet.t * int;
  modulo : StringSet.t * int;
  mult : StringSet.t * int;
  neg : StringSet.t * int;
  minus_a : StringSet.t * int;
  minus_pi : StringSet.t * int;
  minus_pp : StringSet.t * int;
  plus_a : StringSet.t * int;
  plus_pi : StringSet.t * int;
  shift_l : StringSet.t * int;
  shift_r : StringSet.t * int;
}

let hidden_tuples = [ "SparrowAlarm" ] |> StringSet.of_list

let base_dir_of bench =
  Filename.concat (Filename.concat benchmark_home bench) "sparrow-out/"
  |> Fun.flip Filename.concat (!analysis_type ^ "/")

let find_reusable_timestamp current_rule_instance bench =
  if !force_rerun then None
  else
    let base_dir = base_dir_of bench in
    Sys.readdir base_dir |> Array.to_list
    |> List.filter (fun s ->
           let dir = Filename.concat base_dir s in
           let { Unix.st_kind; _ } = Unix.lstat dir in
           st_kind = S_DIR
           && String.length s > 5
           && String.sub s 0 (String.length "bnet-") = "bnet-")
    |> List.find_opt (fun dir ->
           let bnet_dir = Filename.concat base_dir dir in
           let dl_file =
             if !analysis_type = "interval" then
               Filename.concat bnet_dir "BufferOverflow.dl"
             else if !analysis_type = "taint" then
               Filename.concat bnet_dir "IntegerOverflow.dl"
             else assert false
           in
           let prob_file = Filename.concat bnet_dir "rule-prob.txt" in
           let combined_dir =
             Filename.concat base_dir
               ("bingo_combined" ^ String.sub dir 4 (String.length dir - 4))
           in
           let done_file = Filename.concat combined_dir ".done" in
           if
             Sys.file_exists done_file && Sys.file_exists dl_file
             && Sys.file_exists prob_file
           then
             let datalog = Datalog.of_file dl_file prob_file in
             Datalog.eq current_rule_instance datalog
           else false)

(* Generate named_cons_all before execution of run.py *)
let generate_named_cons env current_rule_instance =
  log "Generate named_cons_all started";
  prerr_endline
    ("[" ^ env.current_timestamp ^ "] Generating named_cons_all started");
  List.iter
    (fun bench ->
      match find_reusable_timestamp current_rule_instance bench with
      | Some dir ->
          log "- Reusable named_cons_all of %s found (copy %s to bnet-%s)" bench
            dir env.current_timestamp;
          let base_dir = base_dir_of bench in
          let src_dir = Filename.concat base_dir dir in
          let dst_dir =
            Filename.concat base_dir ("bnet-" ^ env.current_timestamp)
          in
          if src_dir = dst_dir then () else Unix.symlink src_dir dst_dir
      | None ->
          log "- Generate named_cons_all of %s" bench;
          let dir =
            Filename.concat
              (Filename.concat benchmark_home bench)
              "sparrow-out/"
          in
          let bnet_dir = "bnet-" ^ env.current_timestamp in
          (* Create bnet_dir where named_cons_all shall be generated *)
          let cid =
            Unix.create_process "mkdir"
              [|
                "mkdir";
                "-p";
                Filename.concat dir (!analysis_type ^ "/" ^ bnet_dir);
              |]
              devnull devnull devnull
          in
          Unix.waitpid [] cid |> snd |> fun exit_status ->
          if exit_status = Unix.WEXITED 0 then ()
          else
            prerr_endline
              ("Error: mkdir failed for " ^ bnet_dir ^ " of " ^ bench);
          BNet.generate_named_cons dir !analysis_type bnet_dir
            current_rule_instance)
    env.benchmarks

let run_bingo env current_rule_instance =
  log "Run Bingo for all benchmarks";
  prerr_endline
    ("[" ^ env.current_timestamp ^ "] Run Bingo for all benchmarks started");
  env.benchmarks
  |> List.map (fun bench ->
         match find_reusable_timestamp current_rule_instance bench with
         | Some dir ->
             let combined_dir =
               "bingo_combined" ^ String.sub dir 4 (String.length dir - 4)
             in
             log "- Reusable Bingo run of %s found" bench;
             let base_dir = base_dir_of bench in
             let src_dir = Filename.concat base_dir combined_dir in
             let dst_dir =
               Filename.concat base_dir
                 ("bingo_combined-" ^ env.current_timestamp)
             in
             if src_dir = dst_dir then None
             else (
               Unix.symlink src_dir dst_dir;
               None )
         | None ->
             log "- Run %s" bench;
             let cid =
               Unix.create_process run_script_path
                 [|
                   run_script_path;
                   "rank";
                   "--skip-generate-named-cons";
                   "--timestamp";
                   env.current_timestamp;
                   "--alpha";
                   string_of_float !alpha;
                   Filename.concat benchmark_home bench;
                 |]
                 Unix.stdin devnull devnull
             in
             Some (cid, bench))
  |> List.iter (function
       | Some (pid, bench) ->
           Unix.waitpid [] pid |> snd |> fun exit_status ->
           if exit_status = Unix.WEXITED 0 then (
             let base_dir = base_dir_of bench in
             let combined_dir =
               Filename.concat base_dir
                 ("bingo_combined-" ^ env.current_timestamp)
             in
             let bnet_dir =
               Filename.concat base_dir ("bnet-" ^ env.current_timestamp)
             in
             let combined_done_file = Filename.concat combined_dir ".done" in
             let bnet_done_file = Filename.concat bnet_dir ".done" in
             let oc = open_out bnet_done_file in
             P.fprintf oc "%s" env.current_timestamp;
             close_out oc;
             let oc = open_out combined_done_file in
             P.fprintf oc "%s" env.current_timestamp;
             close_out oc )
           else prerr_endline ("Error: Bingo failed for " ^ bench)
       | None -> ())

let run_all env =
  let dl_file =
    Filename.concat !out_dir ("rule-" ^ env.current_timestamp ^ ".dl")
  in
  let prob_txt_file =
    Filename.concat !out_dir ("rule-prob-" ^ env.current_timestamp ^ ".txt")
  in
  let current_rule_instance = Datalog.make env.current_rules in
  let dl_oc = open_out dl_file in
  let dl_ofmt = F.formatter_of_out_channel dl_oc in
  Datalog.pp dl_ofmt current_rule_instance;
  close_out dl_oc;
  BNet.generate_rule_prob_txt prob_txt_file current_rule_instance;
  generate_named_cons env current_rule_instance;
  run_bingo env current_rule_instance

let run_test env =
  let fake_env =
    {
      empty_env with
      benchmarks = get_test_benchmark !targets;
      current_timestamp = env.current_timestamp;
      current_rules = env.current_rules;
    }
  in
  log "========== TEST START : %s ==========" (String.concat " " !targets);
  run_all fake_env;
  Evaluation.run fake_env |> ignore;
  log "=========== TEST END : %s ===========" (String.concat " " !targets)

let read_alarms bnet_dir =
  let ground_truth = Filename.concat bnet_dir "GroundTruth.txt" in
  let alarm = Filename.concat bnet_dir "Alarm.txt" in
  let rec loop ic set =
    match input_line ic with
    | s -> StringSet.add s set |> loop ic
    | exception End_of_file -> set
  in
  let ic = open_in ground_truth in
  let bugs = loop ic StringSet.empty in
  close_in ic;
  let ic = open_in alarm in
  let alarms = loop ic StringSet.empty in
  close_in ic;
  (alarms, bugs)

let read_features vc =
  log "Read feature";
  let datalog_dir =
    Filename.dirname vc.VCurve.bnet_dir |> Fun.flip Filename.concat "datalog"
  in
  let rec loop ic_opt arity set map =
    match ic_opt with
    | None -> (StringSet.empty, -1, TupleMap.empty)
    | Some ic -> (
        match input_line ic with
        | s ->
            let toks = String.split_on_char '\t' s in
            let new_arity = List.length toks in
            let key = toks |> Fun.flip List.nth 0 in
            let value = List.tl toks in
            let new_string_set = key |> Fun.flip StringSet.add set in
            let new_map = TupleMap.add key value map in
            loop ic_opt new_arity new_string_set new_map
        | exception End_of_file ->
            close_in ic;
            (set, arity, map) )
  in
  let read fact_name =
    let fact_file = fact_name ^ ".facts" in
    let ic_opt =
      try Some (open_in (Filename.concat datalog_dir fact_file))
      with _ -> None
    in
    let set, arity, t_map = loop ic_opt 0 StringSet.empty TupleMap.empty in
    ((set, arity), (fact_name, t_map))
  in
  let alarm_array_exp_feat, alarm_array_exp_pair = read alarm_array_exp in
  let alarm_deref_exp_feat, alarm_deref_exp_pair = read alarm_deref_exp in
  let alarm_strcpy_feat, alarm_strcpy_pair = read alarm_strcpy in
  let alarm_strncmp_feat, alarm_strncmp_pair = read alarm_strncmp in
  let alarm_memchr_feat, alarm_memchr_pair = read alarm_memchr in
  let alarm_buffer_overrun_lib_feat, alarm_buffer_overrun_lib_pair =
    read alarm_buffer_overrun_lib
  in
  let alarm_div_exp_feat, alarm_div_exp_pair = read alarm_div_exp in
  let alarm_memcpy_feat, alarm_memcpy_pair = read alarm_memcpy in
  let alarm_memmove_feat, alarm_memmove_pair = read alarm_memmove in
  let alarm_strcat_feat, alarm_strcat_pair = read alarm_strcat in
  let alarm_strncpy_feat, alarm_strncpy_pair = read alarm_strncpy in
  let alarm_taint_feat, alarm_taint_pair = read alarm_taint in
  let alarm_alloc_size_feat, alarm_alloc_size_pair = read alarm_alloc_size in
  let alarm_printf_feat, alarm_printf_pair = read alarm_printf in
  let assign_feat, assign_pair = read assign in
  let loophead_feat, loophead_pair = read loophead in
  let libcall_feat, libcall_pair = read libcall in
  let assume_feat, assume_pair = read assume in
  let call_feat, call_pair = read call in
  let unop_feat, unop_pair = read unop in
  let binop_feat, binop_pair = read binop in
  let lval_exp_feat, lval_exp_pair = read lval_exp in
  let cast_exp_feat, cast_exp_pair = read cast_exp in
  let field_feat, field_pair = read field in
  let b_and_feat, b_and_pair = read b_and in
  let b_not_feat, b_not_pair = read b_not in
  let b_or_feat, b_or_pair = read b_or in
  let b_xor_feat, b_xor_pair = read b_xor in
  let div_feat, div_pair = read div in
  let eq_feat, eq_pair = read eq in
  let ne_feat, ne_pair = read ne in
  let ge_feat, ge_pair = read ge in
  let gt_feat, gt_pair = read gt in
  let le_feat, le_pair = read le in
  let lt_feat, lt_pair = read lt in
  let l_and_feat, l_and_pair = read l_and in
  let l_not_feat, l_not_pair = read l_not in
  let l_or_feat, l_or_pair = read l_or in
  let modulo_feat, modulo_pair = read modulo in
  let mult_feat, mult_pair = read mult in
  let neg_feat, neg_pair = read neg in
  let minus_a_feat, minus_a_pair = read minus_a in
  let minus_pi_feat, minus_pi_pair = read minus_pi in
  let minus_pp_feat, minus_pp_pair = read minus_pp in
  let plus_a_feat, plus_a_pair = read plus_a in
  let plus_pi_feat, plus_pi_pair = read plus_pi in
  let shift_l_feat, shift_l_pair = read shift_l in
  let shift_r_feat, shift_r_pair = read shift_r in
  let entire_feature_pair =
    [
      alarm_array_exp_pair;
      alarm_deref_exp_pair;
      alarm_strcpy_pair;
      alarm_strncmp_pair;
      alarm_memchr_pair;
      alarm_buffer_overrun_lib_pair;
      alarm_div_exp_pair;
      alarm_memcpy_pair;
      alarm_memmove_pair;
      alarm_strcat_pair;
      alarm_strncpy_pair;
      alarm_taint_pair;
      alarm_alloc_size_pair;
      alarm_printf_pair;
      assign_pair;
      loophead_pair;
      libcall_pair;
      assume_pair;
      call_pair;
      unop_pair;
      binop_pair;
      lval_exp_pair;
      cast_exp_pair;
      field_pair;
      b_and_pair;
      b_not_pair;
      b_or_pair;
      b_xor_pair;
      div_pair;
      eq_pair;
      ne_pair;
      ge_pair;
      gt_pair;
      le_pair;
      lt_pair;
      l_and_pair;
      l_not_pair;
      l_or_pair;
      modulo_pair;
      mult_pair;
      neg_pair;
      minus_a_pair;
      minus_pi_pair;
      minus_pp_pair;
      plus_a_pair;
      plus_pi_pair;
      shift_l_pair;
      shift_r_pair;
    ]
  in
  ( {
      alarm_array_exp = alarm_array_exp_feat;
      alarm_deref_exp = alarm_deref_exp_feat;
      alarm_strcpy = alarm_strcpy_feat;
      alarm_strncmp = alarm_strncmp_feat;
      alarm_memchr = alarm_memchr_feat;
      alarm_buffer_overrun_lib = alarm_buffer_overrun_lib_feat;
      alarm_div_exp = alarm_div_exp_feat;
      alarm_memcpy = alarm_memcpy_feat;
      alarm_memmove = alarm_memmove_feat;
      alarm_strcat = alarm_strcat_feat;
      alarm_strncpy = alarm_strncpy_feat;
      alarm_alloc_size = alarm_alloc_size_feat;
      alarm_printf = alarm_printf_feat;
      alarm_taint = alarm_taint_feat;
      assign = assign_feat;
      loophead = loophead_feat;
      libcall = libcall_feat;
      assume = assume_feat;
      call = call_feat;
      unop = unop_feat;
      binop = binop_feat;
      lval_exp = lval_exp_feat;
      cast_exp = cast_exp_feat;
      field = field_feat;
      b_and = b_and_feat;
      b_not = b_not_feat;
      b_or = b_or_feat;
      b_xor = b_xor_feat;
      div = div_feat;
      eq = eq_feat;
      ne = ne_feat;
      ge = ge_feat;
      gt = gt_feat;
      le = le_feat;
      lt = lt_feat;
      l_and = l_and_feat;
      l_not = l_not_feat;
      l_or = l_or_feat;
      modulo = modulo_feat;
      mult = mult_feat;
      neg = neg_feat;
      minus_a = minus_a_feat;
      minus_pi = minus_pi_feat;
      minus_pp = minus_pp_feat;
      plus_a = plus_a_feat;
      plus_pi = plus_pi_feat;
      shift_l = shift_l_feat;
      shift_r = shift_r_feat;
    },
    List.fold_left
      (fun m kv ->
        let k = fst kv in
        let v = snd kv in
        FeatureMap.add k v m)
      FeatureMap.empty entire_feature_pair )

let construct_sparrow_alarm_assoc_list vc =
  log "Construct SparrowAlarm association list";
  let datalog_dir =
    Filename.dirname vc.VCurve.bnet_dir |> Fun.flip Filename.concat "datalog"
  in
  let make_sparrow_alarm_pair toks =
    let a1 = List.nth toks 0 in
    let a2 = List.nth toks 1 in
    let value = List.nth toks 2 in
    let key = a1 ^ "," ^ a2 in
    (key, value)
  in
  let rec loop ic lst =
    match input_line ic with
    | s ->
        String.split_on_char '\t' s
        |> make_sparrow_alarm_pair |> Fun.flip List.cons lst |> loop ic
    | exception End_of_file -> lst
  in
  let read fact_file =
    let ic = open_in (Filename.concat datalog_dir fact_file) in
    let set = loop ic [] in
    close_in ic;
    set
  in
  read "SparrowAlarm.facts"

let update_current_timestamp env =
  (* to avoid conflicts *)
  let rand_int = Random.int 100000 in
  let ts = string_of_current_time () in
  { env with current_timestamp = ts ^ "-" ^ string_of_int rand_int }

let attach_prob_to_timestamp prob env =
  {
    env with
    current_timestamp = env.current_timestamp ^ "-p" ^ string_of_float prob;
  }

let remove_prob_from_timestamp env =
  log "Before removing: %s" env.current_timestamp;
  if Str.string_match (Str.regexp "\\(.*\\)-p\\(.*\\)") env.current_timestamp 0
  then (
    let pure_timestamp = Str.matched_group 1 env.current_timestamp in
    log "After removing: %s" pure_timestamp;
    { env with current_timestamp = pure_timestamp } )
  else (
    log "NO REMOVAL";
    env )

let update_env timestamp total_iters env =
  let total_num_alarms, total_num_bugs =
    List.fold_left
      (fun (num_alarms, num_bugs) bench ->
        let bench_dir = Filename.concat benchmark_home bench in
        let bnet_dir =
          Filename.concat bench_dir
            ("sparrow-out/" ^ !analysis_type ^ "/bnet-" ^ timestamp)
        in
        let alarms, bugs = read_alarms bnet_dir in
        ( num_alarms + StringSet.cardinal alarms,
          num_bugs + StringSet.cardinal bugs ))
      (0, 0) env.benchmarks
  in
  {
    env with
    best_timestamp = timestamp;
    best_iters = total_iters;
    best_iters_lst = Evaluation.get_num_iters_lst env;
    total_num_alarms;
    total_num_bugs;
  }

(* for all unlabelled alarms, return a list of pairs of name and ranking *)
let rank_of file =
  let ic = open_in file in
  let rec loop ic lst =
    match input_line ic with
    | s when String.sub s 0 4 = "Rank'" -> loop ic lst
    | s ->
        let tokens = String.split_on_char '\t' s in
        if List.nth tokens 3 = "Unlabelled" then
          loop ic ((List.nth tokens 4, List.nth tokens 0) :: lst)
        else loop ic lst
    | exception End_of_file -> lst
  in
  let lst = loop ic [] |> List.rev in
  close_in ic;
  lst

let find_v_curve_one benchmark num_alarms bugs bnet_dir combined_dir =
  let rankings =
    Sys.readdir combined_dir |> Array.to_list
    |> List.filter (fun x -> x <> "init.out" && x <> ".done")
    |> List.sort (fun a b ->
           compare
             (Filename.remove_extension a |> int_of_string)
             (Filename.remove_extension b |> int_of_string))
    |> List.map (fun file -> Filename.concat combined_dir file |> rank_of)
  in
  let rec collect rankings lst =
    match rankings with
    | current :: next :: t ->
        StringSet.fold
          (fun gt lst ->
            let current_ranking =
              try List.assoc gt current |> int_of_string with Not_found -> 0
            in
            let next_ranking =
              try List.assoc gt next |> int_of_string with Not_found -> 0
            in
            if next_ranking > current_ranking then
              {
                VCurve.benchmark;
                bnet_dir;
                false_alarm = List.hd current |> fst;
                true_alarm = gt;
                height = next_ranking - current_ranking;
                height_ratio =
                  float_of_int (next_ranking - current_ranking)
                  /. float_of_int num_alarms;
              }
              :: lst
            else lst)
          bugs lst
        |> collect (next :: t)
    | _ -> lst
  in
  collect rankings [] |> List.filter (fun vc -> vc.VCurve.height_ratio > !min_v)

let find_v_curves env =
  log "Find the worst v-curve";
  List.fold_left
    (fun lst bench ->
      let bench_dir = Filename.concat benchmark_home bench in
      let bnet_dir =
        Filename.concat bench_dir
          ("sparrow-out/" ^ !analysis_type ^ "/bnet-" ^ env.current_timestamp)
      in
      let alarms, bugs = read_alarms bnet_dir in
      let num_alarms = StringSet.cardinal alarms in
      let combined_dir =
        Filename.concat bench_dir
          ( "sparrow-out/" ^ !analysis_type ^ "/bingo_combined-"
          ^ env.current_timestamp )
      in
      lst @ find_v_curve_one bench num_alarms bugs bnet_dir combined_dir)
    [] env.benchmarks
  |> List.sort (fun a b -> compare b.VCurve.height_ratio a.VCurve.height_ratio)

let type_of_alarm features alarm =
  if StringSet.mem alarm (features.alarm_alloc_size |> fst) then
    (alarm_alloc_size, features.alarm_alloc_size |> snd)
  else if StringSet.mem alarm (features.alarm_printf |> fst) then
    (alarm_printf, features.alarm_printf |> snd)
  else if StringSet.mem alarm (features.alarm_taint |> fst) then
    (alarm_taint, features.alarm_taint |> snd)
  else if StringSet.mem alarm (features.alarm_array_exp |> fst) then
    (alarm_array_exp, features.alarm_array_exp |> snd)
  else if StringSet.mem alarm (features.alarm_deref_exp |> fst) then
    (alarm_deref_exp, features.alarm_deref_exp |> snd)
  else if StringSet.mem alarm (features.alarm_strcpy |> fst) then
    (alarm_strcpy, features.alarm_strcpy |> snd)
  else if StringSet.mem alarm (features.alarm_memchr |> fst) then
    (alarm_memchr, features.alarm_memchr |> snd)
  else if StringSet.mem alarm (features.alarm_strncmp |> fst) then
    (alarm_strncmp, features.alarm_strncmp |> snd)
  else if StringSet.mem alarm (features.alarm_buffer_overrun_lib |> fst) then
    (alarm_buffer_overrun_lib, features.alarm_buffer_overrun_lib |> snd)
  else if StringSet.mem alarm (features.alarm_div_exp |> fst) then
    (alarm_div_exp, features.alarm_div_exp |> snd)
  else if StringSet.mem alarm (features.alarm_memcpy |> fst) then
    (alarm_memcpy, features.alarm_memcpy |> snd)
  else if StringSet.mem alarm (features.alarm_memmove |> fst) then
    (alarm_memmove, features.alarm_memmove |> snd)
  else if StringSet.mem alarm (features.alarm_strcat |> fst) then
    (alarm_strcat, features.alarm_strcat |> snd)
  else if StringSet.mem alarm (features.alarm_strncpy |> fst) then
    (alarm_strncpy, features.alarm_strncpy |> snd)
  else (not_found, -1)

let type_of_node features node =
  if StringSet.mem node (features.assign |> fst) then
    (assign, features.assign |> snd)
  else if StringSet.mem node (features.assume |> fst) then
    (assume, features.assume |> snd)
  else if StringSet.mem node (features.libcall |> fst) then
    (libcall, features.libcall |> snd)
  else if StringSet.mem node (features.loophead |> fst) then
    (loophead, features.loophead |> snd)
  else if StringSet.mem node (features.call |> fst) then
    (call, features.call |> snd)
  else (not_found, -1)

let type_of_exp features exp =
  if StringSet.mem exp (features.unop |> fst) then (unop, features.unop |> snd)
  else if StringSet.mem exp (features.binop |> fst) then
    (binop, features.binop |> snd)
  else if StringSet.mem exp (features.lval_exp |> fst) then
    (lval_exp, features.lval_exp |> snd)
  else if StringSet.mem exp (features.cast_exp |> fst) then
    (cast_exp, features.cast_exp |> snd)
  else (not_found, -1)

let type_of_lval features lval =
  if StringSet.mem lval (features.field |> fst) then
    (field, features.unop |> snd)
  else (not_found, -1)

let type_of_op features op =
  if StringSet.mem op (features.b_and |> fst) then (b_and, features.b_and |> snd)
  else if StringSet.mem op (features.b_not |> fst) then
    (b_not, features.b_not |> snd)
  else if StringSet.mem op (features.b_or |> fst) then
    (b_or, features.b_or |> snd)
  else if StringSet.mem op (features.b_xor |> fst) then
    (b_xor, features.b_xor |> snd)
  else if StringSet.mem op (features.div |> fst) then (div, features.div |> snd)
  else if StringSet.mem op (features.eq |> fst) then (eq, features.eq |> snd)
  else if StringSet.mem op (features.ne |> fst) then (ne, features.ne |> snd)
  else if StringSet.mem op (features.ge |> fst) then (ge, features.ge |> snd)
  else if StringSet.mem op (features.gt |> fst) then (gt, features.gt |> snd)
  else if StringSet.mem op (features.le |> fst) then (le, features.le |> snd)
  else if StringSet.mem op (features.lt |> fst) then (lt, features.lt |> snd)
  else if StringSet.mem op (features.l_and |> fst) then
    (l_and, features.l_and |> snd)
  else if StringSet.mem op (features.l_not |> fst) then
    (l_not, features.l_not |> snd)
  else if StringSet.mem op (features.l_or |> fst) then
    (l_or, features.l_or |> snd)
  else if StringSet.mem op (features.modulo |> fst) then
    (modulo, features.modulo |> snd)
  else if StringSet.mem op (features.mult |> fst) then
    (mult, features.mult |> snd)
  else if StringSet.mem op (features.neg |> fst) then (neg, features.neg |> snd)
  else if StringSet.mem op (features.minus_a |> fst) then
    (minus_a, features.minus_a |> snd)
  else if StringSet.mem op (features.minus_pi |> fst) then
    (minus_pi, features.minus_pi |> snd)
  else if StringSet.mem op (features.minus_pp |> fst) then
    (minus_pp, features.minus_pp |> snd)
  else if StringSet.mem op (features.plus_a |> fst) then
    (plus_a, features.plus_a |> snd)
  else if StringSet.mem op (features.plus_pi |> fst) then
    (plus_pi, features.plus_pi |> snd)
  else if StringSet.mem op (features.shift_l |> fst) then
    (shift_l, features.shift_l |> snd)
  else if StringSet.mem op (features.shift_r |> fst) then
    (shift_r, features.shift_r |> snd)
  else (not_found, -1)

let alarm_node_seed = ref (Datalog.Variable.Var 666)

let is_exp name = Str.string_match (Str.regexp "Exp-.*") name 0

let is_lval name = Str.string_match (Str.regexp "Lval-.*") name 0

let get_non_alarm_tuple_type_and_arity features ground_node_name =
  let typ, arity =
    ground_node_name
    |>
    if is_exp ground_node_name then type_of_exp features
    else if is_lval ground_node_name then type_of_lval features
    else type_of_node features
  in
  if typ = not_found then type_of_op features ground_node_name else (typ, arity)

let get_visible_tail rule =
  List.filter
    (fun t -> StringSet.mem t.Tuple.name hidden_tuples |> not)
    rule.Datalog.Rule.tail

let get_visible_rule (rule : Datalog.Rule.t) =
  { rule with tail = get_visible_tail rule }

let find_tup_in_grule_and_brule box grule brule =
  (* Find GTuple that contains box using correspondence to brule. Ignore negated tuples *)
  log "Traverse thru grounded rule and boxed rule";
  log "Grounded: %s" (GRule.to_string grule);
  log "Boxed: %s" (Datalog.Rule.to_string brule);
  let b_loc = Datalog.Rule.find_box box brule in
  let grule_premises = grule.GRule.premises in
  let brule_visible_tail = get_visible_tail brule in
  let rec loop premises tail =
    match (premises, tail) with
    | gtup :: t1, tup :: t2 ->
        if Datalog.Tuple.is_v_present box tup then (gtup, b_loc) else loop t1 t2
    | _, _ -> failwith (Datalog.Variable.to_string box ^ " NOT FOUND")
  in
  loop grule_premises brule_visible_tail

let run_parallel f lst =
  let res =
    List.map
      (fun work ->
        let c = Event.new_channel () in
        let _ =
          Thread.create (fun c -> Event.send c (f work) |> Event.sync) c
        in
        Event.receive c)
      lst
  in
  List.map Event.sync res

let run_weights env old_rule refined_rules =
  let aligned_rule_lst =
    refined_rules |> RuleSet.elements
    |> List.sort (fun a b ->
           Datalog.Rule.num_negated_tups a - Datalog.Rule.num_negated_tups b)
  in
  let unchanged_rules = RuleSet.remove old_rule env.current_rules in
  let weighted_ruleset_candiates =
    List.map
      (fun p ->
        let target_rule = List.nth aligned_rule_lst 0 in
        let rest_rule = List.nth aligned_rule_lst 1 in
        let new_prob = p *. target_rule.prob in
        let weighted_rule = Datalog.Rule.assign_prob new_prob target_rule in
        ( p,
          [ weighted_rule; rest_rule ]
          |> RuleSet.of_list
          |> RuleSet.union unchanged_rules ))
      weights
  in
  let weighted_envs =
    List.map
      (fun (prob, weighted_ruleset) ->
        let prob_env =
          env |> remove_prob_from_timestamp |> attach_prob_to_timestamp prob
        in
        { prob_env with current_rules = weighted_ruleset })
      weighted_ruleset_candiates
  in
  (if !is_parallel then run_parallel else List.map)
    (fun wenv ->
      log "%s" wenv.current_timestamp;
      run_all wenv;
      Evaluation.run wenv |> ignore)
    weighted_envs
  |> ignore;
  weighted_envs

let improved env old_rule refined_rules =
  log "Refined rules:\n%a" (RuleSet.pp ~is_debug:false) refined_rules;
  if RuleSet.cardinal refined_rules = 1 then (
    log "SUSPICIOUS";
    log "Rule should have been refined: %s" (Rule.to_string old_rule);
    (false, env) )
  else
    let env = update_current_timestamp env in
    let new_rules =
      RuleSet.remove old_rule env.current_rules
      |> RuleSet.union refined_rules
      |> RuleSet.normalize
    in
    match RuleSetCache.find_opt new_rules env.ruleset_cache with
    | Some total_iters ->
        log "CACHED RULE SET";
        ( false,
          {
            env with
            history = env.history @ [ (env.current_timestamp, total_iters) ];
          } )
    | None ->
        let weighted_envs = run_weights env old_rule refined_rules in
        let { Evaluation.total_iters; improved_ratio; env = evaluated_env; _ } =
          Evaluation.run_weights weighted_envs
        in
        if !is_debug then run_test evaluated_env;
        let ruleset_cache =
          RuleSetCache.add new_rules total_iters env.ruleset_cache
        in
        let criteria_iters =
          if !use_baseline then !baseline_iters else env.best_iters
        in
        let compare_iter = total_iters < criteria_iters in
        if compare_iter && improved_ratio >= !min_improved_ratio then (
          let num_iters_lst = Evaluation.get_num_iters_lst evaluated_env in
          log "IMPROVED";
          log "TIMESTAMP-WEIGHT: %s" evaluated_env.current_timestamp;
          ( true,
            {
              evaluated_env with
              best_timestamp = evaluated_env.current_timestamp;
              best_iters = total_iters;
              best_iters_lst = num_iters_lst;
              best_rules = new_rules;
              history =
                evaluated_env.history
                @ [ (evaluated_env.current_timestamp, total_iters) ];
              ruleset_cache;
            } ) )
        else
          ( false,
            {
              env with
              history =
                env.history @ [ (evaluated_env.current_timestamp, total_iters) ];
              ruleset_cache;
            } )

let refine_boxed_rule env boxed_rule rule_to_be_refined target_type arity
    target_var =
  log "Arity: %d" arity;
  let rec dontcares n =
    if n <= 1 then [] else Datalog.Variable.DontCare :: dontcares (n - 1)
  in
  let boxes = Datalog.Rule.extract_boxes boxed_rule in
  log "# boxes: %s" (string_of_int (List.length boxes));
  log "TARGET VAR: %s" (Datalog.Variable.to_string target_var);
  log "BOXED: %s" (Datalog.Rule.to_string boxed_rule);
  let dontcared =
    [ boxed_rule ] |> List.map (Datalog.Rule.dontcare_box_except target_var)
  in
  log "DONTCARED: %s" (Datalog.Rule.to_string (List.nth dontcared 0));
  dontcared
  |> Combinator.populate target_var (fun v _ ->
         [
           Datalog.Tuple.make target_type
             (Datalog.Variable.box_into_var v :: dontcares arity);
         ])
  |> List.map Datalog.Rule.dontcare_box
  |> RuleSet.of_list
  |> improved env rule_to_be_refined

let refine_negated_tuple env boxed_rule grule rule_to_be_refined features =
  log "Try refine negated tuple of %s"
    (Datalog.Rule.to_string rule_to_be_refined);
  let visible_rule =
    { rule_to_be_refined with tail = get_visible_tail rule_to_be_refined }
  in
  let negated_tup_head_vars =
    Datalog.Rule.get_negated_tup_head_vars visible_rule
  in
  List.fold_left
    (fun (is_improved, env) (head_v, tup_ind) ->
      if is_improved then (true, env)
      else
        let neg_gtup = List.nth grule.GRule.premises tup_ind in
        log "- negated gtuple: %s" (GTuple.to_string neg_gtup);
        let neg_gtup_head = List.nth neg_gtup.elements 0 in
        log "-- head name: %s" neg_gtup_head;
        let target_type, arity =
          get_non_alarm_tuple_type_and_arity features neg_gtup_head
        in
        if target_type = not_found then (false, env)
        else
          refine_boxed_rule env boxed_rule rule_to_be_refined target_type arity
            head_v)
    (false, env) negated_tup_head_vars

let rec refine_tuples env boxed_rule grule rule_to_be_refined features
    feature_map = function
  | [] -> (false, env)
  | box :: t -> (
      log "========== Epoch %d.%d.%d.%d (on tuples) ==========" env.epoch
        env.epoch_v_curve env.epoch_rule env.epoch_tuple;
      log "Refine %s" (Datalog.Variable.to_string box);
      let target_gtup, target_v_loc =
        find_tup_in_grule_and_brule box grule boxed_rule
      in
      let gtup_head = List.nth target_gtup.elements 0 in
      let tuple_map = FeatureMap.find target_gtup.GTuple.name feature_map in
      let named_nodes = TupleMap.find gtup_head tuple_map in
      let target_node_name = List.nth named_nodes target_v_loc in
      let target_type, arity =
        get_non_alarm_tuple_type_and_arity features target_node_name
      in
      if target_type = not_found then (false, env)
      else
        refine_boxed_rule env boxed_rule rule_to_be_refined target_type arity
          box
        |> function
        | b, env ->
            if b then (true, { env with epoch_tuple = 0 })
            else
              refine_tuples
                { env with epoch_tuple = env.epoch_tuple + 1 }
                boxed_rule grule rule_to_be_refined features feature_map t )

let refine_rule env features alarm_map feature_map grule target_rule =
  let boxed_rule = Datalog.Rule.dontcare_into_box target_rule in
  if Str.string_match (Str.regexp "Alarm.*") grule.GRule.name 0 then
    (* Alarm rule refinement *)
    let target_tuple = List.nth grule.premises 0 in
    let alarm_tuple_exists = List.exists GTuple.is_alarm grule.premises in
    let alarm_rule_boxes = Datalog.Rule.boxes_in_rule boxed_rule in
    let alarm_tuple_boxes =
      if alarm_tuple_exists then Datalog.Rule.boxes_in_alarm boxed_rule else []
    in
    if alarm_tuple_boxes <> [] then (
      (* Case A1 : AlarmTuple exists and boxes exist in the AlarmTuple *)
      log "Case A1";
      refine_tuples env boxed_rule grule target_rule features feature_map
        alarm_tuple_boxes )
    else if alarm_tuple_exists then (
      (* Case A2 : AlarmTuple exists and no more boxes in the AlarmTuple *)
      log "Case A2";
      let improved, env =
        refine_negated_tuple env boxed_rule grule target_rule features
      in
      if improved then (true, env)
      else
        refine_tuples env boxed_rule grule target_rule features feature_map
          alarm_rule_boxes )
    else (
      (* Case A3 : No AlarmTuple has been generated in the rule *)
      log "Case A3";
      let target_tuple_str = GTuple.elements_to_string target_tuple in
      log "target %s" target_tuple_str;
      let target_alarm =
        match List.assoc_opt target_tuple_str alarm_map with
        | Some s -> s
        | None ->
            prerr_endline
              ( "Cannot find "
              ^ GTuple.to_string target_tuple
              ^ " in SparrowAlarm.facts" );
            exit 1
      in
      log "target alarm: %s" target_alarm;
      let target_alarm_type, alarm_arity =
        type_of_alarm features target_alarm
      in
      if target_alarm_type = not_found then (
        log "NOT_FOUND - Alarm case";
        (false, env) )
      else
        let is_fresh = List.length grule.premises = 1 in
        if is_fresh then log "FRESH CASE"
        else
          log "NOT FRESH - # premises: %s"
            (string_of_int (List.length grule.premises));
        List.iter
          (fun gt -> log "grule.premise: %s" (GTuple.to_string gt))
          grule.premises;
        let boxes = Datalog.Rule.extract_boxes boxed_rule in
        if is_fresh then alarm_node_seed := List.nth boxes 0;
        let target_v = !alarm_node_seed in
        refine_boxed_rule env boxed_rule target_rule target_alarm_type
          alarm_arity target_v )
  else
    (* DUPath rule refinement *)
    let path_rule_boxes =
      boxed_rule |> get_visible_rule |> Datalog.Rule.boxes_in_rule
    in
    let is_cond =
      boxed_rule.tail
      |> List.exists (fun t ->
             Str.string_match (Str.regexp ".*eCond.*") t.Tuple.name 0)
    in
    if path_rule_boxes = [] then (
      (* Case P1 : Base rule, i.e. no refinement has been done *)
      if is_cond then log "Case P1 - Cond" else log "Case P1";
      let tuple_ind = if is_cond then 2 else 0 in
      let target_tuple = List.nth grule.premises tuple_ind in
      let target_node_ind = List.length target_tuple.elements - 1 in
      let target_tuple_str = GTuple.elements_to_string target_tuple in
      log "target %s" target_tuple_str;
      let target_node_name =
        GTuple.nth_elt_to_string target_node_ind target_tuple
      in
      let target_v =
        List.nth (List.nth boxed_rule.tail tuple_ind).vars target_node_ind
      in
      let target_type, arity =
        get_non_alarm_tuple_type_and_arity features target_node_name
      in
      if target_type = not_found then (
        log "NOT_FOUND - DUPath case";
        (false, env) )
      else
        refine_boxed_rule env boxed_rule target_rule target_type arity target_v
      )
    else (
      (* Case P2 : Refinement in progress - refine (1) negated tuple's first Var, or (2) Box *)
      log "Case P2";
      let improved, env =
        refine_negated_tuple env boxed_rule grule target_rule features
      in
      if improved then (true, env)
      else
        refine_tuples env boxed_rule grule target_rule features feature_map
          path_rule_boxes )

(* Heuristic: Given a grounded rule (grule), find the corresponding rule from the rule set *)
let find_rule grule rules =
  RuleSet.filter
    (fun r ->
      let visible_tail = get_visible_tail r in
      r.Rule.head.Tuple.name = grule.GRule.conclusion.GTuple.name
      && List.length visible_tail = List.length grule.premises
      && List.for_all2
           (fun t gt -> Tuple.get_full_name t = gt.GTuple.name)
           visible_tail grule.premises)
    rules
  |> fun s ->
  log "Target grule: %s" (GRule.to_string grule);
  log "Matched rule: %a" (RuleSet.pp ~is_debug:false) s;
  assert (RuleSet.cardinal s = 1);
  RuleSet.choose s

let rec refine_rules env features alarm_map feature_map = function
  | [] -> (false, env)
  | grule :: t -> (
      log "========== Epoch %d.%d.%d (on rules) ==========" env.epoch
        env.epoch_v_curve env.epoch_rule;
      log "Refine %s" (GRule.to_string grule);
      let rule_to_be_refined = find_rule grule env.current_rules in
      refine_rule env features alarm_map feature_map grule rule_to_be_refined
      |> function
      | b, env ->
          if b then (true, { env with epoch_rule = 0 })
          else
            refine_rules
              { env with epoch_rule = env.epoch_rule + 1 }
              features alarm_map feature_map t )

let find_candidates vc =
  let named_cons = Filename.concat vc.VCurve.bnet_dir "named_cons_all.txt" in
  let node =
    Filename.dirname vc.VCurve.bnet_dir
    |> Filename.dirname
    |> Fun.flip Filename.concat "node.json"
  in
  let bnet = BNet.build named_cons node in
  let a1 =
    match !analysis_type with
    | "interval" -> BNet.Node.of_tuple vc.VCurve.false_alarm
    | "taint" -> BNet.Node.of_tuple vc.VCurve.true_alarm
    | t -> failwith ("Unsupported analysis type: " ^ t)
  in
  let a2 =
    match !analysis_type with
    | "interval" -> BNet.Node.of_tuple vc.VCurve.true_alarm
    | "taint" -> BNet.Node.of_tuple vc.VCurve.false_alarm
    | t -> failwith ("Unsupported analysis type: " ^ t)
  in
  try BNet.compute_common_ancestor bnet a1 a2 |> snd
  with BNet.Best_effort_not_found ->
    log "COMMON ANCESTOR NOT FOUND";
    []

let rec refine_v_curves env = function
  | [] -> (false, env)
  | vc :: t -> (
      log "========== Epoch %d.%d (on v curves) ==========" env.epoch
        env.epoch_v_curve;
      log "Target VC: %s" (VCurve.to_string vc);
      match find_candidates vc with
      | candidate_grules ->
          let features, feature_map = read_features vc in
          let alarm_assoc_list = construct_sparrow_alarm_assoc_list vc in
          log "Candidate grounded rules";
          List.iter (fun x -> log "- %s" (GRule.to_string x)) candidate_grules;
          let improved, env =
            refine_rules
              { env with current_v_curve = vc; epoch_rule = 0 }
              features alarm_assoc_list feature_map candidate_grules
          in
          if improved then (true, { env with epoch_v_curve = 0 })
          else
            refine_v_curves { env with epoch_v_curve = env.epoch_v_curve + 1 } t
      | exception Not_found ->
          log "WARN: common ancestor not found. skip this v-curve";
          refine_v_curves { env with epoch_v_curve = env.epoch_v_curve + 1 } t )

let opts =
  [
    ("-reuse", Arg.Set reuse, "Reuse existing baseline results");
    ( "-timestamp",
      Arg.String (fun s -> timestamp := s),
      "Start from an existing Bingo result" );
    ( "-min_v",
      Arg.Set_float min_v,
      "Minimum threshold of height-ratio (default: 0.1)" );
    ( "-max_epoch",
      Arg.Set_int max_epoch,
      "Maximum number of epochs (default: 100)" );
    ("-out_dir", Arg.Set_string out_dir, "Output directory (default: learn-out)");
    ( "-debug",
      Arg.Set is_debug,
      "Enable debug mode i.e. run test at every improvement" );
    ( "-analysis_type",
      Arg.Set_string analysis_type,
      "Analysis type: interval or taint (default: interval)" );
    ( "-min_improved_ratio",
      Arg.Set_float min_improved_ratio,
      "Minimum threshold of improved benchmarks' ratio (default: 0.5)" );
    ( "-dl_from",
      Arg.Set_string dl_from,
      "Specify path to .dl file to start from" );
    ( "-rule_prob_from",
      Arg.Set_string rule_prob_from,
      "Specify path to rule-prob.txt file to start from" );
    ("-j", Arg.Set is_parallel, "Run parallel if possible");
    ( "-test",
      Arg.Set is_test,
      "Run test on given benchmark, dl and rule_prob files" );
    ( "-force_rerun",
      Arg.Set force_rerun,
      "Force re-run without using cached bingo results" );
    ( "-use_baseline",
      Arg.Set use_baseline,
      "Set baseline as evaluation criteria at each time" );
    ( "-alpha",
      Arg.Set_float alpha,
      "Set alpha i.e. hyperparam. for learned rule firing prob. multiplier \
       (default: 0.99)" );
  ]

(* TODO *)
let should_terminate env = env.epoch > !max_epoch

let rec learning env =
  if should_terminate env then env
  else (
    log "========== Epoch %d ==========" env.epoch;
    log "Current rules: \n%a" (RuleSet.pp ~is_debug:true) env.current_rules;
    find_v_curves env
    $> List.iter (fun vc -> VCurve.to_string vc |> log "%s")
    |> refine_v_curves env
    |> function
    | improved, env ->
        if improved then learning { env with epoch = env.epoch + 1 }
        else (
          log "No more possible refinement";
          env ) )

let initialize () =
  ( try Unix.mkdir !out_dir 0o775
    with Unix.Unix_error (Unix.EEXIST, _, _) -> () );
  prerr_endline ("Logging to " ^ !out_dir);
  log_file := Filename.concat !out_dir "learn.log" |> open_out |> Option.some;
  log_formatter := Option.map F.formatter_of_out_channel !log_file

let set_baseline base_rules =
  log "Load baseline statistics";
  let base_env =
    update_current_timestamp
      {
        empty_env with
        current_rules = base_rules;
        benchmarks = leave_one_out !targets;
      }
  in
  run_all base_env;
  baseline_iters_lst := Evaluation.get_num_iters_lst base_env;
  baseline_iters := List.fold_left ( + ) 0 !baseline_iters_lst;
  log "TOTAL BASELINE ITERS: %d" !baseline_iters

let finalize () =
  match !log_file with Some log_file -> close_out log_file | None -> ()

let report env =
  log "========== Report ==========";
  log "  - Total trials: %d" (List.length env.history);
  List.iter
    (fun (timestamp, iters) -> log "  - %s: %d" timestamp iters)
    env.history

let main () =
  Random.self_init ();
  Arg.parse opts (fun x -> targets := !targets @ [ x ]) "";
  initialize ();
  log "Chosen program: %s" (String.concat " " !targets);
  let initial_rules =
    if !dl_from <> "" then (Datalog.of_file !dl_from !rule_prob_from).rules
    else if !analysis_type = "interval" then Buffer_rules.buffer_overflow_rules
    else if !analysis_type = "taint" then Integer_rules.integer_overflow_rules
    else failwith "Unknown analysis type"
  in
  let initial_env =
    {
      empty_env with
      current_timestamp = "baseline";
      current_rules = initial_rules;
      benchmarks = leave_one_out !targets;
    }
  in
  if !is_test then (
    if !dl_from = "" then
      failwith "One must at least specify a dl file to run test";
    let test_env = { initial_env with current_timestamp = !timestamp } in
    run_test test_env )
  else (
    ( if !use_baseline then
      let baseline_rules =
        if !analysis_type = "interval" then
          Buffer_rules.buffer_overflow_rules_baseline
        else if !analysis_type = "taint" then
          Integer_rules.integer_overflow_rules_baseline
        else failwith "Unknown analysis type"
      in
      set_baseline baseline_rules );
    if !reuse then log "Skip baseline and reuse existing result."
    else run_all initial_env;
    let { Evaluation.total_iters; _ } = Evaluation.run initial_env in
    let env =
      update_env initial_env.current_timestamp total_iters initial_env
    in
    log "%s" (string_of_environment env);
    learning env |> report |> finalize )

let _ = main ()
