module F = Format

let main argv =
  let dl_file = argv.(1) in
  let dl = Datalog.of_file dl_file "" in
  let new_dl = BNet.equip_tdupath dl in
  Datalog.pp F.std_formatter new_dl

let _ = main Sys.argv
