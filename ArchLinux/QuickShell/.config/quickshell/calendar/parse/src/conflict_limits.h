#pragma once
#include <QtGlobal>

// Match each before/after source set in series_group.cpp, including member UIDs.
inline constexpr qsizetype maxConflictSourceBytes = 16 * 1024 * 1024;
// Preserve protected previews and all bytes accepted by the existing parser.
// A source byte can occupy 6 bytes directly, 7 inside nested JSON, and 6 in
// decoded previews/identity: two 16 MiB sides * 19, plus bounded record overhead.
// This is a ceiling, not a preallocation; ordinary states remain small.
inline constexpr qsizetype maxConflictStateBytes = 616 * 1024 * 1024;
