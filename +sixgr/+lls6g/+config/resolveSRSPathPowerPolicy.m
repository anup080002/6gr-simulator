function policy=resolveSRSPathPowerPolicy(block)
% Explicit implementation-policy detector, not a standardized accuracy gate.
if nargin==0
    policy=struct('Enabled',false,'PolicySource',"absent_disabled_legacy"); return;
end
id='sixgr:lls6g:config:SRSPathPowerPolicy';
assert(isstruct(block)&&isscalar(block),id,'SRS path-power policy must be a scalar mapping.');
catalog=sixgr.lls6g.config.loadParameterCatalog("scenario");
rules=catalog.nested_sections.kpi_srs_path_power.parameters;
mapping=["enabled","Enabled";"delay_min_us","DelayMin_us";"delay_max_us","DelayMax_us"; ...
    "delay_step_us","DelayStep_us";"peak_relative_threshold_db","PeakRelativeThreshold_dB"; ...
    "noise_threshold_db","NoiseThreshold_dB";"minimum_path_separation_us","MinimumPathSeparation_us"; ...
    "maximum_paths","MaximumPaths";"classification","Classification"];
names=string(fieldnames(rules));
assert(isequal(sort(names),sort(mapping(:,1)))&& ...
    isequal(sort(string(fieldnames(block))),sort(names)),id,'Supply exactly the complete catalog policy.');
policy=struct();
for k=1:size(mapping,1)
    name=mapping(k,1); value=block.(name); rule=rules.(name);
    switch string(rule.type)
        case "boolean", valid=islogical(value)&&isscalar(value);
        case {"number","integer"}
            valid=isnumeric(value)&&isreal(value)&&isscalar(value)&&isfinite(value);
            if valid&&string(rule.type)=="integer", valid=value==fix(value); end
            if valid&&isfield(rule,'min'), valid=value>=rule.min; end
            if valid&&isfield(rule,'max'), valid=value<=rule.max; end
        case "string"
            value=string(value); valid=isscalar(value)&&~ismissing(value)&&any(value==string(rule.allowed_values));
        otherwise, valid=false;
    end
    assert(valid,id,'Invalid kpi_spec.srs_path_power.%s.',name);
    policy.(mapping(k,2))=value;
end
assert(policy.DelayMax_us>policy.DelayMin_us&&policy.DelayStep_us>0&& ...
    policy.DelayStep_us<=policy.DelayMax_us-policy.DelayMin_us&& ...
    policy.MinimumPathSeparation_us>=policy.DelayStep_us,id,'Invalid declared delay search geometry.');
policy.PolicySource="kpi_spec.srs_path_power";
end
