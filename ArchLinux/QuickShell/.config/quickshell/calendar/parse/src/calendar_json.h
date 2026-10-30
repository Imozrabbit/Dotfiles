#pragma once

#include "helper.h"
#include <string>
#include <vector>

std::string serializeCalendar(std::vector<Event> events, const std::string &sourceId);
std::string serializeSyncedCalendar(std::vector<Event> events, const std::string &sourceId,
                                    const std::vector<std::string> &warnings = {});
std::string eventRevision(const Event &event);
// Caller holds calendar directory lock; source files are canonical.
bool rebuildSyncedCache(const std::string &directory, const std::string &output,
                         const std::string &sourceId, std::string &error, bool strict = false);
// Caller holds collection/runtime locks. Never scan source directory as fallback.
bool validateSyncedCache(const std::string &output, const std::string &sourceId,
                         std::string &error, bool allowMissing = false);
bool updateSyncedCache(const std::string &output, const std::string &sourceId,
                       const std::vector<std::string> &removedUids, std::vector<Event> replacements,
                       std::string &error, bool allowMissing = false);
bool refreshSyncedCacheEntry(const std::string &directory, const std::string &output,
                            const std::string &sourceId, const std::string &uid, std::string &error);
// Header-only search: remote resource names need not be hashes of their UIDs.
bool syncedSourcePath(const std::string &directory, const std::string &uid, std::string &path, std::string &error);
