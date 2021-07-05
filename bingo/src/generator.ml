module F = Format
module StringSet = Set.Make (String)

let usage =
  "Usage: generator [ taint | interval ] [ sparrow-out dir path ] [ bnet dir \
   name ]"

let check_argv args =
  if Array.length args <> 4 then (
    prerr_endline usage;
    exit 1 )
  else ()

let main argv =
  check_argv argv;
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
