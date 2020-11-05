module F = Format
module StringSet = Set.Make (String)

let usage =
  "Usage: generator bnet [ taint | interval ] [ sparrow-out dir path ] [ bnet \
   dir name ] [ dl | ml ] [ dl file path ]"

let rule_src_opts = [ "dl"; "ml" ] |> StringSet.of_list

let check_argv args =
  if Array.length args >= 4 then
    if not (StringSet.mem args.(5) rule_src_opts) then (
      prerr_endline usage;
      exit 1 )

let main argv =
  let analysis_type = argv.(1) in
  let sparrow_out_dir = argv.(2) in
  let bnet_dir = argv.(3) in
  match analysis_type with
  | "interval" ->
      Datalog.make Buffer_rules.buffer_overflow_rules
      |> BNet.generate_named_cons sparrow_out_dir analysis_type bnet_dir
  | "taint" ->
      Datalog.make Integer_rules.integer_overflow_rules
      |> BNet.generate_named_cons sparrow_out_dir analysis_type bnet_dir
  | _ -> assert false

let _ = main Sys.argv
