function schema=validateInstalledReceiverCampaign(policy)
% Validate authored campaign policy; no waveform or qualification result.
schema=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/installed_pucch_campaign_schema.yaml');
id='sixgr:pucch:InvalidInstalledCampaign';
localFields(policy,schema.required_fields,'campaign',id);
assert(policy.schema_version==schema.schema_version,id,'Unsupported campaign schema_version.');
localName(policy.profile_id,'profile_id',id);
for spec=["stage","scope","research_class"]
    catalog=spec+"s";
    if spec=="research_class", catalog="research_classes"; end
    assert(isscalar(string(policy.(spec))) && any(string(policy.(spec))==string(schema.(catalog))), ...
        id,'Invalid %s; use an authored schema value.',spec);
end
assert(isscalar(string(policy.scenario_path)) && strlength(string(policy.scenario_path))>0, ...
    id,'scenario_path must identify the installed scenario.');
paths=string(policy.scenario_seed_paths(:));
assert(~isempty(paths) && ~any(ismissing(paths)) && all(strlength(paths)>0) && ...
    numel(unique(paths))==numel(paths),id,'scenario_seed_paths must be distinct authored paths.');
for name=["episodes_per_case","execution_batch_episodes","seed_stride"]
    localInteger(policy.(name),1,2^32-1,name,id);
end
for name=["seed_base","noise_seed_offset","guard_samples"]
    localInteger(policy.(name),0,2^32-1,name,id);
end
for name=["family_alpha","event_error_limit"]
    x=policy.(name);
    assert(isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x)&&x>0&&x<1, ...
        id,'%s must be between zero and one.',name);
end
assert(islogical(policy.development_history_complete)&&isscalar(policy.development_history_complete), ...
    id,'development_history_complete must be explicitly declared.');
reserved=policy.development_seeds;
assert(isnumeric(reserved)&&isreal(reserved)&&(isempty(reserved)||isvector(reserved)) && ...
    all(isfinite(reserved(:))&reserved(:)>=0&reserved(:)<=2^32-1&reserved(:)==fix(reserved(:))) && ...
    numel(unique(reserved))==numel(reserved),id,'Invalid or duplicate development_seeds.');
cases=policy.cases;
assert(isstruct(cases)&&~isempty(cases),id,'At least one paired H0/H1 case context is required.');
ids=strings(numel(cases),1); signatures=ids; contexts=ids;
for k=1:numel(cases)
    c=cases(k); localFields(c,schema.case_fields,"cases("+k+")",id);
    ids(k)=localName(c.id,"case id",id);
    for name=["signal_present","csi_requested"]
        assert(islogical(c.(name))&&isscalar(c.(name)),id,'Case %s: %s must be logical.',ids(k),name);
    end
    for name=["ue_index","serving_cell","rnti"]
        localInteger(c.(name),1,65535,name,id);
    end
    for name=["absolute_slot0","resource_id","harq_bit_count","sr_bit_count"]
        localInteger(c.(name),0,2^32-1,name,id);
    end
    assert(any(string(c.resource_selection_procedure)==string(schema.resource_procedures)), ...
        id,'Case %s: unsupported resource_selection_procedure.',ids(k));
    t=c.transmitter;
    assert(isstruct(t)&&isscalar(t),id,'transmitter must be an explicit object (empty for H0).');
    if ~c.signal_present
        assert(isempty(fieldnames(t)),id,'H0 must not contain a transmitter payload or control state.');
    else
        localFields(t,schema.transmitter_fields,'transmitter',id);
        b=t.harq_bits;
        assert((isnumeric(b)||islogical(b))&&isreal(b)&&(isempty(b)||isvector(b)) && ...
            all(isfinite(b(:)))&&all(b(:)==0|b(:)==1),id,'harq_bits must be binary.');
        assert(isstruct(t.csi)&&isscalar(t.csi),id,'csi must be an explicit object.');
        if ~isempty(fieldnames(t.csi))
            localFields(t.csi,schema.csi_fields,'transmitter.csi',id);
            localInteger(t.csi.rank,1,8,'rank',id);
            for name=["pmi","cri","cqi_cw0"]
                localInteger(t.csi.(name),0,2^32-1,name,id);
            end
        end
        assert(~isempty(b)||~isempty(fieldnames(t.csi)),id, ...
            'This DMRS-bearing campaign requires a HARQ or CSI transmitter; no implicit SR-only waveform.');
        localFields(t.control,schema.control_fields,'transmitter.control',id);
        for name=string(schema.control_fields(:)).'
            localInteger(t.control.(name),0,2^32-1,name,id);
        end
        assert(t.control.k1+t.control.pdsch_end_slot==c.absolute_slot0+1, ...
            id,'Declared K1 and one-based PDSCH end slot must target absolute_slot0+1.');
        requests=t.scheduling_requests;
        assert(isstruct(requests)||isempty(requests),id,'scheduling_requests must contain explicit procedure states.');
        for r=1:numel(requests)
            localFields(requests(r),schema.sr_fields,'scheduling_requests',id);
            localInteger(requests(r).id,0,2^32-1,'SR id',id);
            for name=["pending_positive","prohibit_timer_active"]
                assert(islogical(requests(r).(name))&&isscalar(requests(r).(name)),id,'SR flags must be logical.');
            end
        end
        if ~isempty(requests)
            assert(numel(unique([requests.id]))==numel(requests),id,'Duplicate SR procedure identity.');
        end
    end
    signatures(k)=sixgr.util.sha256Hex(jsonencode(rmfield(c,'id')));
    contexts(k)=sixgr.util.sha256Hex(jsonencode(rmfield(c,{'id','signal_present','transmitter'})));
