function coverage = registerContractEvidence(registry, domain, profile, payload, provenanceRoot, varargin)
%REGISTERCONTRACTEVIDENCE Register one subsystem's fresh runtime outputs.
%
% payload.Tables and payload.Renderers are scalar structs keyed by the
% contract filename without its extension (made MATLAB-valid).  Values must
% be in-memory tables and explicit figure-renderer function handles.  Paths
% and previously generated artifacts are rejected by construction.

arguments
    registry (1,1) sixgr.artifact.EvidenceRegistry
    domain {mustBeTextScalar}
    profile {mustBeTextScalar}
    payload (1,1) struct
    provenanceRoot {mustBeTextScalar}
end
arguments (Repeating)
    varargin
end
parser = inputParser();
parser.addParameter("Catalog", table(), @istable);
parser.addParameter("RequireComplete", false, @(x) islogical(x) && isscalar(x));
parser.parse(varargin{:});

catalog = parser.Results.Catalog;
if isempty(catalog)
    catalog = sixgr.artifact.ContractCatalog.load();
end
domain = lower(string(domain));
profile = lower(string(profile));
selected = catalog(lower(catalog.Domain) == domain & ...
    lower(catalog.Profile) == profile, :);
if isempty(selected)
    error("sixgr:artifact:UnknownContractOwner", ...
        "No artifact contract rows exist for %s/%s.", domain, profile);
end
tables = sixgr.util.structGet(payload, "Tables", struct());
renderers = sixgr.util.structGet(payload, "Renderers", struct());
if ~isstruct(tables) || ~isscalar(tables) || ...
        ~isstruct(renderers) || ~isscalar(renderers)
    error("sixgr:artifact:MalformedEvidencePayload", ...
        "payload.Tables and payload.Renderers must be scalar structs.");
end

rows = repmat(localEmptyRow(), height(selected), 1);
for index = 1:height(selected)
    contract = selected(index, :);
    fieldName = matlab.lang.makeValidName(erase(contract.FileName, ...
        [".csv", ".png"]));
    row = localEmptyRow();
    row.ContractID = contract.ContractID;
    row.ArtifactType = contract.ArtifactType;
    row.FileName = contract.FileName;
    row.Required = contract.Required;
    row.PayloadField = fieldName;
    producer = string(provenanceRoot) + "." + fieldName;
    if contract.ArtifactType == "CSV"
        if isfield(tables, fieldName) && istable(tables.(fieldName))
            registry.registerTable(domain, profile, contract.FileName, ...
                tables.(fieldName), producer);
            row.Registered = true;
            row.Status = "REGISTERED_RUNTIME_TABLE";
        else
            row.Status = "MISSING_RUNTIME_TABLE";
        end
    else
        if isfield(renderers, fieldName) && ...
                isa(renderers.(fieldName), "function_handle")
            registry.registerRenderer(domain, profile, contract.FileName, ...
                renderers.(fieldName), producer);
            row.Registered = true;
            row.Status = "REGISTERED_EXPLICIT_RENDERER";
        else
            row.Status = "MISSING_EXPLICIT_RENDERER";
        end
    end
    rows(index) = row;
end
coverage = struct2table(rows, 'AsArray', true);
requiredMissing = coverage.Required & ~coverage.Registered;
if parser.Results.RequireComplete && any(requiredMissing)
    missing = coverage.FileName(requiredMissing);
    error("sixgr:artifact:IncompleteSubsystemEvidence", ...
        "%s/%s lacks %d required runtime producers: %s", ...
        domain, profile, nnz(requiredMissing), strjoin(missing, ", "));
end
end

function row = localEmptyRow()
row = struct( ...
    "ContractID", "", ...
    "ArtifactType", "", ...
    "FileName", "", ...
    "Required", false, ...
    "PayloadField", "", ...
    "Registered", false, ...
    "Status", "NOT_EVALUATED");
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:artifact:TextScalarRequired", ...
        "Artifact evidence owner fields must be text scalars.");
end
end
