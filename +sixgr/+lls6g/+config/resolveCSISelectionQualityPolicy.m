function policy=resolveCSISelectionQualityPolicy(block)
%RESOLVECSISELECTIONQUALITYPOLICY Validate an explicit YAML study policy.
% No argument means an absent legacy block, which stays disabled. A supplied
% block is fully validated even when disabled; [] is not an absent policy.
% Numeric defaults and supported values live in the YAML catalog/defaults.
% Execution, never configuration, supplies actual amplitude units and planes.
if nargin==0
    policy=struct('Enabled',false,'PolicySource',"absent_disabled_legacy");
    return;
end
prefix="kpi_spec.csi_selection_quality";
assert(isstruct(block) && isscalar(block), ...
    'sixgr:lls6g:config:CSISelectionQualityPolicy', ...
    '%s must be a complete scalar policy mapping when present.',prefix);
catalog=sixgr.lls6g.config.loadParameterCatalog("scenario");
rules=catalog.nested_sections.kpi_csi_selection_quality.parameters;
names=string(fieldnames(rules));
unknown=setdiff(string(fieldnames(block)),names);
assert(isempty(unknown),'sixgr:lls6g:config:CSISelectionQualityPolicy', ...
    '%s contains unsupported field(s): %s. Actual power units/planes come from execution.', ...
    prefix,strjoin(unknown,', '));
for name=names.'
    rule=rules.(name); path=prefix+"."+name;
    assert(isfield(block,name),'sixgr:lls6g:config:CSISelectionQualityPolicy', ...
        '%s must be explicit, including when this study is disabled.',path);
    value=block.(name);
    switch string(rule.type)
        case "boolean"
            valid=islogical(value) && isscalar(value);
        case "number"
            valid=isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value);
            if valid && isfield(rule,'min'), valid=value>=rule.min; end
            if valid && isfield(rule,'max'), valid=value<=rule.max; end
        case "string"
            valid=(ischar(value) && isrow(value)) || (isstring(value) && isscalar(value));
            if valid
                value=string(value);
                valid=~ismissing(value) && any(value==string(rule.allowed_values));
            end
        otherwise
            error('sixgr:lls6g:config:CSISelectionQualityCatalog', ...
                'Unsupported catalog type %s for %s.',string(rule.type),path);
    end
    assert(valid,'sixgr:lls6g:config:CSISelectionQualityPolicy', ...
        '%s violates its explicit catalog rule: %s.',path,string(jsonencode(rule)));
end
mapping=["enabled","Enabled";"objective","Objective";"receiver","Receiver"; ...
    "power_normalization","PowerNormalization";"power_factor","PowerFactor"; ...
    "support","Support";"research_class","ResearchClass"; ...
    "classification","Classification";"tie_absolute_tolerance","TieAbsoluteTolerance"; ...
    "physical_power_tolerance","PhysicalPowerTolerance"];
assert(isequal(sort(names),sort(mapping(:,1))), ...
    'sixgr:lls6g:config:CSISelectionQualityCatalog', ...
    'Every CSI selection-quality catalog field needs an explicit runtime binding.');
policy=struct();
for index=1:size(mapping,1)
    name=mapping(index,1); value=block.(name);
    if string(rules.(name).type)=="string", value=string(value); end
    if string(rules.(name).type)=="number", value=double(value); end
    policy.(mapping(index,2))=value;
end
policy.PolicySource=prefix;
end
