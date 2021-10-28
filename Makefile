TRAVIS_TAG ?= $(shell git rev-parse HEAD)
ARCH = $(shell go env GOOS)-$(shell go env GOARCH)
RELEASE_NAME = sequins-$(TRAVIS_TAG)-$(ARCH)

SOURCES = $(shell find . -name '*.go' -not -name '*_test.go')
TEST_SOURCES = $(shell find . -name '*_test.go')
BUILD = $(shell pwd)/third_party

VENDORED_LIBS = -lsparkey -lsnappy -lzstd

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
	CGO_PREAMBLE_LDFLAGS = -lc++ -L$(BUILD)/lib
else
	CGO_PREAMBLE_LDFLAGS = -lrt -lm -lstdc++
endif

ifneq ($(VERBOSE),)
  VERBOSITY=-v
endif

ZK_VERSION ?= 3.5.6
ZK = apache-zookeeper-$(ZK_VERSION)-bin
ZK_URL = "https://archive.apache.org/dist/zookeeper/zookeeper-$(ZK_VERSION)/$(ZK).tar.gz"

CGO_PREAMBLE = CGO_CFLAGS="-I$(BUILD)/include" CGO_LDFLAGS="$(VENDORED_LIBS) $(CGO_PREAMBLE_LDFLAGS)"
ZK_PREAMBLE  = ZOOKEEPER_BIN_PATH="$PWD/zookeeper/bin"

$(ZK):
	curl -o $(ZK).tar.gz $(ZK_URL)
	tar -zxf $(ZK).tar.gz
	rm $(ZK).tar.gz

# we link to a standard directory path so then the tests dont need to find based on version
# in the test code. this allows backward compatable testing.
zookeeper: $(ZK)
	ln -s $(ZK) zookeeper

all: sequins

sequins: $(SOURCES) $(BUILD)/lib/libsparkey.a $(BUILD)/lib/libsnappy.a
	$(CGO_PREAMBLE) go build -ldflags "-X main.sequinsVersion=$(TRAVIS_TAG)"

release: sequins
	./sequins --version
	mkdir -p $(RELEASE_NAME)
	cp sequins sequins.conf.example README.md LICENSE.txt $(RELEASE_NAME)/
	tar -cvzf $(RELEASE_NAME).tar.gz $(RELEASE_NAME)

test: $(TEST_SOURCES) zookeeper
	$(ZK_PREAMBLE) $(CGO_PREAMBLE) go test $(VERBOSITY) -short -race -timeout 2m $(shell go list ./... | grep -v vendor)
	# This test exercises some sync.Pool code, so it should be run without -race
	# as well (sync.Pool doesn't ever share objects under -race).
	$(ZK_PREAMBLE) $(CGO_PREAMBLE) go test $(VERBOSITY) -timeout 30s ./blocks -run TestBlockParallelReads

vet:
	$(CGO_PREAMBLE) go vet $(shell go list ./... | grep -v vendor)

test_functional: sequins $(TEST_SOURCES)
	$(CGO_PREAMBLE) go test $(VERBOSITY) -timeout 10m -run "^TestCluster"

clean:
	rm -rf $(BUILD)
	rm -f vendor/snappy/configure
	cd vendor/snappy && make distclean; true
	rm -f vendor/sparkey/configure
	cd vendor/sparkey && make distclean; true
	rm -f vendor/zookeeper/configure
	cd vendor/zookeeper && make distclean; true
	rm -f sequins sequins-*.tar.gz
	rm -rf $(RELEASE_NAME)

.PHONY: release test test_functional clean
