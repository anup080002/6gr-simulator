classdef LogProgressAnalyzer
    %LOGPROGRESSANALYZER Extract actual simulator progress from run.log.

    methods (Static)
        function T = export(runDir)
            logPath = fullfile(char(string(runDir)), "run.log");
            T = sixgr.monitor.LogProgressAnalyzer.analyze(logPath);
            sixgr.util.csvWriteTable(fullfile(char(string(runDir)), "runtime_log_progress_summary.csv"), T);
        end

        function T = analyze(logPath)
            logPath = char(string(logPath));
            if exist(logPath, "file") ~= 2
                T = sixgr.monitor.LogProgressAnalyzer.emptyTable();
                return;
            end
            txt = string(fileread(logPath));
            lines = splitlines(txt);
            lineCount = numel(lines);
            ts = regexp(char(txt), "\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\]", "tokens");
            firstTime = ""; lastTime = ""; elapsed = NaN;
            if ~isempty(ts)
                firstTime = string(ts{1}{1});
                lastTime = string(ts{end}{1});
                try
                    t0 = datetime(firstTime, "InputFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
                    t1 = datetime(lastTime, "InputFormat", "yyyy-MM-dd'T'HH:mm:ss'Z'", "TimeZone", "UTC");
                    elapsed = seconds(t1 - t0);
                catch
                    elapsed = NaN;
                end
            end
            slotMatches = regexp(char(txt), "slot[= ](\d+)/(\d+)", "tokens");
            lastSlot = NaN; totalSlots = NaN;
            if ~isempty(slotMatches)
                lastSlot = str2double(slotMatches{end}{1});
                totalSlots = str2double(slotMatches{end}{2});
            end
            progress = lastSlot / max(totalSlots, 1);
            projected = NaN;
            remaining = NaN;
            if isfinite(elapsed) && elapsed > 0 && isfinite(progress) && progress > 0
                projected = elapsed / progress;
                remaining = max(0, projected - elapsed);
            end
            grants = sixgr.monitor.LogProgressAnalyzer.numericMatches(txt, "grants=(\d+)");
            executable = sixgr.monitor.LogProgressAnalyzer.numericMatches(txt, "executable_grants=(\d+)");
            active = sixgr.monitor.LogProgressAnalyzer.numericMatches(txt, "active=(\d+)");
            prach = sixgr.monitor.LogProgressAnalyzer.numericMatches(txt, "prach_attempts=(\d+)");
            access = regexp(char(txt), "access=(\d+)/(\d+)", "tokens");
            lastAccessNumerator = NaN;
            lastAccessDenominator = NaN;
            if ~isempty(access)
                lastAccessNumerator = str2double(access{end}{1});
                lastAccessDenominator = str2double(access{end}{2});
            end
            T = table(string(logPath), lineCount, firstTime, lastTime, elapsed, ...
                lastSlot, totalSlots, progress, projected, remaining, ...
                max(grants, [], "omitnan"), max(executable, [], "omitnan"), ...
                max(active, [], "omitnan"), max(prach, [], "omitnan"), ...
                lastAccessNumerator, lastAccessDenominator, ...
                'VariableNames', {'LogPath','LineCount','FirstTimestampUTC','LastTimestampUTC', ...
                'ObservedElapsed_s','LastSlot','TotalSlots','ProgressFraction', ...
                'ProjectedTotalRuntime_s','ProjectedRemainingRuntime_s','MaxGrantsPerLogLine', ...
                'MaxExecutableGrantsPerLogLine','MaxActivePerLogLine','MaxPRACHAttemptsPerSlot', ...
                'LastAccessCompleteUEs','LastAccessTotalUEs'});
        end

        function vals = numericMatches(txt, pattern)
            m = regexp(char(txt), pattern, "tokens");
            vals = NaN;
            if isempty(m)
                return;
            end
            vals = zeros(numel(m), 1);
            for i = 1:numel(m)
                vals(i) = str2double(m{i}{1});
            end
        end

        function T = emptyTable()
            T = table("", 0, "", "", NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
                'VariableNames', {'LogPath','LineCount','FirstTimestampUTC','LastTimestampUTC', ...
                'ObservedElapsed_s','LastSlot','TotalSlots','ProgressFraction', ...
                'ProjectedTotalRuntime_s','ProjectedRemainingRuntime_s','MaxGrantsPerLogLine', ...
                'MaxExecutableGrantsPerLogLine','MaxActivePerLogLine','MaxPRACHAttemptsPerSlot', ...
                'LastAccessCompleteUEs','LastAccessTotalUEs'});
        end
    end
end
