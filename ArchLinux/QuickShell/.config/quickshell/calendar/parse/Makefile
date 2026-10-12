CXX ?= g++
NODE ?= node
NODE_TESTS ?= $(shell find ../dev/tests -type f -name 'test-*.js' | sort)
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Wpedantic
ICAL_CFLAGS := $(shell pkg-config --cflags libical)
ICAL_LIBS := $(shell pkg-config --libs libical)
QT_CFLAGS := $(shell pkg-config --cflags Qt6Core) -fPIC
QT_LIBS := $(shell pkg-config --libs Qt6Core)
QMLLINT ?= $(shell pkg-config --variable=bindir Qt6Qml)/qmllint

convert: output/convert.o output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o output/series_group.o
	$(CXX) $^ $(ICAL_LIBS) $(QT_LIBS) -o convert

calendar-sync-helper: output/sync_main.o output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o output/series_group.o output/series_conflict.o output/series_resolution.o
	$(CXX) $^ $(ICAL_LIBS) $(QT_LIBS) -o calendar-sync-helper

output:
	mkdir -p $@

output/convert.o: src/main.cpp src/helper.h src/calendar_json.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) -c src/main.cpp -o output/convert.o

output/helper.o: src/helper.cpp src/helper.h src/synced_recurrence.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/helper.cpp -o output/helper.o

output/calendar_json.o: src/calendar_json.cpp src/calendar_json.h src/helper.h src/series_group.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/calendar_json.cpp -o output/calendar_json.o

output/sync_main.o: src/sync_main.cpp src/calendar_json.h src/helper.h src/recurrence.h src/series_group.h src/synced_recurrence.h src/series_conflict.h src/calendar_lock.h src/conflict_state.h src/conflict_limits.h src/series_resolution.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/sync_main.cpp -o output/sync_main.o

output/recurrence.o: src/recurrence.cpp src/recurrence.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/recurrence.cpp -o $@

output/synced_recurrence.o: src/synced_recurrence.cpp src/synced_recurrence.h src/helper.h src/recurrence.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/synced_recurrence.cpp -o $@

output/recurrence_tests: test/recurrence_tests.cpp output/recurrence.o
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -Isrc $^ $(ICAL_LIBS) $(QT_LIBS) -o $@

output/series_group_tests: test/series_group_tests.cpp src/series_group.cpp src/series_group.h src/calendar_lock.h output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o
	$(CXX) $(CXXFLAGS) -DCALENDAR_GROUP_TEST_HOOKS $(ICAL_CFLAGS) $(QT_CFLAGS) -Isrc test/series_group_tests.cpp src/series_group.cpp output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o $(ICAL_LIBS) $(QT_LIBS) -o $@

output/series_group.o: src/series_group.cpp src/series_group.h src/helper.h src/recurrence.h src/calendar_json.h src/synced_recurrence.h src/calendar_lock.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/series_group.cpp -o $@

output/series_conflict.o: src/series_conflict.cpp src/series_conflict.h src/series_group.h src/helper.h src/calendar_json.h src/conflict_limits.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/series_conflict.cpp -o $@

output/series_resolution.o: src/series_resolution.cpp src/series_resolution.h src/series_group.h src/conflict_state.h src/calendar_lock.h src/helper.h src/calendar_json.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -c src/series_resolution.cpp -o $@

output/group_codec_bridge: test/group_codec_bridge.cpp src/series_group.cpp src/series_group.h src/calendar_lock.h output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o
	$(CXX) $(CXXFLAGS) -DCALENDAR_GROUP_TEST_HOOKS $(ICAL_CFLAGS) $(QT_CFLAGS) -Isrc test/group_codec_bridge.cpp src/series_group.cpp output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o $(ICAL_LIBS) $(QT_LIBS) -o $@

output/sync_group_test_helper: output/sync_main.o src/series_group.cpp src/series_group.h src/calendar_lock.h output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o output/series_conflict.o output/series_resolution.o
	$(CXX) $(CXXFLAGS) -DCALENDAR_GROUP_TEST_HOOKS $(ICAL_CFLAGS) $(QT_CFLAGS) -Isrc output/sync_main.o src/series_group.cpp output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o output/series_conflict.o output/series_resolution.o $(ICAL_LIBS) $(QT_LIBS) -o $@

output/conflict_main.o: src/sync_main.cpp src/calendar_json.h src/helper.h src/recurrence.h src/series_group.h src/synced_recurrence.h src/series_conflict.h src/calendar_lock.h src/conflict_state.h src/conflict_limits.h src/series_resolution.h | output
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -Dmain=calendar_sync_helper_main -c src/sync_main.cpp -o $@

output/grouped_conflict_limits: test/grouped_conflict_limits.cpp src/conflict_limits.h output/conflict_main.o output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o output/series_group.o output/series_conflict.o output/series_resolution.o
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -Isrc $(filter %.cpp %.o,$^) $(ICAL_LIBS) $(QT_LIBS) -o $@

.PHONY: all test node-tests lint clean

lint:
	@set -e; for file in ../shell.qml ../common/*.js ../services/*.qml ../ui/*.qml; do "$(QMLLINT)" --ignore-settings --max-warnings 0 "$$file"; done

test: output/parser_tests output/parser_tests_ndebug output/recurrence_tests output/series_group_tests output/group_codec_bridge output/grouped_conflict_limits output/series_group.o convert calendar-sync-helper node-tests
	./output/recurrence_tests
	sh ./test/grouped_conflict_limits.sh
	sh ./test/series_group_test.sh
	./output/parser_tests
	./output/parser_tests_ndebug
	@if CALENDAR_TEST_FORCE_FAILURE=1 ./output/parser_tests_ndebug >/dev/null 2>&1; then echo "NDEBUG assertion check unexpectedly passed"; exit 1; fi
	./test/converter_test.sh
	./test/sync_helper_test.sh
	sh ./test/conflict_broker_test.sh
	sh ./test/node_test_aggregate_test.sh

node-tests: output/group_codec_bridge output/sync_group_test_helper
	@set -e; for test in $(NODE_TESTS); do $(NODE) "$$test"; done

output/parser_tests: test/parser_tests.cpp output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o output/series_group.o
	$(CXX) $(CXXFLAGS) $(ICAL_CFLAGS) $(QT_CFLAGS) -Isrc $^ $(ICAL_LIBS) $(QT_LIBS) -o $@

output/parser_tests_ndebug: test/parser_tests.cpp output/helper.o output/calendar_json.o output/recurrence.o output/synced_recurrence.o output/series_group.o
	$(CXX) $(CXXFLAGS) -DNDEBUG $(ICAL_CFLAGS) $(QT_CFLAGS) -Isrc $^ $(ICAL_LIBS) $(QT_LIBS) -o $@

clean:
	rm -f output/grouped_conflict_limits
	rm -f output/sync_group_test_helper
	rm -f output/group_codec_bridge
	rm -f output/series_group_tests
	rm -f output/recurrence_tests
	rm -f output/*.o
	rm -f convert
	rm -f calendar-sync-helper
	rm -f output/parser_tests
	rm -f output/parser_tests_ndebug
