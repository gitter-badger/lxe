DOMAIN=lxe

LXDSOCKETFILE ?= /var/lib/lxd/unix.socket
LXESOCKETFILE ?= /var/run/lxe.sock
LXDSOCKET=unix://$(LXDSOCKETFILE)
LXESOCKET=unix://$(LXESOCKETFILE)
LXELOGFILE ?= /var/log/lxe.log

VERSION=$(shell git describe --long --tags --dirty --always --match '[0-9]\.[0-9]' | sed -e 's|-|.|g')
PACKAGENAME=$(shell echo "$${PWD\#"$$GOPATH/src/"}")

GO111MODULE=on

.PHONY: all
all: build test lint

.PHONY: build
build: mod version
	go build -v $(DEBUG) -o bin/lxe ./cmd/lxe

.PHONY: 
mod: 
	go mod download
	go mod tidy
	go mod verify

.PHONY: debug
debug: mod version
	go build -v -tags logdebug $(DEBUG) -o bin/lxe ./cmd/lxe

$(GOPATH)/bin/gometalinter:
	go get -v -u "github.com/alecthomas/gometalinter"
	$(GOPATH)/bin/gometalinter --install

$(GOPATH)/bin/overalls:
	go get -v -u "github.com/go-playground/overalls"

$(GOPATH)/bin/critest:
# 	go get -v -u "github.com/kubernetes-incubator/cri-tools/cmd/critest"
	make -C $(GOPATH)/src/github.com/kubernetes-incubator/cri-tools critest

.PHONY: check
check: lint vet test

.PHONY: lint
lint: $(GOPATH)/bin/gometalinter
	$(GOPATH)/bin/gometalinter ./... --vendor \
		--disable-all \
		--deadline 160s \
		--enable=misspell \
		--enable=goconst \
		--enable=deadcode \
		--enable=ineffassign \
		--enable=lll --line-length=140 \
		--enable=gosec \
		--enable=golint \
		--enable=varcheck \
		--enable=structcheck \
		--enable=gosimple \
		--enable=errcheck \
		--enable=goimports \
		--enable=dupl \
		--enable=gotype \
		--concurrency=1 --enable-gc \
		--aggregate

.PHONY: vet
vet:
	@echo TODO

.PHONY: test
test: $(GOPATH)/bin/overalls
	$(GOPATH)/bin/overalls -project $(PACKAGENAME) -ignore .git,vendor,.cache
	go tool cover -func overalls.coverprofile

gccgo:
	go build -v $(DEBUG) -compiler gccgo ./...
	@echo "$(DOMAIN) built successfully with gccgo"

version:
	@echo "$(VERSION)"
	@echo "package cri\n// Version of LXE\nconst Version = \"$(VERSION)\"" | gofmt > cri/version.go

.PHONY: integration-test
integration-test: critest

.PHONY: checklxd
checklxd:
	@test -e $(LXDSOCKETFILE) || (echo "Socket $(LXDSOCKETFILE) not found! Is LXD running?" && false)
	@test -r $(LXDSOCKETFILE) || (echo "Socket $(LXDSOCKETFILE) not accessible! Can this user read it?" && false)

.PHONY: prepareintegration
prepareintegration:
	lxc image copy images:alpine/edge local: --alias busybox \
		--alias gcr.io/cri-tools/test-image-latest:latest \
		--alias gcr.io/cri-tools/test-image-digest@sha256:9179135b4b4cc5a8721e09379244807553c318d92fa3111a65133241551ca343

.PHONY: critest
critest: checklxd $(GOPATH)/bin/critest
	$(GOPATH)/bin/critest -runtime-endpoint	$(LXESOCKET) -image-endpoint $(LXESOCKET)

.PHONY: cribench
cribench: checklxd default prepareintegration $(GOPATH)/bin/critest
	(./bin/lxe --socket $(LXESOCKETFILE) --lxd-socket $(LXDSOCKETFILE) --logfile $(LXELOGFILE) &)
	$(GOPATH)/bin/critest -benchmark -runtime-endpoint $(LXESOCKET) -image-endpoint $(LXESOCKET)

run: checklxd build
	./bin/lxe --debug --socket $(LXESOCKETFILE) --lxd-socket $(LXDSOCKETFILE) --logfile $(LXELOGFILE)