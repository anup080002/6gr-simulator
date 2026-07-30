classdef QualificationArtifactAuditNormalizer
    %QUALIFICATIONARTIFACTAUDITNORMALIZER Adapt producer schemas explicitly.
    methods (Static)
        function T = aliasRegistry()
            T = table( ...
                ["ArtifactType";"ArtifactType";"ArtifactType"; ...
                "ArtifactType";"ArtifactType";"ArtifactType"; ...
                "RelativePath";"RelativePath";"RelativePath"; ...
                "RelativePath"], ...
                ["ArtifactType";"ArtifactKind";"FileKind";"FileType"; ...
                "Type";"Format";"RelativePath";"ArtifactPath"; ...
                "LogicalPath";"Path"], ...
                repmat("phase18-artifact-audit-aliases/v1",10,1), ...
                'VariableNames',{'CanonicalField','InputAlias', ...
                'MappingVersion'});
        end

        function [canonical,diagnostic] = normalize(raw,varargin)
            parser = inputParser;
            parser.addParameter("Registry",table(),@istable);
            parser.addParameter("RunID","",@(x)ischar(x)||isstring(x));
            parser.parse(varargin{:});
            registry = parser.Results.Registry;
            runID = string(parser.Results.RunID);
            diagnostic = localDiagnostic("PASS","", ...
                "Artifact audit normalized to the canonical schema.", ...
                localSchemaName(raw));
            try
                canonical = localNormalize(raw,registry,runID);
            catch ME
                canonical = sixgr.integration.qualification. ...
                    QualificationArtifactAuditSchema.empty();
                diagnostic = localDiagnostic("FAIL", ...
                    "FULLSTACK:ArtifactAuditSchemaInvalid", ...
                    string(ME.identifier)+": "+string(ME.message), ...
                    localSchemaName(raw));
            end
        end

        function canonical = require(raw,varargin)
            [canonical,diagnostic] = sixgr.integration.qualification. ...
                QualificationArtifactAuditNormalizer.normalize(raw,varargin{:});
            if string(diagnostic.Status) ~= "PASS"
                error("FULLSTACK:ArtifactAuditSchemaInvalid", ...
                    "%s",string(diagnostic.Details));
            end
        end
    end
end

function canonical = localNormalize(raw,registry,defaultRunID)
if ~istable(raw)
    error("FULLSTACK:ArtifactAuditNotTable", ...
        "Artifact audit input must be a MATLAB table.");
end
n = height(raw);
canonical = sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.empty(n);
if n == 0
    return;