end
assert(numel(unique(ids))==numel(ids)&&numel(unique(signatures))==numel(signatures), ...
    id,'Renaming a duplicate case does not create an independent population.');
for key=unique(contexts).'
    present=[cases(contexts==key).signal_present];
    assert(any(present)&&any(~present),id,'Each receive hypothesis requires both H0 and H1 coverage.');
end
n=double(policy.episodes_per_case)*numel(cases);
assert(n<=2^32-1 && policy.execution_batch_episodes<=n,id,'Campaign/batch budget is invalid.');
last=double(policy.seed_base)+(n-1)*double(policy.seed_stride)+double(policy.noise_seed_offset);
assert(last<=2^32-1,id,'Channel/RF/noise seed schedules overflow uint32.');
assert(policy.noise_seed_offset>0 && ...
    ~(mod(policy.noise_seed_offset,policy.seed_stride)==0 && policy.noise_seed_offset/policy.seed_stride<n), ...
    id,'Noise and channel/RF seed schedules must not overlap.');
if string(policy.stage)=="frozen_qualification"
    for base=[policy.seed_base policy.seed_base+policy.noise_seed_offset]
        d=double(reserved(:))-double(base);
        assert(~any(d>=0 & mod(d,policy.seed_stride)==0 & d/policy.seed_stride<n), ...
            id,'Qualification seeds overlap declared development history.');
    end
    bestUpper=-expm1(log(policy.family_alpha/(2*numel(cases)))/policy.episodes_per_case);
    assert(bestUpper<=policy.event_error_limit,id, ...
        'episodes_per_case cannot meet the family confidence gate even with zero errors.');
end
end
function localFields(v,names,path,id)
assert(isstruct(v)&&isscalar(v)&&isequal(sort(string(fieldnames(v))),sort(string(names(:)))), ...
    id,'%s has missing or unknown fields; expected: %s.',path,strjoin(string(names),', '));
end
function name=localName(value,path,id)
name=string(value);
assert(isscalar(name)&&~ismissing(name)&&~isempty(regexp(char(name),'^[A-Za-z0-9_-]+$','once')), ...
    id,'%s must be a nonempty safe identifier.',path);
end
function localInteger(x,lo,hi,name,id)
assert(isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x)&&x==fix(x)&&x>=lo&&x<=hi, ...
    id,'%s must be an integer in [%g,%g].',name,lo,hi);
end

