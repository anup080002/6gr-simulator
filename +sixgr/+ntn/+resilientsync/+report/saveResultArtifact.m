function record = saveResultArtifact(runDirectory, relativeBase, data, evidenceClass, metadata)
%SAVERESULTARTIFACT Persist data with a provenance and unit sidecar.

arguments
    runDirectory (1,1) string
    relativeBase (1,1) string
    data
    evidenceClass (1,1) string
    metadata (1,1) struct = struct()
end
allowed = ["ANALYTICAL","MONTE_CARLO_GEOMETRY","CALIBRATED_LLS", ...
    "SCHEDULER_SYSTEM","EVENT_PROCEDURE","ARCHITECTURE_DIAGRAM"];
if ~ismember(evidenceClass, allowed)
    error("sixgr:ntn:resilientsync:InvalidEvidenceClass", ...
        "Artifact evidence class %s is not permitted.", char(evidenceClass));
end
base = fullfile(char(runDirectory), char(relativeBase));
folder = fileparts(base);
if exist(folder, "dir") ~= 7, mkdir(folder); end

paths = strings(0,1);
if istable(data)
    if height(data) == 0
        error("sixgr:ntn:resilientsync:EmptyPrimaryArtifact", ...
            "Primary artifact %s may not contain fallback or empty rows.", char(relativeBase));
    end
    csvPath = string(base) + ".csv";
    writetable(data, csvPath);
    paths(end+1,1) = csvPath;
elseif isnumeric(data) || islogical(data)
    if isempty(data)
        error("sixgr:ntn:resilientsync:EmptyPrimaryArtifact", ...
            "Primary artifact %s is empty.", char(relativeBase));
    end
else
    if isempty(data)
        error("sixgr:ntn:resilientsync:EmptyPrimaryArtifact", ...
            "Primary artifact %s is empty.", char(relativeBase));
    end
end
matPath = string(base) + ".mat";
save(matPath, "data", "-v7.3");
paths(end+1,1) = matPath;

sidecar = metadata;
sidecar.SchemaVersion = "sixgr.ntn.resilientsync.artifact/v1";
sidecar.EvidenceClass = evidenceClass;
sidecar.Measured = evidenceClass == "CALIBRATED_LLS";
sidecar.ProxyUsed = false;
sidecar.FallbackUsed = false;
sidecar.RelativeBase = relativeBase;
sidecar.CreatedUTC = string(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss'Z'"));
if istable(data)
    sidecar.RowCount = height(data);
    sidecar.Columns = string(data.Properties.VariableNames);
    units = string(data.Properties.VariableUnits);
    if isempty(units), units = repmat("",1,width(data)); end
    sidecar.ColumnUnits = units;
end
jsonPath = string(base) + ".metadata.json";
localWriteJSON(jsonPath, sidecar);
paths(end+1,1) = jsonPath;
record = table(relativeBase, evidenceClass, sidecar.Measured, ...
    strjoin(paths,"|"), "PRODUCED", ...
    'VariableNames', {'RelativeBase','EvidenceClass','Measured','Paths','Status'});
end

function localWriteJSON(path, value)
text = jsonencode(value, "PrettyPrint", true);
fid = fopen(path, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:ntn:resilientsync:ArtifactWriteFailed", ...
        "Unable to open JSON artifact %s.", char(path));
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", text);
end
