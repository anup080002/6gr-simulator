classdef ArtifactResolver
    %ARTIFACTRESOLVER Resolve qualification evidence by registered identity.
    %
    % Resolution is deliberately exact and fail-closed.  Basename
    % substring searches are not used.
    methods (Static)
        function resolver = create(sourceRunRoot, profile)
            root = string(sourceRunRoot);
            if ~isfolder(root)
                error("FULLSTACK:SourceRunMissing", ...
                    "Source run root does not exist: %s", root);
            end
            root = string(char(java.io.File(char(root)).getCanonicalPath()));
            listing = dir(fullfile(root, "**", "*"));
            listing = listing(~[listing.isdir]);
            n = numel(listing);
            relativePath = strings(n,1);
            fullPath = strings(n,1);
            fileName = strings(n,1);
            byteCount = zeros(n,1);
            sha256 = strings(n,1);
            rootPrefix = root + string(filesep);
            for index = 1:n
                candidate = string(fullfile(listing(index).folder, ...
                    listing(index).name));
                canonical = string(char(java.io.File( ...
                    char(candidate)).getCanonicalPath()));
                if ~startsWith(lower(canonical), lower(rootPrefix))
                    error("FULLSTACK:ArtifactPathOutsideRunRoot", ...
                        "Artifact path escapes the source run: %s", candidate);
                end
                fullPath(index) = canonical;
                relativePath(index) = replace( ...
                    extractAfter(canonical,strlength(rootPrefix)),"\","/");
                fileName(index) = string(listing(index).name);
                byteCount(index) = double(listing(index).bytes);
                sha256(index) = sixgr.integration.qualification. ...
                    ArtifactResolver.fileHash(canonical);
            end
            files = table(relativePath,fullPath,fileName,byteCount,sha256, ...
                'VariableNames',{'RelativePath','FullPath','FileName', ...
                'ByteCount','SHA256'});
            if ~isempty(files)
                files = sortrows(files,["RelativePath","SHA256"]);
            end

            manifestPath = fullfile(root,"reports","csv", ...
                "full_stack_artifact_manifest.csv");
            if isfile(manifestPath)
                manifest = readtable(manifestPath,"TextType","string", ...
                    "VariableNamingRule","preserve");
            else
                manifest = table();
            end
            resolver = struct();
            resolver.SourceRunRoot = root;
            resolver.RootCanonical = root;
            resolver.Files = files;
            resolver.Manifest = manifest;
            resolver.Registry = profile.SelectedArtifactRegistry;
            resolver.Aliases = sixgr.integration.qualification. ...
                EvidenceAdapterRegistry.aliases();
            resolver.InventorySHA256 = sixgr.integration.qualification. ...
                ArtifactResolver.inventoryDigest(files);
            resolver.Version = "phase18-artifact-resolver-v1";
        end

        function result = resolve(resolver, requestedIdentity)
            requested = strtrim(string(requestedIdentity));
            result = localEmptyResult(requested);
            if ismissing(requested) || strlength(requested)==0
                result.FailureCode = "FULLSTACK:ValueSourceMissing";
                result.Details = "An empty artifact identity cannot be resolved.";
                return;
            end

            registry = resolver.Registry;
            registryID = "";
            registeredName = "";
            byID = string(registry.ArtifactID)==requested;
            byName = string(registry.FileName)==requested;
            if nnz(byID)==1
                registryID = string(registry.ArtifactID(byID));
                registeredName = string(registry.FileName(byID));
            elseif nnz(byName)==1
                registryID = string(registry.ArtifactID(byName));
                registeredName = string(registry.FileName(byName));
            elseif nnz(byID)>1 || nnz(byName)>1
                result.FailureCode = "FULLSTACK:AmbiguousArtifactIdentity";
                result.Details = "Artifact identity is duplicated in the registry.";
                return;
            end

            alias = resolver.Aliases;
            aliasMask = string(alias.RequestedIdentity)==requested;
            if strlength(registeredName)==0 && nnz(aliasMask)==1
                registeredName = string(alias.CanonicalIdentity(aliasMask));
                canonicalMask = string(registry.FileName)==registeredName;
                if nnz(canonicalMask)==1
                    registryID = string(registry.ArtifactID(canonicalMask));
                end
                result.ResolutionMethod = "VERSIONED_COMPATIBILITY_ALIAS";
                result.AdapterVersion = string(alias.AdapterVersion(aliasMask));
            end

            manifest = resolver.Manifest;
            manifestMask = false(height(manifest),1);
            if ~isempty(manifest)
                if strlength(registryID)>0 && ...
                        ismember("ArtifactID",string(manifest.Properties.VariableNames))
                    manifestMask = string(manifest.ArtifactID)==registryID;
                elseif ismember("FileName",string(manifest.Properties.VariableNames))
                    manifestMask = string(manifest.FileName)==requested;
                end
            end
            if nnz(manifestMask)>1
                result.FailureCode = "FULLSTACK:AmbiguousArtifactManifestIdentity";
                result.Details = "Artifact identity has multiple manifest rows.";
                return;
            elseif nnz(manifestMask)==1
                row = manifest(manifestMask,:);
                result.ArtifactID = localTableString(row,"ArtifactID");
                result.RegisteredSHA256 = lower(localTableString(row,"SHA256"));
                relative = localTableString(row,"RelativePath");
                if strlength(relative)>0
                    result = localResolveManifestPath( ...
                        resolver,result,relative);
                    return;
                end
            end

            if strlength(registeredName)==0
                registeredName = requested;
            end
            exact = string(resolver.Files.FileName)==registeredName & ...
                arrayfun(@localAllowedRelativePath, ...
                string(resolver.Files.RelativePath));
            if nnz(exact)==0
                result.FailureCode = "FULLSTACK:ValueSourceMissing";
                result.Details = sprintf( ...
                    "Registered artifact '%s' has no exact file match.", ...
                    registeredName);
                return;
            elseif nnz(exact)>1
                result.FailureCode = "FULLSTACK:AmbiguousValueSource";
                result.Details = sprintf( ...
                    "Registered artifact '%s' has %d exact file matches.", ...
                    registeredName,nnz(exact));
                return;
            end
            result.Resolved = true;
            result.FileName = registeredName;
            result.ArtifactID = registryID;
            result.RelativePath = string(resolver.Files.RelativePath(exact));
            result.FullPath = string(resolver.Files.FullPath(exact));
            result.ActualSHA256 = string(resolver.Files.SHA256(exact));
            result.HashValid = strlength(result.RegisteredSHA256)==0 || ...
                result.RegisteredSHA256==result.ActualSHA256;
            if strlength(result.ResolutionMethod)==0
                result.ResolutionMethod = "REGISTERED_EXACT_FILE_IDENTITY";
            end
            if ~result.HashValid
                result.Resolved = false;
                result.FailureCode = "FULLSTACK:StaleArtifactHash";
                result.Details = "The registered hash differs from the file hash.";
            else
                result.Details = "Resolved through exact registered identity.";
            end
        end

        function [audit,adapterResults] = audit(resolver,applyAdapters)
            if nargin<2
                applyAdapters = true;
            end
            registry = resolver.Registry;
            n = height(registry);
            rows = repmat(localAuditRow(),n,1);
            adapterResults = sixgr.integration.qualification. ...
                EvidenceAdapterRegistry.emptyResults();
            for index = 1:n
                rows(index).ArtifactID = string(registry.ArtifactID(index));
                rows(index).Domain = string(registry.Domain(index));
                rows(index).ArtifactType = string( ...
                    registry.ArtifactType(index));
                rows(index).FileName = string(registry.FileName(index));
                rows(index).RequiredForPreset = true;
                rows(index).EvidenceClass = string( ...
                    registry.EvidenceClass(index));
                resolution = sixgr.integration.qualification. ...
                    ArtifactResolver.resolve( ...
                    resolver,rows(index).ArtifactID);
                rows(index).Present = strlength(resolution.FullPath)>0 && ...
                    isfile(resolution.FullPath);
                rows(index).RelativePath = resolution.RelativePath;
                rows(index).SHA256 = resolution.ActualSHA256;
                rows(index).HashValid = rows(index).Present && ...
                    strlength(resolution.ActualSHA256)==64 && ...
                    (strlength(resolution.RegisteredSHA256)==0 || ...
                    resolution.HashValid);
                if ~rows(index).Present
                    rows(index).FailureCode = localAuditFailure( ...
                        resolution.FailureCode,"FULLSTACK:ArtifactMissing");
                    rows(index).Details = resolution.Details;
                    continue;
                end
                try
                    if rows(index).ArtifactType=="CSV"
                        T = readtable(resolution.FullPath, ...
                            "TextType","string", ...
                            "VariableNamingRule","preserve");
                        required = localList(registry.RequiredColumns(index));
                        adapted = T;
                        if applyAdapters && ~isempty(required) && ...
                                any(~ismember(required,string( ...
                                T.Properties.VariableNames)))
                            [adapted,adapterRows] = ...
                                sixgr.integration.qualification. ...
                                EvidenceAdapterRegistry.adapt( ...
                                rows(index).FileName,T,required, ...
                                resolution.ActualSHA256);
                            if ~isempty(adapterRows)
                                adapterResults = [adapterResults; ...
                                    adapterRows]; %#ok<AGROW>
                            end
                        end
                        rows(index).RowCount = height(adapted);
                        rows(index).SchemaValid = all(ismember(required, ...
                            string(adapted.Properties.VariableNames)));
                        minimum = str2double(string( ...
                            registry.MinimumRows(index)));
                        if ~isfinite(minimum)
                            minimum = 0;
                        end
                        rows(index).MinimumRowsValid = ...
                            height(adapted)>=minimum;
                        rows(index).SemanticValid = ...
                            rows(index).SchemaValid && ...
                            localRequiredValuesValid(adapted,required);
                    elseif rows(index).ArtifactType=="PNG"
                        info = imfinfo(resolution.FullPath);
                        rows(index).Width = double(info(1).Width);
                        rows(index).Height = double(info(1).Height);
                        minimumWidth = str2double(string( ...
                            registry.MinimumWidth(index)));
                        minimumHeight = str2double(string( ...
                            registry.MinimumHeight(index)));
                        if ~isfinite(minimumWidth),minimumWidth=1;end
                        if ~isfinite(minimumHeight),minimumHeight=1;end
                        rows(index).SchemaValid = true;
                        rows(index).MinimumRowsValid = true;
                        rows(index).SemanticValid = ...
                            rows(index).Width>=minimumWidth && ...
                            rows(index).Height>=minimumHeight;
                    else
                        rows(index).SchemaValid = true;
                        rows(index).MinimumRowsValid = true;
                        rows(index).SemanticValid = true;
                    end
                    passed = rows(index).Present && ...
                        rows(index).HashValid && ...
                        rows(index).SchemaValid && ...
                        rows(index).MinimumRowsValid && ...
                        rows(index).SemanticValid;
                    rows(index).Status = localStatus(passed);
                    if passed
                        rows(index).Details = ...
                            "Exact identity, hash, schema, cardinality, and semantic checks passed.";
                    elseif ~rows(index).HashValid
                        rows(index).FailureCode = ...
                            "FULLSTACK:StaleArtifactHash";
                        rows(index).Details = ...
                            "Artifact hash is missing or stale.";
                    elseif ~rows(index).SchemaValid
                        rows(index).FailureCode = ...
                            "FULLSTACK:CSVSchemaInvalid";
                        rows(index).Details = ...
                            "Required canonical columns are absent.";
                    elseif ~rows(index).MinimumRowsValid
                        rows(index).FailureCode = ...
                            "FULLSTACK:CSVRowCountInvalid";
                        rows(index).Details = ...
                            "Artifact has fewer rows than the contract minimum.";
                    else
                        rows(index).FailureCode = ...
                            "FULLSTACK:ArtifactSemanticInvalid";
                        rows(index).Details = ...
                            "Required values, row status, or image dimensions are invalid.";
                    end
                catch ME
                    rows(index).FailureCode = string(ME.identifier);
                    rows(index).Details = string(ME.message);
                end
            end
            audit = struct2table(rows,"AsArray",true);
            if ~isempty(adapterResults)
                adapterResults = unique(adapterResults,"rows","stable");
            end
        end

        function digest = inventoryDigest(files)
            if isempty(files)
                digest = lower(string(sixgr.util.sha256Hex(uint8([]))));
                return;
            end
            lines = string(files.RelativePath) + "|" + ...
                string(files.ByteCount) + "|" + lower(string(files.SHA256));
            payload = strjoin(lines,newline) + newline;
            digest = lower(string(sixgr.util.sha256Hex( ...
                unicode2native(char(payload),"UTF-8"))));
        end

        function hash = fileHash(path)
            fid = fopen(char(string(path)),"rb");
            if fid<0
                error("FULLSTACK:ArtifactReadFailure", ...
                    "Unable to read artifact: %s",string(path));
            end
            cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
            bytes = fread(fid,Inf,"*uint8");
            hash = lower(string(sixgr.util.sha256Hex(bytes)));
        end
    end
end

function result = localResolveManifestPath(resolver,result,relative)
relative = replace(string(relative),"/",string(filesep));
candidate = string(fullfile(resolver.SourceRunRoot,relative));
canonical = string(char(java.io.File(char(candidate)).getCanonicalPath()));
rootPrefix = resolver.RootCanonical + string(filesep);
if ~startsWith(lower(canonical),lower(rootPrefix))
    result.FailureCode = "FULLSTACK:ArtifactPathOutsideRunRoot";
    result.Details = "Manifest path escapes the source run root.";
    return;
end
match = string(resolver.Files.FullPath)==canonical;
if nnz(match)==0
    result.FailureCode = "FULLSTACK:ValueSourceMissing";
    result.Details = "The exact manifest path does not exist.";
    return;
elseif nnz(match)>1
    result.FailureCode = "FULLSTACK:AmbiguousValueSource";
    result.Details = "The exact manifest path resolves more than once.";
    return;
end
result.FileName = string(resolver.Files.FileName(match));
result.RelativePath = string(resolver.Files.RelativePath(match));
result.FullPath = canonical;
result.ActualSHA256 = string(resolver.Files.SHA256(match));
result.HashValid = strlength(result.RegisteredSHA256)>0 && ...
    result.RegisteredSHA256==result.ActualSHA256;
result.ResolutionMethod = "MANIFEST_ARTIFACT_ID";
if ~result.HashValid
    result.FailureCode = "FULLSTACK:StaleArtifactHash";
    if strlength(result.RegisteredSHA256)==0
        result.Details = "The manifest has no final hash for this artifact.";
    else
        result.Details = "The manifest hash differs from the file hash.";
    end
    return;
end
result.Resolved = true;
result.Details = "Resolved through exact manifest artifact identity.";
end

function tf = localAllowedRelativePath(path)
path = lower(replace(string(path),"\","/"));
roots = ["reports/csv/","reports/json/","qualification_evidence/", ...
    "validation/","artifacts/","logs/"];
tf = any(startsWith(path,roots));
end

function value = localTableString(row,name)
if ~ismember(name,string(row.Properties.VariableNames))
    value = "";
    return;
end
raw = string(row.(char(name)));
if isempty(raw) || ismissing(raw(1))
    value = "";
else
    value = strtrim(raw(1));
end
end

function result = localEmptyResult(requested)
result = struct("RequestedIdentity",requested,"Resolved",false, ...
    "ArtifactID","","FileName","","RelativePath","","FullPath","", ...
    "RegisteredSHA256","","ActualSHA256","","HashValid",false, ...
    "ResolutionMethod","","AdapterVersion","","FailureCode","", ...
    "Details","");
end

function row = localAuditRow()
row = struct("ArtifactID","","Domain","","ArtifactType","", ...
    "FileName","","EvidenceClass","","RequiredForPreset",true, ...
    "Present",false, ...
    "RelativePath","","SHA256","","HashValid",false, ...
    "SchemaValid",false,"MinimumRowsValid",false, ...
    "SemanticValid",false,"RowCount",0,"Width",0,"Height",0, ...
    "Status","FAIL","FailureCode","","Details","");
end

function values = localList(raw)
values = strip(split(string(raw),"|"));
values = values(strlength(values)>0);
end

function tf = localRequiredValuesValid(T,required)
tf = true;
for name = reshape(required,1,[])
    raw = T.(char(name));
    if isempty(raw)
        tf = false;
        return;
    end
    if isnumeric(raw)
        if any(~isfinite(double(raw(:))))
            tf = false;
            return;
        end
    end
end
if ismember("Placeholder",string(T.Properties.VariableNames))
    raw = T.Placeholder;
    if islogical(raw) || isnumeric(raw)
        tf = tf && ~any(logical(raw));
    else
        tf = tf && ~any(ismember(lower(strtrim(string(raw))), ...
            ["true","1","yes"]));
    end
end
for name = intersect(["Source","ExecutionBackend","ApproximationMode"], ...
        string(T.Properties.VariableNames),"stable")
    text = lower(string(T.(char(name))));
    tf = tf && ~any(contains(text, ...
        ["placeholder","synthetic","fallback"]));
end
end

function value = localAuditFailure(current,fallback)
value = string(current);
if strlength(value)==0
    value = string(fallback);
end
end

function value = localStatus(tf)
if tf
    value = "PASS";
else
    value = "FAIL";
end
end
