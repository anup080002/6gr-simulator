function validatePUCCHDetectorEpisodePolicy(v)
% Physical episode policy validation; no RF execution or qualification.
assert(isstruct(v) && isscalar(v),'test:PilotPolicy','Expected one policy.');
assert(ismember(string(v.stage),["development_pilot","held_out_campaign_episode"]) && ...
    string(v.research_class)=="optional_research_experiment",'test:PilotPolicy', ...
    'Expected a development pilot or a registered campaign episode.');
validateattributes(v.episodes,{'numeric'},{'scalar','integer','positive','finite','<=',2^32});
validateattributes(v.seed_base,{'numeric'},{'scalar','integer','nonnegative','finite','<=',2^32-1});
validateattributes(v.seed_stride,{'numeric'},{'scalar','integer','positive','finite','<=',2^32-1});
% Division avoids overflowing or rounding a large episode-count product.
assert(double(v.episodes)-1<=floor((2^32-1-double(v.seed_base))/double(v.seed_stride)), ...
    'test:PilotSeedRange','Every episode seed must be unique and fit the twister seed range.');
validateattributes(v.family_alpha,{'numeric'},{'scalar','finite','>',0,'<',1});
validateattributes(v.event_error_limit,{'numeric'},{'scalar','finite','>',0,'<',1});
validateattributes(v.qualification_episodes_per_case,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(v.last_slot,{'numeric'},{'scalar','integer','positive','finite'});
cases=v.cases;
assert(isstruct(cases) && numel(cases)==8,'test:PilotCaseCoverage','Expected eight Format-0 hypotheses.');
keys=strings(numel(cases),1); ids=strings(numel(cases),1);
for k=1:numel(cases)
    c=cases(k);
    assert((ischar(c.id) && isrow(c.id)) || (isstring(c.id) && isscalar(c.id)), ...
        'test:PilotCaseIdentity','Case ID must be scalar text.');
    ids(k)=string(c.id);
    assert(~isempty(regexp(char(ids(k)),'^[A-Za-z0-9_]+$','once')), ...
        'test:PilotCaseIdentity','Case ID must be a safe evidence filename.');
    validateattributes(c.harq_bits,{'numeric'},{'scalar','integer','finite'});
    assert(ismember(c.harq_bits,[1 2]) && islogical(c.signal_present) && isscalar(c.signal_present), ...
        'test:PilotCaseCoverage','Expected one/two HARQ bits and scalar logical signal presence.');
    assert((isnumeric(c.payload) || islogical(c.payload)) && ...
        (isempty(c.payload) || isvector(c.payload)) && all(ismember(c.payload(:),[0 1])), ...
        'test:PilotCaseCoverage','Declared payload must be a binary vector.');
    assert((~c.signal_present && isempty(c.payload)) || ...
        (c.signal_present && numel(c.payload)==c.harq_bits), ...
        'test:PilotCaseCoverage','Payload must match signal presence and width.');
    validateattributes(c.slot,{'numeric'},{'scalar','integer','finite','>',1,'<',v.last_slot});
    keys(k)=string(c.harq_bits)+":"+string(double(c.signal_present))+":"+ ...
        string(sprintf('%d',c.payload(:)));
end
required=["1:0:";"2:0:";"1:1:0";"1:1:1";"2:1:00";"2:1:01";"2:1:10";"2:1:11"];
assert(isequal(sort(keys),sort(required)),'test:PilotCaseCoverage', ...
    'Require each noise width and each signal payload exactly once; unique names alone are insufficient.');
assert(numel(unique(ids))==numel(cases) && numel(unique([cases.slot]))==numel(cases), ...
    'test:PilotCaseIdentity','Case IDs and receive slots must be unique.');
assert(isempty(intersect([cases.slot],v.srs_slots)),'test:PilotCaseIdentity', ...
    'Pilot PUCCH and SRS slots must not overlap.');
end
