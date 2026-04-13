function appendLogLine(levelStr, timeStr, msgStr)
sixgr.db.artifactStore("append_log", levelStr, timeStr, msgStr);
end
