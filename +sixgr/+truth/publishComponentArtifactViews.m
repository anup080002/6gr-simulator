function out = publishComponentArtifactViews(runFolder, options)
%PUBLISHCOMPONENTARTIFACTVIEWS Publish hash-verified component-facing mirrors.
% Canonical artifacts are never moved or relabeled. Each published file is
% a byte-identical convenience mirror whose source and hashes are recorded.

arguments
    runFolder (1,1) string
    options.Enabled (1,1) logical = true
    options.Required (1,1) logical = true
end

out = struct("Enabled", options.Enabled, "Required", options.Required, ...
    "Ok", true, "ManifestPath", "", "PublishedCount", 0, ...
    "SkippedLegacySVGCount", 0, "Rows", localEmptyTable());
if ~options.Enabled
    return;
end
root = string(java.io.File(char(runFolder)).getCanonicalPath());
if ~isfolder(root)
    error("sixgr:truth:componentViews:MissingRunFolder", ...
        "Run folder does not exist: %s", root);
end

specs = localSpecs();
componentRoots = string({specs.Folder});
files = dir(fullfile(root, "**", "*"));
files = files(~[files.isdir]);
rows = repmat(localEmptyRow(), 0, 1);
for idx = 1:numel(files)
    sourcePath = string(fullfile(files(idx).folder, files(idx).name));
    rel = localRelativePath(root, sourcePath);
    firstPart = extractBefore(rel + "/", "/");
    if any(firstPart == componentRoots) || ...
            rel == "reports/csv/component_artifact_publication_manifest.csv"
        continue;
    end
    [~, stem, ext] = fileparts(sourcePath);
    ext = lower(string(ext));
    component = localClassify(rel, specs);
    if strlength(component) == 0
        continue;
    end
    if ext == ".svg"
        out.SkippedLegacySVGCount = out.SkippedLegacySVGCount + 1;
        continue;
    end
    kind = localKind(ext);
    if strlength(kind) == 0
        continue;
    end
    sourceHash = localFileSHA256(sourcePath);
    targetDir = fullfile(root, component, kind);
    if ~isfolder(targetDir)
        mkdir(targetDir);
    end
    targetPath = fullfile(targetDir, string(stem) + ext);
    if isfile(targetPath)
        existingHash = localFileSHA256(targetPath);
        if existingHash ~= sourceHash
            targetPath = fullfile(targetDir, string(stem) + "__" + ...
                extractBefore(sourceHash, 13) + ext);
        end
    end
    if ~isfile(targetPath) || localFileSHA256(targetPath) ~= sourceHash
        [copied, message] = copyfile(sourcePath, targetPath, "f");
        if ~copied
            error("sixgr:truth:componentViews:CopyFailed", ...
                "Unable to publish %s to %s: %s", sourcePath, targetPath, message);
        end
    end
    publishedHash = localFileSHA256(targetPath);
    if publishedHash ~= sourceHash
        error("sixgr:truth:componentViews:HashMismatch", ...
            "Component mirror hash mismatch for %s.", targetPath);
    end
    info = dir(targetPath);
    row = localEmptyRow();
    row.Component = component;
    row.ArtifactType = kind;
    row.CanonicalRelativePath = rel;
    row.PublishedRelativePath = localRelativePath(root, targetPath);
    row.CanonicalSHA256 = sourceHash;
    row.PublishedSHA256 = publishedHash;
    row.ByteSize = double(info.bytes);
    row.MirrorOnly = true;
    row.CanonicalAuthorityRetained = true;
    row.SourceTruthClassification = "byte_identical_canonical_mirror";
    row.PublishStatus = "PUBLISHED_HASH_VERIFIED";
    rows(end + 1, 1) = row; %#ok<AGROW>
end

if isempty(rows)
    T = localEmptyTable();
else
    T = struct2table(rows);
    T = sortrows(T, ["Component", "ArtifactType", "PublishedRelativePath"]);
end
manifestPath = fullfile(root, "reports", "csv", ...
    "component_artifact_publication_manifest.csv");
sixgr.util.csvWriteTable(manifestPath, T);
out.ManifestPath = localRelativePath(root, manifestPath);
out.PublishedCount = height(T);
out.Rows = T;
out.Ok = ~options.Required || all(T.PublishStatus == "PUBLISHED_HASH_VERIFIED");
end

function specs = localSpecs()
specs = struct( ...
    "Folder", {"prach","initial_access","ssb","pdcch","pdsch", ...
        "pusch","pucch","reference_signals","mimo","waveform", ...
        "l2","l3","traffic"}, ...
    "Tokens", {{"prach","random_access","four_step_ra","contention"}, ...
        {"initial_access","sib1","attach_state","cell_acquisition"}, ...
        {"ssb","pbch","pss","sss"}, ...
        {"pdcch","dci","coreset","search_space"}, ...
        {"pdsch","dlsch","dl_pdsch","dl_scheduler_grant"}, ...
        {"pusch","ulsch","ul_pusch","ul_scheduler_grant"}, ...
        {"pucch","uci_"}, ...
        {"csi_rs","csirs","srs","trs","dmrs","ptrs","reference_signal"}, ...
        {"mimo","beamforming","beam_","precoder","rank_layer"}, ...
        {"waveform","ofdm","constellation","spectrum","spectral"}, ...
        {"/mac","mac_","harq","rlc","pdcp","sdap","bearer"}, ...
        {"rrc","handover","mobility_event"}, ...
        {"traffic","packet_flow","flow_","goodput","latency","qos"}});
end

function component = localClassify(relativePath, specs)
text = lower("/" + replace(string(relativePath), "\", "/"));
component = "";
for idx = 1:numel(specs)
    if any(contains(text, string(specs(idx).Tokens)))
        component = string(specs(idx).Folder);
        return;
    end
end
end

function kind = localKind(ext)
if ext == ".csv"
    kind = "csv";
elseif any(ext == [".png", ".jpg", ".jpeg"])
    kind = "image";
elseif ext == ".json"
    kind = "json";
elseif ext == ".mat"
    kind = "mat";
else
    kind = "";
end
end

function relative = localRelativePath(root, pathValue)
rootText = replace(string(root), "\", "/");
pathText = replace(string(pathValue), "\", "/");
prefix = rootText + "/";
if ~startsWith(lower(pathText), lower(prefix))
    error("sixgr:truth:componentViews:PathEscape", ...
        "Artifact path is outside the run folder: %s", pathText);
end
relative = extractAfter(pathText, strlength(prefix));
end

function hash = localFileSHA256(pathValue)
fid = fopen(pathValue, "rb");
if fid < 0
    error("sixgr:truth:componentViews:ReadFailed", ...
        "Unable to read artifact for hashing: %s", pathValue);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, "*uint8");
hash = string(sixgr.util.sha256Hex(bytes));
end

function row = localEmptyRow()
row = struct("Component", "", "ArtifactType", "", ...
    "CanonicalRelativePath", "", "PublishedRelativePath", "", ...
    "CanonicalSHA256", "", "PublishedSHA256", "", "ByteSize", 0, ...
    "MirrorOnly", true, "CanonicalAuthorityRetained", true, ...
    "SourceTruthClassification", "", "PublishStatus", "");
end

function T = localEmptyTable()
T = struct2table(repmat(localEmptyRow(), 0, 1));
end
