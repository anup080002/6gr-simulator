function ok=testLDPCScenarioPolicy()
% Config-only decoder policy: no waveform, decode, iteration-consumption or
% standards-performance claim. Native primitive defaults are tested elsewhere.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
repo=fileparts(fileparts(mfilename('fullpath')));
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> % Only this unique test directory.
fixture=fullfile(repo,'simulator','configs','scenarios', ...
    'lls_tdd_four_port_received_rank_transition_fixture.yaml');
groups={@()localOriginalScenarios(repo,work),@()localPolicies(fixture,work), ...
    @()localInheritance(fixture,work),@localOverrides,@localInvalidValues,@localDefaultsAndAuthority};
names=["original_scenarios","complete_policies","per_field_inheritance", ...
    "canonical_overrides","invalid_values","defaults_and_authority"];
failures=strings(0,1);
for k=1:numel(groups)
    try
        groups{k}();
        fprintf('LDPC_SCENARIO_POLICY %s PASS\n',names(k));
    catch cause
        failures(end+1)=names(k)+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'LDPC_SCENARIO_POLICY %s FAIL %s\n',names(k),getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(isempty(failures),'test:LDPCScenarioPolicy', ...
    '%d/%d config-only groups failed:\n%s',numel(failures),numel(groups),strjoin(failures,newline));
fprintf('LDPC_SCENARIO_POLICY_PASS groups=%d configured_DL_UL_policy=1 decoded_waveforms=0\n',numel(groups));
ok=true;
end

function localOriginalScenarios(repo,work)
paths=fullfile(repo,'simulator','configs','scenarios',[
    "lls_mobile_2ue_100kmh_1sector_full_capture.yaml"
    "lls_tdd_four_port_received_rank_transition_fixture.yaml"
    "lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml"]);
limits=[50 8 8];
for k=1:numel(paths)
    before=fileread(paths(k));
    scenario=sixgr.lls6g.config.loadScenarioConfig(paths(k));
    resolved=scenario.toStruct();
    cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(work,"original_"+k));
    offset=.5; if k==1, offset=.75; end % Original mobile authored inactive offset.
    localAssertRuntime(cfg,'Normalized min-sum',.75,offset,'early',limits(k));
    assert(strcmp(string(resolved.coding.ldpc_algorithm),'Normalized min-sum')&& ...
        resolved.coding.ldpc_scaling_factor==.75&& ...
        resolved.coding.ldpc_min_sum_offset==offset&&resolved.coding.ldpc_early_termination);
    assert(strcmp(before,fileread(paths(k))),'Original scenario was modified.');
    fprintf('LDPC_SCENARIO_ORIGINAL %s maximum=%g algorithm=%s scaling=%g offset=%g termination=%s\n', ...
        paths(k),cfg.phy.ldpc.maxIterations,string(cfg.phy.ldpc.algorithm), ...
        cfg.phy.ldpc.scalingFactor,cfg.phy.ldpc.minSumOffset,string(cfg.phy.ldpc.termination));
end
end

function localPolicies(fixture,work)
catalog=sixgr.config.loadCoreCatalog();
algorithms=string(catalog.parameters.phy.ldpc.algorithm.allowed_values);
schedules=string(catalog.parameters.phy.ldpc.algorithm.schedule_types);
base=sixgr.lls6g.config.loadScenarioConfig(fixture);
for k=1:numel(algorithms)
    s=base.toStruct();
    s.coding.ldpc_algorithm=char(algorithms(k));
    s.coding.ldpc_scaling_factor=.625;
    s.coding.ldpc_min_sum_offset=.375;
    s.coding.ldpc_early_termination=mod(k,2)==0;
    s.coding.ldpc_schedule_type=char(schedules(k));
    sixgr.lls6g.config.validateScenarioConfig(s);
    cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(work,"policy_"+k));
    term="max"; if s.coding.ldpc_early_termination, term="early"; end
    localAssertRuntime(cfg,algorithms(k),.625,.375,term,8);
    assert(string(cfg.phy.ldpc.scheduleType)==schedules(k));
    % Opposite termination is also accepted without changing other policy.
    p=cfg.phy.ldpc;
    p.termination='early'; if term=="early", p.termination='max'; end
    checked=sixgr.config.validateLDPCPolicy(p);
    assert(strcmp(checked.termination,p.termination)&& ...
        checked.scalingFactor==.625&&checked.minSumOffset==.375);
