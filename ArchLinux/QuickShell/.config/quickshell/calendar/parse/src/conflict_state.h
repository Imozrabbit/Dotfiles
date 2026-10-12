#pragma once
#include "helper.h"
#include <QJsonObject>
#include <filesystem>
#include <string>

// Caller owns conflict-state directory lock.
bool readConflictState(const std::filesystem::path &path, QJsonObject &state, std::string &error);
bool writeConflictState(const std::filesystem::path &path, const QJsonObject &state, std::string &error);
bool readSingleEvent(const std::filesystem::path &path, Event &event, std::string &raw, std::string &error);
// pimsync retains open descriptors to these buffers: never replace their inode.
bool writeConflictBuffer(const std::filesystem::path &path, const std::string &expected,
                         const std::string &selected, std::string &error);