end
names = string(raw.Properties.VariableNames);
artifactID = localText(raw,["ArtifactID","ArtifactId","ID"], ...
    compose("UNRESOLVED-%05d",(1:n)'));
fileName = localText(raw, ...
    ["RelativePath","ArtifactPath","LogicalPath","FileName","Path"], ...
    strings(n,1));
registryRows = localRegistryRows(registry,artifactID,fileName);

canonical.RunID = localText(raw,["RunID","RunId"], ...
    repmat(defaultRunID,n,1));
canonical.ArtifactID = artifactID;
canonical.Domain = localText(raw,["Domain","ArtifactDomain"], ...
    localRegistryText(registry,registryRows,"Domain",n));
canonical.SubcaseID = localText(raw,["SubcaseID","SubcaseId"], ...
    localRegistryText(registry,registryRows,"SubcaseID",n));
canonical.RelativePath = replace(localText(raw, ...
    ["RelativePath","ArtifactPath","LogicalPath","Path","FileName"], ...
    fileName),"\","/");

[artifactType,typeSource] = localArtifactType(raw,names,registry, ...
    registryRows,canonical.RelativePath);
canonical.ArtifactType = artifactType;
canonical.ArtifactTypeSource = typeSource;
canonical.MIMEType = localText(raw,["MIMEType","MimeType","ContentType"], ...
    sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.mimeFor(artifactType));
canonical.Required = localTruth(localAny(raw, ...
    ["Required","RequiredForPreset","Mandatory"],true(n,1)));
canonical.Present = localTruth(localAny(raw,["Present","Exists"],false(n,1)));
canonical.SchemaValid = localTruth(localAny(raw, ...
    ["SchemaValid","HeaderValid"],canonical.Present));
canonical.HashValid = localTruth(localAny(raw, ...
    ["HashValid","ChecksumValid"],canonical.Present));
canonical.SemanticValid = localTruth(localAny(raw, ...
    ["SemanticValid","SemanticAuditValid"],canonical.Present));
canonical.SHA256 = lower(localText(raw,["SHA256","ArtifactSHA256"], ...
    strings(n,1)));
canonical.ByteCount = localNumber(raw,["ByteCount","Bytes"],zeros(n,1));
canonical.GeneratedUTC = localText(raw, ...
    ["GeneratedUTC","GeneratedAtUTC"],strings(n,1));
canonical.SourceArtifactIDs = localText(raw, ...
    ["SourceArtifactIDs","SourceArtifactID"],strings(n,1));
canonical.SourceCSVRelativePath = replace(localText(raw, ...
    ["SourceCSVRelativePath","SourceCSV","SourcePath"], ...
    localRegistryText(registry,registryRows,"SourceCSV",n)),"\","/");
canonical.SourceCSV_SHA256 = lower(localText(raw, ...
    ["SourceCSV_SHA256","SourceCSVHash"],strings(n,1)));
canonical.SemanticAuditStatus = upper(localText(raw, ...
    ["SemanticAuditStatus"],localSemanticStatus(canonical)));
canonical.ProvenanceClass = localText(raw, ...
    ["ProvenanceClass","EvidenceClass","Source"], ...
    localRegistryText(registry,registryRows,"EvidenceClass",n));
canonical.PublicationStatus = upper(localPublication(raw,n));

explicitStatus = upper(localText(raw,["Status","Validity"],strings(n,1)));
canonical.Status = localStatus(canonical,explicitStatus);
canonical.Valid = canonical.Status=="PASS";
canonical.FailureCode = localText(raw,["FailureCode","ErrorCode"], ...
    strings(n,1));
missingCode = strlength(canonical.FailureCode)==0 & canonical.Status~="PASS";
canonical.FailureCode(missingCode) = localFailureCode(canonical.Status(missingCode));

allowedTypes = sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.ArtifactTypes;
badType = ~ismember(canonical.ArtifactType,allowedTypes);
if any(badType)
    error("FULLSTACK:UnsupportedCanonicalArtifactType", ...
        "Unsupported artifact type(s): %s", ...
        strjoin(unique(canonical.ArtifactType(badType)),", "));
end
allowedStatus = sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.StatusValues;
if any(~ismember(canonical.Status,allowedStatus))
    error("FULLSTACK:UnsupportedCanonicalArtifactStatus", ...
        "Canonical status reduction produced an unsupported value.");
end
if numel(unique(canonical.ArtifactID)) ~= n
    error("FULLSTACK:DuplicateCanonicalArtifactID", ...
        "ArtifactID must identify exactly one canonical artifact row.");
end
end

function [type,source] = localArtifactType(raw,names,registry,rows,path)
n = height(raw);
aliases = ["ArtifactType","ArtifactKind","FileKind","FileType", ...
    "Type","Format"];
present = aliases(ismember(aliases,names));
if numel(present) > 1
    candidates = strings(n,numel(present));
    for index=1:numel(present)
        candidates(:,index) = upper(strtrim(string(raw.(char(present(index))))));
    end
    contradiction = false(n,1);
    for row=1:n
        values = unique(candidates(row,strlength(candidates(row,:))>0));
        contradiction(row) = numel(values)>1;
    end
    if any(contradiction)
        error("FULLSTACK:ContradictoryArtifactTypeAliases", ...
            "Artifact type aliases disagree for %d row(s).",nnz(contradiction));
    end
end
if ~isempty(present)
    type = upper(strtrim(string(raw.(char(present(1))))));
    source = repmat("explicit:"+present(1),n,1);
else
    type = strings(n,1);
    source = strings(n,1);
end
registryType = localRegistryText(registry,rows,"ArtifactType",n);
explicit = strlength(type)>0;
contradictsRegistry = explicit & strlength(registryType)>0 & ...
    upper(type)~=upper(registryType);
if any(contradictsRegistry)
    error("FULLSTACK:ContradictoryRegistryArtifactType", ...
        "Explicit and registry artifact types disagree for %d row(s).", ...
        nnz(contradictsRegistry));
end
useRegistry = strlength(type)==0 & strlength(registryType)>0;
type(useRegistry) = upper(registryType(useRegistry));
source(useRegistry) = "registry:ArtifactType";
useExtension = strlength(type)==0;
type(useExtension) = sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.typeFromPath(path(useExtension));
if any(useExtension & type=="OTHER")
    error("FULLSTACK:UnknownArtifactExtension", ...
        "Unknown or extensionless artifacts require an explicit type.");
end
source(useExtension) = ...
    "DERIVED_FROM_EXTENSION:phase18-extension-map/v1";
end

function rows = localRegistryRows(registry,artifactID,fileName)
n = numel(artifactID);
rows = zeros(n,1);
if isempty(registry)
    return;
end
names = string(registry.Properties.VariableNames);
for index=1:n
    mask = false(height(registry),1);
    if ismember("ArtifactID",names) && strlength(artifactID(index))>0
        mask = string(registry.ArtifactID)==artifactID(index);
    end
    if ~any(mask) && ismember("FileName",names) && strlength(fileName(index))>0
        mask = string(registry.FileName)==string(fileName(index));
    end
    if nnz(mask)>1
        error("FULLSTACK:AmbiguousArtifactRegistryJoin", ...
            "Registry join for artifact %s is not one-to-one.",artifactID(index));
    end
    if nnz(mask)==1
        rows(index)=find(mask,1);
    end
end
end

function out = localRegistryText(registry,rows,name,n)
out = strings(n,1);
if isempty(registry) || ~ismember(name,string(registry.Properties.VariableNames))
    return;
end
mask = rows>0;
out(mask) = string(registry.(char(name))(rows(mask)));
end

function value = localText(T,aliases,fallback)
value = string(localAny(T,aliases,fallback));
value(ismissing(value)) = "";
end

function value = localNumber(T,aliases,fallback)
raw = localAny(T,aliases,fallback);
if isnumeric(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
value(~isfinite(value)) = 0;
end

function value = localAny(T,aliases,fallback)
names = string(T.Properties.VariableNames);
found = aliases(ismember(aliases,names));
if isempty(found)
    value = fallback;
else
    value = T.(char(found(1)));
end
end

function tf = localTruth(value)
if islogical(value)
    tf = value;
elseif isnumeric(value)
    tf = isfinite(value) & value~=0;
else
    tf = ismember(lower(strtrim(string(value))), ...
        ["true","1","yes","pass","required","valid","published"]);
end
tf = reshape(logical(tf),[],1);
end

function status = localSemanticStatus(T)
status = repmat("UNAVAILABLE",height(T),1);
status(T.Present & T.SemanticValid) = "PASS";
status(T.Present & ~T.SemanticValid) = "FAIL";
end

function status = localPublication(raw,n)
names = string(raw.Properties.VariableNames);
if ismember("PublicationStatus",names)
    status = string(raw.PublicationStatus);
elseif ismember("WebGUIPublished",names)
    published = localTruth(raw.WebGUIPublished);
    status = repmat("UNPUBLISHED",n,1);
    status(published) = "PUBLISHED";
else
    status = repmat("UNAVAILABLE",n,1);
end
end

function status = localStatus(T,explicit)
status = repmat("FAIL",height(T),1);
status(~T.Required & ~T.Present) = "NOT_APPLICABLE";
status(T.Required & ~T.Present) = "MISSING";
status(T.Present & ~T.SchemaValid) = "INVALID_SCHEMA";
status(T.Present & T.SchemaValid & ~T.HashValid) = "INVALID_HASH";
status(T.Present & T.SchemaValid & T.HashValid & ~T.SemanticValid) = ...
    "INVALID_SEMANTICS";
pass = T.Present & T.SchemaValid & T.HashValid & T.SemanticValid;
status(pass) = "PASS";
unavailable = ismember(explicit,["UNAVAILABLE","NOT_APPLICABLE"]) & ~pass;
status(unavailable) = explicit(unavailable);
end

function code = localFailureCode(status)
code = repmat("FULLSTACK:ArtifactInvalid",numel(status),1);
code(status=="MISSING") = "FULLSTACK:ArtifactMissing";
code(status=="INVALID_SCHEMA") = "FULLSTACK:ArtifactSchemaInvalid";
code(status=="INVALID_HASH") = "FULLSTACK:ArtifactHashInvalid";
code(status=="INVALID_SEMANTICS") = "FULLSTACK:ArtifactSemanticInvalid";
code(status=="UNAVAILABLE") = "FULLSTACK:ArtifactUnavailable";
code(status=="NOT_APPLICABLE") = "";
end

function diagnostic = localDiagnostic(status,code,details,sourceSchema)
diagnostic = table( ...
    sixgr.integration.qualification.QualificationArtifactAuditSchema.Version, ...
    string(sourceSchema),string(status),string(code),string(details), ...
    'VariableNames',{'TargetSchemaVersion','SourceSchema', ...
    'Status','FailureCode','Details'});
end

function value = localSchemaName(raw)
if ~istable(raw)
    value = string(class(raw));
    return;
end
names = string(raw.Properties.VariableNames);
if ismember("SchemaVersion",names) && ~isempty(raw)
    value = string(raw.SchemaVersion(1));
elseif all(ismember(["ArtifactID","FileName","RequiredForPreset"],names))
    value = "phase18-artifact-completeness-combined/v0";
elseif all(ismember(["ArtifactID","ArtifactType","RelativePath"],names))
    value = "phase18-artifact-resolver/v0";
else
    value = "unrecognized-table-schema";
end
end
