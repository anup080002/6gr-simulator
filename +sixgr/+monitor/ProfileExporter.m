classdef ProfileExporter
    %PROFILEEXPORTER Convert MATLAB profiler output into audit artifacts.

    methods (Static)
        function profileT = export(profileInfo, runDir)
            if nargin < 1 || ~isstruct(profileInfo)
                profileInfo = struct();
            end
            sixgr.util.ensureFolder(char(string(runDir)));
            save(fullfile(runDir, "matlab_profile_raw.mat"), "profileInfo");
            profileT = sixgr.monitor.ProfileExporter.functionTable(profileInfo);
            sixgr.util.csvWriteTable(fullfile(runDir, "matlab_profile_function_table.csv"), profileT);
            sixgr.monitor.ProfileExporter.writeCallGraph(profileInfo, runDir);
            sixgr.monitor.ProfileExporter.writeHotspots(profileT, fullfile(runDir, "top_runtime_hotspots.md"));
        end

        function T = functionTable(profileInfo)
            rows = repmat(struct("function_name", "", "file_path", "", "call_count", NaN, ...
                "total_time_s", NaN, "self_time_s", NaN, "child_time_s", NaN, ...
                "average_time_s", NaN, "max_time_s", NaN, "parent_functions", "", ...
                "child_functions", "", "percentage_total_runtime", NaN, ...
                "package_area", "", "inferred_channel_or_block", ""), 0, 1);
            if ~isfield(profileInfo, "FunctionTable") || isempty(profileInfo.FunctionTable)
                T = struct2table(rows);
                return;
            end
            ft = profileInfo.FunctionTable;
            totalRuntime = sum(arrayfun(@(x)localFieldNumber(x, "TotalTime"), ft), "omitnan");
            for i = 1:numel(ft)
                total = localFieldNumber(ft(i), "TotalTime");
                self = localFieldNumber(ft(i), "SelfTime");
                calls = localFieldNumber(ft(i), "NumCalls");
                file = string(localFieldString(ft(i), ["FileName","FilePath"]));
                name = string(localFieldString(ft(i), ["FunctionName","Name"]));
                child = sixgr.monitor.ProfileExporter.relationNames(ft, ft(i), "Children");
                parent = sixgr.monitor.ProfileExporter.relationNames(ft, ft(i), "Parents");
                pct = NaN;
                if isfinite(totalRuntime) && totalRuntime > 0
                    pct = 100 * total / totalRuntime;
                end
                rows(end+1, 1) = struct("function_name", name, "file_path", file, ...
                    "call_count", calls, "total_time_s", total, "self_time_s", self, ...
                    "child_time_s", max(0, total - self), ...
                    "average_time_s", total / max(calls, 1), "max_time_s", NaN, ...
                    "parent_functions", parent, "child_functions", child, ...
                    "percentage_total_runtime", pct, ...
                    "package_area", sixgr.monitor.ProfileExporter.packageArea(file, name), ...
                    "inferred_channel_or_block", sixgr.monitor.ProfileExporter.inferChannel(file + " " + name)); %#ok<AGROW>
            end
            T = struct2table(rows);
            if ~isempty(T)
                T = sortrows(T, "total_time_s", "descend");
            end
        end

        function writeCallGraph(profileInfo, runDir)
            treePath = fullfile(runDir, "function_call_tree.json");
            dotPath = fullfile(runDir, "function_call_graph.dot");
            if ~isfield(profileInfo, "FunctionTable") || isempty(profileInfo.FunctionTable)
                sixgr.util.jsonWrite(treePath, struct("nodes", [], "edges", []));
                fid = fopen(dotPath, "w");
                if fid > 0
                    fprintf(fid, "digraph sixgr_profile {\n}\n");
                    fclose(fid);
                end
                return;
            end
            ft = profileInfo.FunctionTable;
            nodes = repmat(struct("id", 0, "function_name", "", "file_path", "", ...
                "call_count", 0, "total_time_s", 0), numel(ft), 1);
            edges = repmat(struct("source", 0, "target", 0, "source_name", "", "target_name", ""), 0, 1);
            for i = 1:numel(ft)
                nodes(i).id = i;
                nodes(i).function_name = string(localFieldString(ft(i), ["FunctionName","Name"]));
                nodes(i).file_path = string(localFieldString(ft(i), ["FileName","FilePath"]));
                nodes(i).call_count = localFieldNumber(ft(i), "NumCalls");
                nodes(i).total_time_s = localFieldNumber(ft(i), "TotalTime");
                childIdx = sixgr.monitor.ProfileExporter.relationIndexes(ft(i), "Children");
                for j = childIdx(:).'
                    if j >= 1 && j <= numel(ft)
                        edges(end+1, 1) = struct("source", i, "target", double(j), ...
                            "source_name", string(nodes(i).function_name), ...
                            "target_name", string(localFieldString(ft(j), ["FunctionName","Name"]))); %#ok<AGROW>
                    end
                end
            end
            sixgr.util.jsonWrite(treePath, struct("nodes", nodes, "edges", edges));
            fid = fopen(dotPath, "w");
            if fid > 0
                cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
                fprintf(fid, "digraph sixgr_profile {\n");
                fprintf(fid, "  rankdir=LR;\n");
                for i = 1:numel(nodes)
                    label = sixgr.monitor.ProfileExporter.dotEscape(nodes(i).function_name);
                    fprintf(fid, '  n%d [label="%s\n%.3fs"];\n', i, label, nodes(i).total_time_s);
                end
                for i = 1:numel(edges)
                    fprintf(fid, "  n%d -> n%d;\n", edges(i).source, edges(i).target);
                end
                fprintf(fid, "}\n");
            end
        end

        function writeHotspots(T, path)
            fid = fopen(path, "w");
            if fid < 0
                return;
            end
            cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
            fprintf(fid, "# Top Runtime Hotspots\n\n");
            sixgr.monitor.ProfileExporter.writeTop(fid, T, "Top 50 by total time", "total_time_s");
            sixgr.monitor.ProfileExporter.writeTop(fid, T, "Top 50 by self time", "self_time_s");
            sixgr.monitor.ProfileExporter.writeTop(fid, T, "Top 50 by call count", "call_count");
            sixgr.monitor.ProfileExporter.writeTop(fid, T, "Top 50 by average call time", "average_time_s");
            if istable(T) && height(T) > 0
                childDependence = T;
                childDependence.child_ratio = childDependence.child_time_s ./ max(childDependence.total_time_s, eps);
                sixgr.monitor.ProfileExporter.writeTop(fid, childDependence, "Top 25 high child-time dependence", "child_ratio", 25);
            end
            fprintf(fid, "\n## Suspected Avoidable Recomputations\n\n");
            fprintf(fid, "- Review high-call-count rows in `matlab_profile_function_table.csv`.\n");
            fprintf(fid, "- Review repeated carrier/grid/codebook builders in the call graph.\n");
            fprintf(fid, "- Review channel constructors and reset-like functions for per-slot recreation.\n");
        end

        function writeTop(fid, T, title, sortColumn, n)
            if nargin < 5
                n = 50;
            end
            fprintf(fid, "\n## %s\n\n", title);
            if ~(istable(T) && height(T) > 0 && ismember(sortColumn, string(T.Properties.VariableNames)))
                fprintf(fid, "No profiler rows available.\n");
                return;
            end
            T = sortrows(T, sortColumn, "descend");
            n = min(n, height(T));
            fprintf(fid, "| rank | function | total_s | self_s | calls | channel |\n");
            fprintf(fid, "|---:|---|---:|---:|---:|---|\n");
            for i = 1:n
                fprintf(fid, "| %d | `%s` | %.6g | %.6g | %.0f | %s |\n", i, ...
                    char(string(T.function_name(i))), double(T.total_time_s(i)), ...
                    double(T.self_time_s(i)), double(T.call_count(i)), ...
                    char(string(T.inferred_channel_or_block(i))));
            end
        end

        function names = relationNames(ft, entry, fieldName)
            idx = sixgr.monitor.ProfileExporter.relationIndexes(entry, fieldName);
            out = strings(0, 1);
            for j = idx(:).'
                if j >= 1 && j <= numel(ft)
                    out(end+1, 1) = string(localFieldString(ft(j), ["FunctionName","Name"])); %#ok<AGROW>
                end
            end
            names = strjoin(out, "|");
        end

        function idx = relationIndexes(entry, fieldName)
            idx = zeros(0, 1);
            if ~isfield(entry, fieldName)
                return;
            end
            rel = entry.(fieldName);
            if isempty(rel)
                return;
            end
            if isnumeric(rel)
                idx = double(rel(:));
            elseif isstruct(rel) && isfield(rel, "Index")
                idx = double([rel.Index].');
            end
            idx = idx(isfinite(idx) & idx > 0);
        end

        function area = packageArea(file, name)
            token = lower(string(file) + " " + string(name));
            parts = regexp(char(token), "\+sixgr[\\/]\+([^\\/]+)", "tokens", "once");
            if ~isempty(parts)
                area = string(parts{1});
            else
                area = "external_or_root";
            end
        end

        function ch = inferChannel(text)
            ch = sixgr.monitor.StaticInventory.inferChannel(text);
        end

        function out = dotEscape(value)
            out = strrep(char(string(value)), '\', '\\');
            out = strrep(out, '"', '\"');
        end
    end
end

function value = localFieldString(s, names)
value = "";
for name = string(names(:)).'
    if isfield(s, char(name))
        value = string(s.(char(name)));
        if numel(value) > 1
            value = strjoin(value(:), "|");
        end
        return;
    end
end
end

function value = localFieldNumber(s, name)
value = NaN;
if isfield(s, char(name))
    raw = s.(char(name));
    if isnumeric(raw) || islogical(raw)
        raw = double(raw);
        if ~isempty(raw)
            value = raw(1);
        end
    else
        value = str2double(string(raw));
    end
end
end
