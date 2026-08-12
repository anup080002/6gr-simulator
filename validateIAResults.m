function result = validateIAResults(runFolder)
%VALIDATEIARESULTS Read and reduce a persisted IA truth contract.
runFolder=char(string(runFolder));
required=["truth_contract.csv" "artifact_verification.csv" "manifest.json"];
for k=1:numel(required)
    if exist(fullfile(runFolder,required(k)),"file")~=2
        error("sixgr:phy:ia:c0:validation:MissingArtifact", ...
            "Required IA validation artifact is absent: %s.",required(k));
    end
end
gates=readtable(fullfile(runFolder,"truth_contract.csv"), ...
    "Delimiter",",","TextType","string", ...
    "VariableNamingRule","preserve");
artifacts=readtable(fullfile(runFolder,"artifact_verification.csv"), ...
    "Delimiter",",","TextType","string", ...
    "VariableNamingRule","preserve");
manifest=jsondecode(fileread(fullfile(runFolder,"manifest.json")));
applicable=localLogicalColumn(gates.Applicable,"Applicable");
gatePass=localLogicalColumn(gates.Pass,"Pass");
artifactPass=localLogicalColumn(artifacts.Pass,"Pass");
result=struct("Gates",gates,"Artifacts",artifacts,"Manifest",manifest, ...
    "ApplicablePass",all(gatePass(applicable)), ...
    "ArtifactPass",all(artifactPass), ...
    "TDocPass",logical(manifest.TDocPass)&&all(artifactPass));
end

function values=localLogicalColumn(raw,name)
if islogical(raw)
    values=raw;
elseif isnumeric(raw)
    values=isfinite(raw)&raw~=0;
else
    tokens=lower(strtrim(string(raw)));
    valid=tokens=="1"|tokens=="0"|tokens=="true"|tokens=="false";
    if ~all(valid)
        error("sixgr:phy:ia:c0:validation:InvalidLogicalColumn", ...
            "Column %s contains a nonlogical token.",name);
    end
    values=tokens=="1"|tokens=="true";
end
values=logical(values(:));
end