end
end

function localInheritance(fixture,work)
flat="coding.ldpc_scaling_factor";
canonical="canonical_control.coding.ldpc_scaling_factor";
parent=localWrite(work,'policy_parent',fixture,localSet(struct(),flat,.625));
child=localWrite(work,'policy_child',parent, ...
    localSet(struct(),'coding.ldpc_min_sum_offset',.25));
grandchild=localWrite(work,'policy_grandchild',child,struct('meta',struct('description','unrelated child')));
s=localLoad(grandchild);
assert(s.coding.ldpc_scaling_factor==.625&&s.coding.ldpc_min_sum_offset==.25);
defaultChild=localWrite(work,'policy_explicit_default',grandchild,localSet(struct(),flat,.75));
s=localLoad(defaultChild); assert(s.coding.ldpc_scaling_factor==.75);
canon=localWrite(work,'policy_canonical',grandchild,localSet(struct(),canonical,.875));
canonChild=localWrite(work,'policy_canonical_child',canon,localSet(struct(),canonical,.5));
s=localLoad(canonChild);
assert(s.coding.ldpc_scaling_factor==.5&&s.canonical_control.coding.ldpc_scaling_factor==.5&& ...
    s.coding.ldpc_min_sum_offset==.25);
operational=localWrite(work,'policy_operational',canonChild, ...
    struct('run_control',struct('runtime_checkpoint_enable',true)));
s=localLoad(operational); assert(s.coding.ldpc_scaling_factor==.5);
bad=localWrite(work,'policy_flat_conflict',canonChild,localSet(struct(),flat,.75));
localReject(@()localLoad(bad),'sixgr:lls6g:config:LDPCPolicyConflict',[flat canonical]);
bad=localWrite(work,'policy_same_document',fixture, ...
    localSet(localSet(struct(),flat,.5),canonical,.75));
localReject(@()localLoad(bad),'sixgr:lls6g:config:LDPCPolicyConflict',[flat canonical]);
later=localWrite(work,'policy_later_parent',strings(0,1),localSet(struct(),flat,.875));
multi=localWrite(work,'policy_multi_parent',[parent later],struct());
s=localLoad(multi); assert(s.coding.ldpc_scaling_factor==.875);
% Declaring one canonical knob must not reset another flat authored knob.
termChild=localWrite(work,'policy_independent_canonical',canonChild, ...
    localSet(struct(),'canonical_control.coding.ldpc_early_termination',false));
s=localLoad(termChild);
assert(~s.coding.ldpc_early_termination&&s.coding.ldpc_scaling_factor==.5&&s.coding.ldpc_min_sum_offset==.25);
end

function localOverrides()
flat="coding.ldpc_scaling_factor";
canonical="canonical_control.coding.ldpc_scaling_factor";
s=localSet(localSet(localMinimal(),flat,.625),canonical,.875);
s=sixgr.lls6g.config.normalizeScenarioAliases(s);
assert(s.coding.ldpc_scaling_factor==.875);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
leaf=localSet(struct(),flat,.5);
localReject(@()sixgr.lls6g.config.normalizeScenarioAliases(s,'Authority',leaf), ...
    'sixgr:lls6g:config:LDPCPolicyConflict',[flat canonical]);
