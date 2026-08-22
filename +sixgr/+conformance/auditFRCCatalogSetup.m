function report = auditFRCCatalogSetup(varargin)
%AUDITFRCCATALOGSETUP Materialize and audit every catalog FRC transmitter.
%
% REPORT = sixgr.conformance.auditFRCCatalogSetup() executes the bounded
% setup-only path for every selected catalog row.  The report distinguishes
% catalog/contract blockers from failures raised while constructing the
% actual PDSCH/PUSCH waveform objects.  No Monte Carlo trials or proxy rows
% are used.

ip = inputParser;
ip.addParameter("CatalogPath", "", @(x) ischar(x) || isstring(x));
ip.addParameter("OutputPath", "", @(x) ischar(x) || isstring(x));
ip.addParameter("Verbose", false, ...
    @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;

catalog = sixgr.conformance.frcCatalog(opt.CatalogPath);
entries = catalog.entries;
n = numel(entries);
rows = repmat(localEmptyRow(), n, 1);
for index = 1:n
    entry = localItem(entries, index);
    row = localEmptyRow();
    row.EntryId = string(entry.id);
    row.FRC = string(entry.frc_id);
    row.Condition = string(entry.condition.id);
    row.Direction = string(entry.direction);
    try
        result = sixgr.conformance.runFRCPoint( ...
            entry.id, entry.condition.id, ...
            "CatalogPath", opt.CatalogPath, ...
            "ValidateSetupOnly", true, ...
            "RequireExactStandardExecution", false, ...
            "RequireExactDataChannelExecution", false, ...
            "PrintTable", false, "Verbose", false);
        row.DataExact = logical(result.DataChannelExecution.Exact);
        row.StandardExact = logical(result.StandardExecution.Exact);
        row.DataBlockers = strjoin(string( ...
            result.DataChannelExecution.Blockers), ";");
        row.StandardBlockers = strjoin(string( ...
            result.StandardExecution.Blockers), ";");
        row.SetupMaterialized = logical(result.SetupValidation.Pass);
    catch caught
        row.DataExact = false;
        row.StandardExact = false;
        row.SetupMaterialized = false;
        row.FailureIdentifier = string(caught.identifier);
        row.FailureMessage = string(caught.message);
    end
    rows(index) = row;
    if logical(opt.Verbose)
        fprintf("%2d/%2d %-32s data=%d standard=%d setup=%d %s\n", ...
            index, n, row.EntryId, row.DataExact, row.StandardExact, ...
            row.SetupMaterialized, row.FailureIdentifier);
    end
end
report = struct2table(rows);

outputPath = string(opt.OutputPath);
if strlength(strtrim(outputPath)) > 0
    parent = string(fileparts(outputPath));
    if strlength(parent) > 0 && ~isfolder(parent)
        mkdir(parent);
    end
    sixgr.util.csvWriteTable(char(outputPath), report, ...
        "PreserveSchema", true);
end
end

function row = localEmptyRow()
row = struct( ...
    "EntryId", "", "FRC", "", "Condition", "", "Direction", "", ...
    "DataExact", false, "StandardExact", false, ...
    "SetupMaterialized", false, "DataBlockers", "", ...
    "StandardBlockers", "", "FailureIdentifier", "", ...
    "FailureMessage", "");
end

function item = localItem(collection, index)
if iscell(collection)
    item = collection{index};
else
    item = collection(index);
end
end
