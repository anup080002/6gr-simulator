function coverage = auditLegacyReferenceCoverage(repositoryRoot)
%AUDITLEGACYREFERENCECOVERAGE Inventory artifacts/ without using its data.
%
% The checked-in artifacts tree is migration reference material only.  This
% audit maps old CSV/PNG names to the normalized contracts; it does not read,
% copy, adapt, or publish their content.

if nargin < 1 || strlength(string(repositoryRoot)) == 0
    repositoryRoot = sixgr.artifact.ContractCatalog.repositoryRoot();
end
repositoryRoot = char(string(repositoryRoot));
artifactRoot = fullfile(repositoryRoot, "artifacts");
if ~isfolder(artifactRoot)
    error("sixgr:artifact:LegacyReferenceRootMissing", ...
        "Legacy artifact reference root does not exist: %s", artifactRoot);
end
catalog = sixgr.artifact.ContractCatalog.load(repositoryRoot);
listing = dir(fullfile(artifactRoot, "**", "*"));
listing = listing(~[listing.isdir]);

rows = repmat(localEmptyRow(), 0, 1);
for index = 1:numel(listing)
    [~, leaf, extension] = fileparts(listing(index).name);
    extension = lower(string(extension));
    if ~any(extension == [".csv", ".png", ".jpg", ".jpeg", ".svg"])
        continue;
    end
    absolutePath = fullfile(listing(index).folder, listing(index).name);
    relativePath = string(absolutePath(numel(artifactRoot) + 2:end));
    [domain, profile] = localInferOwner(relativePath);
    fileName = string(leaf) + extension;
    if extension == ".csv"
        artifactType = "CSV";
    elseif extension == ".png"
        artifactType = "PNG";
    else
        artifactType = "LEGACY_IMAGE";
    end
    matches = false(height(catalog), 1);
    if artifactType ~= "LEGACY_IMAGE"
        matches = catalog.ArtifactType == artifactType & ...
            lower(catalog.FileName) == lower(fileName);
        if strlength(domain) > 0
            owned = matches & catalog.Domain == domain & catalog.Profile == profile;
            if any(owned)
                matches = owned;
            end
        end
    end
    row = localEmptyRow();
    row.RelativePath = relativePath;
    row.FileName = fileName;
    row.Extension = extension;
    row.InferredDomain = domain;
    row.InferredProfile = profile;
    row.Bytes = listing(index).bytes;
    row.ContractMatchCount = nnz(matches);
    row.ContractIDs = strjoin(catalog.ContractID(matches), "|");
    if artifactType == "LEGACY_IMAGE"
        row.Status = "RETIRED_NON_PNG_REFERENCE";
    elseif row.ContractMatchCount == 1
        row.Status = "COVERED_BY_NORMALIZED_CONTRACT";
    elseif row.ContractMatchCount > 1
        row.Status = "AMBIGUOUS_LEGACY_NAME";
    else
        row.Status = "UNCONTRACTED_LEGACY_REFERENCE";
    end
    rows(end + 1, 1) = row; %#ok<AGROW>
end
coverage = struct2table(rows, 'AsArray', true);
coverage = sortrows(coverage, "RelativePath");
end

function [domain, profile] = localInferOwner(relativePath)
normalized = replace(lower(string(relativePath)), "\\", "/");
top = extractBefore(normalized + "/", "/");
profile = "base";
if contains(top, "impact")
    profile = "impact";
end
domain = "";
rules = {
    "frame_grid", "frame_grid";
    "initial_access", "initial_access";
    "pdcch_dci", "pdcch";
    "pdsch_dlsch", "pdsch";
    "pucch_uci", "pucch";
    "pusch_ulsch", "pusch";
    "rsla", "rsla";
    "mimo_csi_beamforming", "mimo";
    "mac_harq_scheduling", "mac";
    "channel_geometry", "channel";
    "rf_frontend", "rf";
    "protocol_stack", "protocol";
    "waveform_generation", "waveform";
    "validation", "validation";
    "integration", "integration"};
for index = 1:size(rules, 1)
    if startsWith(top, rules{index, 1})
        domain = string(rules{index, 2});
        return;
    end
end
end

function row = localEmptyRow()
row = struct( ...
    "RelativePath", "", ...
    "FileName", "", ...
    "Extension", "", ...
    "InferredDomain", "", ...
    "InferredProfile", "", ...
    "Bytes", 0, ...
    "ContractMatchCount", 0, ...
    "ContractIDs", "", ...
    "Status", "");
end
