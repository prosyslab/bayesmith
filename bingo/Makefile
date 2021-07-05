all:
	dune build src/driver.exe
	dune build src/generator.exe
	dune build src/visualizer.exe
	dune build src/learn.exe
	dune build src/equipTDU.exe
	ln -sf _build/default/src/driver.exe driver
	ln -sf _build/default/src/generator.exe generator
	ln -sf _build/default/src/visualizer.exe visualizer
	ln -sf _build/default/src/learn.exe learn
	ln -sf _build/default/src/equipTDU.exe equipTDU
clean:
	dune clean
