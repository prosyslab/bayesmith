all:
	dune build src/driver.exe
	dune build src/generator.exe
	dune build src/visualizer.exe
	dune build src/learn.exe
	ln -sf _build/default/src/driver.exe driver
	ln -sf _build/default/src/generator.exe generator
	ln -sf _build/default/src/visualizer.exe visualizer
	ln -sf _build/default/src/learn.exe learn
clean:
	dune clean
