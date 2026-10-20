function schema=validateInstalledReceiverCampaign(p)
% Frozen policy validation only; no physical or statistical result is made.
schema=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/installed_pdcch_campaign_schema.yaml');
id='sixgr:pdcch:InvalidInstalledCampaign';
fields(p,schema.required_fields,'campaign',id);
assert(isequal(p.schema_version,schema.schema_version),id,'Unsupported schema_version.');
name(p.profile_id,id);
for key=["stage","scope","research_class"]
    catalog=key+"s"; if key=="research_class", catalog="research_classes"; end
    assert(text(p.(key)) && any(string(p.(key))==string(schema.(catalog))),id, ...
        'Unsupported %s.',key);
end
assert(text(p.timing_boundary) && any(string(p.timing_boundary)==string(schema.timing_boundaries)), ...
    id,'Declare independent nominal radio timing, not a fabricated received alignment.');
assert(text(p.scenario_path),id,'Require the installed scenario path.');
paths=string(p.scenario_seed_paths(:));
assert(~isempty(paths)&&~any(ismissing(paths))&&all(strlength(paths)>0)&& ...
    numel(unique(paths))==numel(paths),id,'scenario_seed_paths must be distinct authored paths.');
for key=["episodes_per_case","execution_batch_episodes","seed_stride"]
    integer(p.(key),1,2^32-1,key,id);
end
for key=["seed_base","noise_seed_offset","guard_samples"]
    integer(p.(key),0,2^32-1,key,id);
end
for key=["family_alpha","event_error_limit"]
    x=p.(key);
    assert(isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x)&&x>0&&x<1,id, ...
        '%s must be strictly between zero and one.',key);
end
assert(islogical(p.development_history_complete)&&isscalar(p.development_history_complete), ...
    id,'Explicitly declare development_history_complete.');
reserved=p.development_seeds;
assert(isnumeric(reserved)&&isreal(reserved)&&(isempty(reserved)||isvector(reserved))&& ...
    all(isfinite(reserved(:))&reserved(:)>=0&reserved(:)<=2^32-1&reserved(:)==fix(reserved(:)))&& ...
    numel(unique(reserved))==numel(reserved),id,'Invalid or duplicate development seed history.');
cases=p.cases;
assert(isstruct(cases)&&~isempty(cases),id,'Require explicit H0/H1 cases.');
ids=strings(numel(cases),1); signatures=ids; contexts=ids;
for k=1:numel(cases)
    c=cases(k); fields(c,schema.case_fields,"cases("+k+")",id); ids(k)=name(c.id,id);
    assert(islogical(c.signal_present)&&isscalar(c.signal_present),id,'signal_present must be logical.');
    integer(c.ue_index,1,65535,'ue_index',id); integer(c.serving_cell,1,65535,'serving_cell',id);
    integer(c.absolute_slot0,0,2^32-1,'absolute_slot0',id);
    t=c.transmitter;
    assert(isstruct(t)&&isscalar(t),id,'transmitter must be an explicit object.');
    if ~c.signal_present
        assert(isempty(fieldnames(t)),id,'A no-signal case cannot contain a transmitter.');
    else
        fields(t,schema.transmitter_fields,'transmitter',id);
        assert(text(t.dci_format)&&isstruct(t.fields)&&isscalar(t.fields),id, ...
            'Require an installed DCI format and explicit field overrides.');
        for key=string(fieldnames(t.fields)).'
            integer(t.fields.(key),0,2^32-1,key,id);
        end
    end
    signatures(k)=sixgr.util.sha256Hex(jsonencode(rmfield(c,'id')));
    contexts(k)=sixgr.util.sha256Hex(jsonencode(rmfield(c,{'id','signal_present','transmitter'})));
end
assert(numel(unique(ids))==numel(ids)&&numel(unique(signatures))==numel(signatures),id, ...
    'Renaming a duplicate case does not create another population.');
for key=unique(contexts).'
    present=[cases(contexts==key).signal_present];
    assert(any(present)&&any(~present),id,'Every installed receive context needs H0 and H1 cases.');
end
n=double(p.episodes_per_case)*numel(cases);
assert(n<=2^32-1 && p.execution_batch_episodes<=n,id,'Invalid campaign/batch size.');
assert(p.seed_base+(n-1)*p.seed_stride+p.noise_seed_offset<=2^32-1,id,'Seed schedule overflows uint32.');
assert(p.noise_seed_offset>0 && ...
    ~(mod(p.noise_seed_offset,p.seed_stride)==0 && p.noise_seed_offset/p.seed_stride<n), ...
    id,'Channel/RF and noise schedules must be disjoint.');
if string(p.stage)=="frozen_qualification"
    for base=[p.seed_base p.seed_base+p.noise_seed_offset]
        d=double(reserved(:))-double(base);
        assert(~any(d>=0&mod(d,p.seed_stride)==0&d/p.seed_stride<n),id, ...
            'Qualification seeds overlap the declared development history.');
    end
    bestUpper=-expm1(log(p.family_alpha/(2*numel(cases)))/p.episodes_per_case);
    assert(bestUpper<=p.event_error_limit,id, ...
        'The planned population cannot meet its family bound even with zero errors.');
end
end
function fields(v,keys,path,id)
assert(isstruct(v)&&isscalar(v)&&isequal(sort(string(fieldnames(v))),sort(string(keys(:)))), ...
    id,'%s has unknown/missing fields.',path);
end
function yes=text(x)
yes=(ischar(x)||isstring(x))&&isscalar(string(x))&&~ismissing(string(x))&&strlength(strtrim(string(x)))>0;
end
function x=name(x,id)
assert(text(x)&&~isempty(regexp(char(x),'^[A-Za-z0-9_-]+$','once')),id,'Require a safe nonempty identifier.');
x=string(x);
end
function integer(x,lo,hi,key,id)
assert(isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x)&&x==fix(x)&&x>=lo&&x<=hi, ...
    id,'%s must be an integer in [%g,%g].',key,lo,hi);
end
