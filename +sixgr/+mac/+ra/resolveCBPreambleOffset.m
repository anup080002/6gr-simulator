function choice=resolveCBPreambleOffset(config,ue,receivedCount)
% Deterministic LLS/test choices WITHIN a received CB partition.
% Neither mode implements the uniform random selection of TS 38.321 5.1.2.
% This helper never selects an SSB/RO, changes RA-RNTI or configures a detector.
assert(isstruct(config)&&isscalar(config),'sixgr:mac:ra:InvalidCBPreamblePolicy', ...
    'Supply the random_access configuration object.');
localInteger(ue,1,Inf); localInteger(receivedCount,1,64);
names={'cb_preamble_selection_policy','cb_preamble_offset'};
authority="resolved_random_access_configuration";
if ~all(isfield(config,names))
    % Compatibility for direct pre-ScenarioConfig callers. The default still
    % belongs to the same YAML catalog, not a second hidden runtime policy.
    persistent defaults
    if isempty(defaults)
        root=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        globalConfig=sixgr.lls6g.config.readConfigFile(fullfile(root, ...
            'simulator','configs','defaults','global.yaml'));
        defaults=globalConfig.random_access;
    end
    for k=1:numel(names)
        if ~isfield(config,names{k}), config.(names{k})=defaults.(names{k}); end
    end
    authority="global_yaml_defaults_for_legacy_direct_configuration";
end
policy=config.cb_preamble_selection_policy;
assert((isstring(policy)&&isscalar(policy)&&~ismissing(policy)) || ...
    (ischar(policy)&&isrow(policy)), 'sixgr:mac:ra:InvalidCBPreamblePolicy', ...
    'random_access.cb_preamble_selection_policy must be scalar text.');
policy=string(policy);
assert(any(policy==["deterministic_per_ue","fixed_partition_offset"]), ...
    'sixgr:mac:ra:InvalidCBPreamblePolicy','Unsupported CB preamble selection policy.');
configured=config.cb_preamble_offset; localInteger(configured,0,63);
if policy=="fixed_partition_offset"
    assert(configured<receivedCount,'sixgr:mac:ra:InvalidCBPreamblePolicy', ...
        'random_access.cb_preamble_offset must be less than the received CB preamble count (%d).',receivedCount);
    offset=double(configured);
else
    assert(configured==0,'sixgr:mac:ra:InvalidCBPreamblePolicy', ...
        'A nonzero cb_preamble_offset requires fixed_partition_offset; do not silently ignore it.');
    offset=mod(double(ue)-1,double(receivedCount));
end
choice=struct('Policy',policy,'Offset0',offset,'ConfiguredOffset0',double(configured), ...
    'ReceivedCBPreambleCount',double(receivedCount),'UEIndex',double(ue), ...
    'Classification',"optional_research_experiment",'NormativeUniformRandomSelection',false, ...
    'AuthoritySource',authority);
end
function localInteger(value,lo,hi)
assert(isnumeric(value)&&~islogical(value)&&isreal(value)&&isscalar(value)&& ...
    isfinite(value)&&value==fix(value)&&value>=lo&&value<=hi, ...
    'sixgr:mac:ra:InvalidCBPreamblePolicy','CB policy operands must be original finite scalar integers in range.');
end
