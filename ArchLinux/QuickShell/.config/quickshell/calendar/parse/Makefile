CXX ?= g++
NODE ?= node
NODE_TESTS ?= ../dev/tests/test-*.js
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Wpedantic
ICAL_CFLAGS := $(shell pkg-config --cflags libical)
ICAL_LIBS := $(shell pkg-config --libs libical)
QT_CFLAGS := $(shell pkg-config --cflags Qt6Core) -fPIC
QT_LIBS := $(shell pkg-config --libs Qt6Core)

convert: output/convert.o output/helper.o output/calendar_json.o
	$(CXX) output/convert.o output/helper.o output/calendar_json.o $(ICAL_LIBS) $(QT_LIBS) -o convert

calendar-sync-helper: output/sync_main.o output/helper.o output/calendar_json.o
	$(CXX) output/sync_main.o output/helper.o output/calendar_json.o $(ICAL_LIBS) $(QT_LIBS) -o calendar-sync-helper

output:
	mkdir -p $@

output/convert.o: main.cpp helper.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) -c main.cpp -o output/convert.o

output/helper.o: helper.cpp helper.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c helper.cpp -o output/helper.o

output/calendar_json.o: calendar_json.cpp calendar_json.h helper.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c calendar_json.cpp -o output/calendar_json.o

output/sync_main.o: sync_main.cpp calendar_json.h helper.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c sync_main.cpp -o output/sync_main.o

.PHONY: all test node-tests clean

test: test/parser_tests test/parser_tests_ndebug convert calendar-sync-helper node-tests
	./test/parser_tests
	./test/parser_tests_ndebug
	@if CALENDAR_TEST_FORCE_FAILURE=1 ./test/parser_tests_ndebug >/dev/null 2>&1; then echo "NDEBUG assertion check unexpectedly passed"; exit 1; fi
	./test/converter_test.sh
	./test/sync_helper_test.sh
	sh ./test/conflict_broker_test.sh
	sh ./test/node_test_aggregate_test.sh

node-tests:
	@set -e; for test in $(NODE_TESTS); do $(NODE) "$$test"; done

test/parser_tests: test/parser_tests.cpp output/helper.o output/calendar_json.o
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -I. test/parser_tests.cpp output/helper.o output/calendar_json.o $(ICAL_LIBS) $(QT_LIBS) -o test/parser_tests

test/parser_tests_ndebug: test/parser_tests.cpp output/helper.o output/calendar_json.o
	$(CXX) $(CXXFLAGS) -DNDEBUG $(ICAL_CFLAGS) $(QT_CFLAGS) -I. test/parser_tests.cpp output/helper.o output/calendar_json.o $(ICAL_LIBS) $(QT_LIBS) -o test/parser_tests_ndebug

clean:
	rm -f output/*.o
	rm -f convert
	rm -f calendar-sync-helper
	rm -f test/parser_tests
	rm -f test/parser_tests_ndebug