s.canonical_control.runtime_overrides=struct('path',{char(flat),char(flat)},'value',{.625,.5});
s=sixgr.lls6g.config.normalizeScenarioAliases(s);
assert(s.coding.ldpc_scaling_factor==.5&&s.canonical_control.coding.ldpc_scaling_factor==.5);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
bad=s; bad.canonical_control.runtime_overrides= ...
    struct('path',{char(flat),char(canonical)},'value',{.625,.5});
localReject(@()sixgr.lls6g.config.normalizeScenarioAliases(bad), ...
    'sixgr:lls6g:config:LDPCPolicyConflict',[flat canonical]);
% Canonical-only override must reach the flat execution field as well.
s.canonical_control.runtime_overrides=struct('path',char(canonical),'value',.75);
s=sixgr.lls6g.config.normalizeScenarioAliases(s);
assert(s.coding.ldpc_scaling_factor==.75&&s.canonical_control.coding.ldpc_scaling_factor==.75);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
end

function localInvalidValues()
cases={"ldpc_algorithm",{'',[],missing,'minsum',["Belief propagation","Offset min-sum"]}; ...
    "ldpc_scaling_factor",{[],0,-1,1.01,NaN,Inf,1+1i,[.5 .75],true}; ...
    "ldpc_min_sum_offset",{[],-1,NaN,Inf,1+1i,[0 .5],false}; ...
    "ldpc_early_termination",{[],0,1,NaN,'true',[true false]}; ...
    "ldpc_schedule_type",{'',[],'parallel',["flooding","layered"]}};
for k=1:size(cases,1)
    path="coding."+cases{k,1};
    for value=cases{k,2}
        bad=localSet(struct(),path,value{1});
        localReject(@()sixgr.lls6g.config.mergeLDPCPolicyAuthority(struct(),bad), ...
            'sixgr:lls6g:config:InvalidLDPCPolicy',path);
    end
end
% Native schedule is fixed by the algorithm, not an ignored free-form knob.
for pair={ {'Belief propagation','layered'}, {'Normalized min-sum','flooding'}, ...
        {'Layered belief propagation','flooding'}, {'Offset min-sum','flooding'} }
    values=pair{1};
    bad=struct('algorithm',values{1},'scheduleType',values{2});
    localReject(@()sixgr.config.validateLDPCPolicy(bad), ...
        'sixgr:config:LDPCScheduleConflict',["algorithm","scheduleType"]);
end
% Exercise real partial schema, including canonical free-form entry and []
% that the generic optional-field validator would otherwise treat as unset.
for path=["coding.ldpc_scaling_factor","canonical_control.coding.ldpc_scaling_factor"]
    localReject(@()sixgr.lls6g.config.validateScenarioConfig(localSet(struct(),path,[]),'AllowPartial',true), ...
        'sixgr:lls6g:config:InvalidLDPCPolicy',path);
end
localReject(@()sixgr.lls6g.config.validateScenarioConfig( ...
    localSet(struct(),'coding.ldpc_algorithm','unknown'),'AllowPartial',true), ...
    'sixgr:lls6g:config:BadEnumValue',"coding.ldpc_algorithm");
localReject(@()sixgr.lls6g.config.validateScenarioConfig( ...
    localSet(struct(),'coding.ldpc_scaling_factor',0),'AllowPartial',true), ...
    'sixgr:lls6g:config:ValueTooSmall',"coding.ldpc_scaling_factor");
localReject(@()sixgr.lls6g.config.validateScenarioConfig( ...
    localSet(struct(),'coding.ldpc_min_sum_offset',-1),'AllowPartial',true), ...
    'sixgr:lls6g:config:ValueTooSmall',"coding.ldpc_min_sum_offset");
end

function localDefaultsAndAuthority()
cfg=sixgr.config.defaultConfig();
localAssertRuntime(cfg,'Normalized min-sum',.75,.5,'early',12);
assert(~isfield(cfg.phy.ldpc,'scheduleType'),'Omitted optional schedule was made an independent knob.');
minimal=localMinimal();
s=sixgr.lls6g.config.normalizeScenarioAliases(minimal);
% Existing generic compatibility aliases retain empty coding fields. Their
% presence must not be mistaken for an authored LDPC policy by the new
% installer, nor removed as unrelated normalization cleanup.
for name=["data_code_type","control_code_type","base_graph"]
    assert(isfield(s.coding,name)&&isempty(s.coding.(name)), ...
        'The existing empty coding compatibility alias %s changed.',name);
