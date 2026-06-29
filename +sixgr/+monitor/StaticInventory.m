classdef StaticInventory
    %STATICINVENTORY Scan +sixgr source files and compare with profile use.

    methods (Static)
        function [inventoryT, unusedT] = export(repoRoot, runDir, profileT)
            if nargin < 3
                profileT = table();
            end
            inventoryT = sixgr.monitor.StaticInventory.scan(repoRoot);
            sixgr.util.csvWriteTable(fullfile(runDir, "static_function_inventory.csv"), inventoryT);
            unusedT = sixgr.monitor.StaticInventory.classifyUsage(inventoryT, profileT);
            sixgr.util.csvWriteTable(fullfile(runDir, "unused_function_report.csv"), unusedT);
        end

        function T = scan(repoRoot)
            root = fullfile(char(string(repoRoot)), "+sixgr");
            files = dir(fullfile(root, "**", "*.m"));
            rows = repmat(sixgr.monitor.StaticInventory.defaultRow(), 0, 1);
            for i = 1:numel(files)
                path = fullfile(files(i).folder, files(i).name);
                txt = "";
                try
                    txt = string(fileread(path));
                catch
                end
                lines = splitlines(txt);
                nonempty = lines(strlength(strtrim(lines)) > 0);
                commentMask = startsWith(strtrim(nonempty), "%");
                funcs = regexp(char(txt), "(?m)^\s*function\s+(?:\[[^\]]+\]\s*=\s*)?(?:[A-Za-z]\w*\s*=\s*)?([A-Za-z]\w*)", "tokens");
                funcs = string([funcs{:}]);
                cls = regexp(char(txt), "(?m)^\s*classdef\s+(?:\([^\)]*\)\s*)?([A-Za-z]\w*)", "tokens", "once");
                primary = "";
                if ~isempty(cls)
                    primary = string(cls{1});
                elseif ~isempty(funcs)
                    primary = funcs(1);
                else
                    [~, primary] = fileparts(path);
                    primary = string(primary);
                end
                rel = erase(string(path), string(repoRoot) + filesep);
                rel = replace(rel, "\", "/");
                localFuncs = "";
                if numel(funcs) > 1
                    localFuncs = strjoin(funcs(2:end), "|");
                end
                row = sixgr.monitor.StaticInventory.defaultRow();
                row.file_path = rel;
                row.package_path = sixgr.monitor.StaticInventory.packagePath(rel);
                row.primary_function_or_class = primary;
                row.local_functions = localFuncs;
                row.class_methods = "";
                row.line_count = numel(lines);
                row.comment_line_count = sum(commentMask);
                row.code_line_count = max(0, numel(nonempty) - sum(commentMask));
                row.contains_todo = contains(lower(txt), "todo");
                row.contains_fallback = contains(lower(txt), "fallback");
                row.contains_simplified = contains(lower(txt), "simplified");
                row.contains_dummy = contains(lower(txt), "dummy");
                row.contains_placeholder = contains(lower(txt), "placeholder");
                row.contains_bypass = contains(lower(txt), "bypass");
                row.contains_try_catch = contains(lower(txt), "try") && contains(lower(txt), "catch");
                row.contains_empty_catch = ~isempty(regexp(char(txt), "(?s)catch\s*(?:%[^\n]*)?\n\s*end", "once"));
                row.contains_return_early = ~isempty(regexp(char(txt), "(?m)^\s*return\s*(?:;)?\s*$", "once"));
                row.contains_warning_only = contains(lower(txt), "warning(");
                row.contains_not_implemented = contains(lower(txt), "not implemented") || contains(lower(txt), "not_implemented");
                row.inferred_domain = sixgr.monitor.StaticInventory.inferDomain(rel);
                row.inferred_channel = sixgr.monitor.StaticInventory.inferChannel(rel + " " + primary + " " + txt);
                rows(end+1, 1) = row; %#ok<AGROW>
            end
            T = struct2table(rows);
            if isempty(T)
                T = struct2table(sixgr.monitor.StaticInventory.defaultRows());
            end
        end

        function T = classifyUsage(inventoryT, profileT)
            profileFiles = strings(0, 1);
            profileNames = strings(0, 1);
            if istable(profileT) && height(profileT) > 0
                if ismember("file_path", string(profileT.Properties.VariableNames))
                    profileFiles = lower(replace(string(profileT.file_path), "\", "/"));
                end
                if ismember("function_name", string(profileT.Properties.VariableNames))
                    profileNames = lower(string(profileT.function_name));
                end
            end
            rows = repmat(struct("function_or_method", "", "file_path", "", ...
                "static_domain", "", "static_channel", "", "was_called", false, ...
                "call_count", NaN, "total_time_s", NaN, "classification", ""), 0, 1);
            for i = 1:height(inventoryT)
                rel = string(inventoryT.file_path(i));
                name = string(inventoryT.primary_function_or_class(i));
                fileHit = any(endsWith(profileFiles, lower(rel)));
                nameHit = any(contains(profileNames, lower(name)));
                wasCalled = fileHit || nameHit;
                callCount = 0;
                totalTime = 0;
                if wasCalled && istable(profileT) && height(profileT) > 0
                    mask = false(height(profileT), 1);
                    if ismember("file_path", string(profileT.Properties.VariableNames))
                        mask = mask | endsWith(lower(replace(string(profileT.file_path), "\", "/")), lower(rel));
                    end
                    if ismember("function_name", string(profileT.Properties.VariableNames))
                        mask = mask | contains(lower(string(profileT.function_name)), lower(name));
                    end
                    if any(mask)
                        if ismember("call_count", string(profileT.Properties.VariableNames))
                            callCount = sum(double(profileT.call_count(mask)), "omitnan");
                        end
                        if ismember("total_time_s", string(profileT.Properties.VariableNames))
                            totalTime = sum(double(profileT.total_time_s(mask)), "omitnan");
                        end
                    end
                end
                cls = "UNKNOWN";
                if wasCalled
                    cls = "CALLED";
                elseif contains(rel, "+report/") || contains(rel, "+analytics/") || contains(rel, "+visual/")
                    cls = "REPORT_ONLY";
                elseif contains(rel, "+legacy/") || contains(lower(name), "legacy")
                    cls = "LEGACY_DUPLICATE";
                elseif logical(inventoryT.contains_fallback(i))
                    cls = "FALLBACK_ONLY";
                elseif contains(rel, "+ai/") || contains(rel, "+ntn/") || contains(rel, "+v2x/")
                    cls = "NOT_CALLED_EXPECTED_INACTIVE";
                else
                    cls = "NOT_CALLED_UNEXPECTED";
                end
                rows(end+1, 1) = struct("function_or_method", name, "file_path", rel, ...
                    "static_domain", string(inventoryT.inferred_domain(i)), ...
                    "static_channel", string(inventoryT.inferred_channel(i)), ...
                    "was_called", logical(wasCalled), "call_count", double(callCount), ...
                    "total_time_s", double(totalTime), "classification", string(cls)); %#ok<AGROW>
            end
            T = struct2table(rows);
        end

        function row = defaultRow()
            row = struct("file_path", "", "package_path", "", "primary_function_or_class", "", ...
                "local_functions", "", "class_methods", "", "line_count", NaN, ...
                "comment_line_count", NaN, "code_line_count", NaN, "contains_todo", false, ...
                "contains_fallback", false, "contains_simplified", false, "contains_dummy", false, ...
                "contains_placeholder", false, "contains_bypass", false, "contains_try_catch", false, ...
                "contains_empty_catch", false, "contains_return_early", false, ...
                "contains_warning_only", false, "contains_not_implemented", false, ...
                "inferred_domain", "", "inferred_channel", "");
        end

        function rows = defaultRows()
            rows = repmat(sixgr.monitor.StaticInventory.defaultRow(), 0, 1);
        end

        function p = packagePath(rel)
            parts = split(string(rel), "/");
            pkg = parts(startsWith(parts, "+"));
            p = strjoin(erase(pkg, "+"), ".");
        end

        function d = inferDomain(rel)
            rel = lower(string(rel));
            domains = ["phy","link","channel","l2","rf","energy","truth","lls6g","mimo","beamforming","config","report","analytics","perf","validation"];
            d = "unknown";
            for x = domains
                if contains(rel, "+" + x + "/")
                    d = x;
                    return;
                end
            end
        end

        function ch = inferChannel(text)
            text = lower(string(text));
            pairs = [
                "PDSCH","pdsch"
                "PUSCH","pusch"
                "PDCCH","pdcch"
                "PUCCH","pucch"
                "PRACH","prach"
                "PBCH_SSB","pbch|ssb|pss|sss|sib1|broadcast"
                "SRS","srs"
                "TRS","trs"
                "CSI_RS","csi-rs|csirs|csi_rs"
                "BEAMFORMING","beam|pmi|precod"
                "HARQ","harq"
                "CHANNEL_RF","channel|rf|interfer"
                ];
            ch = "general";
            for i = 1:size(pairs, 1)
                if ~isempty(regexp(char(text), char(pairs(i, 2)), "once"))
                    ch = pairs(i, 1);
                    return;
                end
            end
        end
    end
end
