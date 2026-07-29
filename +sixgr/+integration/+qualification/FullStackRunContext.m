classdef FullStackRunContext
    %FULLSTACKRUNCONTEXT Immutable run/configuration/hash binding.
    methods (Static)
        function ctx = create(cfg, scfg, runFolder, profile)
            arguments
                cfg (1,1) struct
                scfg (1,1) sixgr.lls6g.config.ScenarioConfig
                runFolder (1,1) string
                profile (1,1) struct
            end
            reports = fullfile(runFolder, "reports");
            csvDir = fullfile(reports, "csv");
            configDir = fullfile(reports, "config");
            evidenceDir = fullfile(runFolder, "qualification_evidence");
            sixgr.util.ensureFolder(csvDir);
            sixgr.util.ensureFolder(configDir);
            sixgr.util.ensureFolder(evidenceDir);

            sourcePath = string(scfg.ConfigPath);
            if ~isfile(sourcePath)
                error("FULLSTACK:SourceYAMLMissing", ...
                    "Executed source YAML does not exist: %s", sourcePath);
            end
            sourceCopy = fullfile(configDir, "source_scenario.yaml");
            sixgr.util.writeTextFile(sourceCopy, fileread(sourcePath), ...
                "MimeType", "application/x-yaml; charset=UTF-8", ...
                "ArtifactKind", "yaml");
            resolved = scfg.toStruct();
            effectivePath = fullfile(configDir, "effective_scenario.yaml");
            resolvedPath = fullfile(configDir, "resolved_scenario.yaml");
            executedPath = fullfile(configDir, "executed_scenario.yaml");
            sixgr.lls6g.config.writeYAML(effectivePath, resolved);
            sixgr.lls6g.config.writeYAML(resolvedPath, resolved);
            sixgr.lls6g.config.writeYAML(executedPath, resolved);

            store = sixgr.db.artifactStore("get_state");
            storeRunID = double(sixgr.util.structGet(store, "RunID", NaN));
            if isfinite(storeRunID)
                runID = string(sprintf("%.0f", storeRunID));
            else
                runID = string(sixgr.util.structGet(cfg, "run.runTag", ""));
                if strlength(strtrim(runID)) == 0
                    runID = string(scfg.ScenarioID) + "-" + ...
                        string(datetime("now","TimeZone","UTC", ...
                        "Format","yyyyMMdd'T'HHmmss'Z'"));
                end
            end
            sourceHash = localFileHash(sourceCopy);
            effectiveHash = localFileHash(effectivePath);
            resolvedHash = localFileHash(resolvedPath);
            executedHash = localFileHash(executedPath);
            launched = contains(lower(sourcePath), "__web_runtime_") || ...
                localEnvironmentTruth("SIXGR_WEBGUI_LAUNCHED");
            [gitCommit, gitBranch] = localGit(profile.RepositoryRoot);
            installedProducts = ver;
            toolbox = installedProducts(strcmpi( ...
                string({installedProducts.Name}),"5G Toolbox"));
            toolboxVersion = "unavailable";
            if ~isempty(toolbox)
                toolboxVersion = string(toolbox(1).Version);
            end

            ctx = struct();
            ctx.RunID = runID;
            ctx.RunFolder = runFolder;
            ctx.ReportsDir = string(reports);
            ctx.CSVDir = string(csvDir);
            ctx.ConfigDir = string(configDir);
            ctx.EvidenceDir = string(evidenceDir);
            ctx.ScenarioID = string(scfg.ScenarioID);
            ctx.ScenarioRevisionID = string(scfg.ConfigHash);
            ctx.ConfigurationRevisionID = string(scfg.ConfigHash);
            ctx.SourceYAMLPath = string(sourceCopy);
            ctx.EffectiveYAMLPath = string(effectivePath);
            ctx.ResolvedYAMLPath = string(resolvedPath);
            ctx.ExecutedYAMLPath = string(executedPath);
            ctx.SourceYAMLSHA256 = sourceHash;
            ctx.EffectiveYAMLSHA256 = effectiveHash;
            ctx.ResolvedYAMLSHA256 = resolvedHash;
            ctx.ExecutedYAMLSHA256 = executedHash;
            ctx.WebGUILaunched = launched;
            ctx.GitCommit = gitCommit;
            ctx.GitBranch = gitBranch;
            ctx.MATLABVersion = string(version);
            ctx.ToolboxVersion = toolboxVersion;
            ctx.WebGUIURL = "http://127.0.0.1:62906/";
            ctx.WebGUIAuthMode = lower(strtrim(string( ...
                getenv("SIXGR_DASHBOARD_AUTH_MODE"))));
            if strlength(ctx.WebGUIAuthMode) == 0
                ctx.WebGUIAuthMode = "open";
            end
            ctx.WebGUISecured = ctx.WebGUIAuthMode == "login";
            ctx.Owner = string(scfg.get("meta.owner", "unknown"));
            ctx.StartUTC = string(datetime("now","TimeZone","UTC", ...
                "Format","yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
            ctx.Profile = profile;
            ctx.Config = cfg;
            ctx.ScenarioConfig = scfg;

            hashesMatch = resolvedHash == executedHash;
            status = localStatus(hashesMatch);
            binding = table(runID, sourceHash, effectiveHash, resolvedHash, ...
                executedHash, hashesMatch, 0, 0, launched, ...
                ctx.WebGUIAuthMode, ctx.WebGUISecured, ...
                string(sourceCopy), string(effectivePath), ...
                string(resolvedPath), string(executedPath), status, ...
                'VariableNames', {'RunID','SourceYAMLSHA256', ...
                'EffectiveYAMLSHA256','ResolvedYAMLSHA256', ...
                'ExecutedYAMLSHA256','HashesMatch','UnknownKeyCount', ...
                'DroppedKeyCount','WebGUILaunched','WebGUIAuthMode', ...
                'WebGUISecured','SourceYAMLPath', ...
                'EffectiveYAMLPath','ResolvedYAMLPath', ...
                'ExecutedYAMLPath','Status'});
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "full_stack_config_binding.csv"), binding);
            ctx.ConfigBinding = binding;
        end

        function hash = fileHash(path)
            hash = localFileHash(path);
        end
    end
end

function hash = localFileHash(path)
fid = fopen(char(string(path)), "rb");
if fid < 0
    error("FULLSTACK:ArtifactReadFailure", ...
        "Unable to read file for hashing: %s", string(path));
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, "*uint8");
hash = lower(string(sixgr.util.sha256Hex(bytes)));
end

function tf = localEnvironmentTruth(name)
tf = ismember(lower(strtrim(string(getenv(name)))), ...
    ["1","true","yes","on"]);
end

function [commit, branch] = localGit(root)
commit = "unavailable";
branch = "unavailable";
[s1, o1] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if s1 == 0, commit = string(strtrim(o1)); end
[s2, o2] = system(sprintf('git -C "%s" rev-parse --abbrev-ref HEAD', root));
if s2 == 0, branch = string(strtrim(o2)); end
end

function value = localStatus(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end