end
policyNames=["ldpc_algorithm","ldpc_scaling_factor","ldpc_min_sum_offset", ...
    "ldpc_early_termination","ldpc_schedule_type"];
assert(~any(isfield(s.coding,policyNames)), ...
    'Unrelated minimal alias fixture acquired an LDPC policy.');
again=sixgr.lls6g.config.normalizeScenarioAliases(s);
assert(~any(isfield(again.coding,policyNames)), ...
    'Repeated normalization promoted empty coding aliases into an LDPC policy.');
authority=sixgr.lls6g.config.mergeLDPCPolicyAuthority(struct(), ...
    localSet(struct(),'coding.ldpc_scaling_factor',.625));
for value={0,NaN,[],1+1i}
    bad=authority; bad.Flat.ldpc_scaling_factor.Value=value{1};
    localReject(@()sixgr.lls6g.config.normalizeScenarioAliases(minimal,'LDPCPolicyAuthority',bad), ...
        'sixgr:lls6g:config:InvalidLDPCPolicy',"coding.ldpc_scaling_factor");
end
bad=authority; bad.Flat.ldpc_scaling_factor.Path="coding.ldpc_min_sum_offset";
localReject(@()sixgr.lls6g.config.normalizeScenarioAliases(minimal,'LDPCPolicyAuthority',bad), ...
    'sixgr:lls6g:config:InvalidLDPCPolicyAuthority',strings(0,1));
% Valid inactive values remain exact. Applicability is a runtime receipt,
% not permission to erase configured values or manufacture executed ones.
p=sixgr.config.validateLDPCPolicy(struct('algorithm','Belief propagation', ...
    'scalingFactor',.25,'minSumOffset',0,'termination','max','scheduleType','flooding'));
assert(p.scalingFactor==.25&&p.minSumOffset==0&&strcmp(p.termination,'max'));
end

function localAssertRuntime(cfg,algorithm,scaling,offset,termination,maximum)
p=cfg.phy.ldpc;
assert(strcmp(string(p.algorithm),string(algorithm))&&p.scalingFactor==scaling&& ...
    p.minSumOffset==offset&&strcmp(string(p.termination),string(termination))&&p.maxIterations==maximum);
for direction=["DL","UL"]
    appliedMaximum=sixgr.phy.phycode.resolveLDPCMaxIterations(cfg,'Direction',direction);
    assert(appliedMaximum==maximum);
    % Both directions consume this same explicit policy; this test does not
    % claim that a decoder call or early-termination decision was executed.
    checked=sixgr.config.validateLDPCPolicy(p);
    assert(isequaln(checked,p));
end
end
function s=localMinimal()
s=struct('frequency',struct('duplex_mode','TDD'), ...
    'link_adaptation',struct('fixed_or_amc','amc','operating_point_mode','adaptive'));
end
function s=localLoad(path)
scenario=sixgr.lls6g.config.loadScenarioConfig(path); s=scenario.toStruct();
end
function path=localWrite(work,name,parents,s)
path=string(fullfile(work,name+".json"));
if ~isempty(parents), s.inherits=string(parents); end
sixgr.util.jsonWrite(path,s);
end
function s=localSet(s,path,value)
s=sixgr.util.structSet(s,path,value);
end
function localReject(action,id,paths)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Unexpected rejection %s: %s',cause.identifier,cause.message);
    for k=1:numel(paths)
        assert(contains(string(cause.message),paths(k)),'Missing original field path %s.',paths(k));
    end
    return;
end
error('test:MissingLDPCPolicyRejection','Expected %s.',id);
end
