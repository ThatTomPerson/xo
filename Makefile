GO = go1.11rc1

run: clean
	mkdir -p dist
	$(GO) generate ./...
	GO111MODULE=on $(GO) run . --out dist -v mysql://root:r=BDipyiDYzQBLvaMV8RbwRo@aurora-cluster.cluster-clbdbh3t0l1b.ap-southeast-2.rds.amazonaws.com/agedcareguide --tables ContactLinks Contacts ContactTypes ContactTypeLinks
.PHONY: run

clean: 
	rm -rf dist
.PHONY: dist

install:
	rm $$(which xo)
	$(GO) generate ./...
	GO111MODULE=on $(GO) install .
.PHONY: install

