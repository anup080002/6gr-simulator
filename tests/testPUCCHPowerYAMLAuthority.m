function ok=testPUCCHPowerYAMLAuthority()
% Configured power authority -> typed state -> native PUCCH TX samples.
% Declared PL is a component input, not an acquired measurement or RF trial.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> % This unique fixture folder only.
base=string(fullfile(pwd,'simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
original=read(base);
checks={@()inheritance(base,work),@()conflicts(base,original,work), ...
    @()overrides(original),@()nativePower(original), ...
    @()alphaScope(original),@()roundTrip(original,work)};
names=["authored_inheritance","conflicts_and_raw_types","sweep_runtime_overrides", ...
    "typed_native_power","alpha_and_static_source_scope","resolved_reload"];
passed=false(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('PUCCH_POWER_YAML_PASS %s\n',names(k));
    catch cause
        fprintf(2,'PUCCH_POWER_YAML_FAIL %s %s\n',names(k),getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(all(passed),'test:PUCCHPowerYAMLAuthority','Passed %d/%d groups.',nnz(passed),numel(passed));
ok=true;
end

function inheritance(base,work)
[left,right]=paths();
authored=setValue(struct(),left(1),-86);
authored.pucch_resources.power_control.delta_f_db=1.25;
authored.pucch_resources.power_control.closed_loop_adjustment_db=-2;
parent=write(work,'parent',base,authored);
child=write(work,'child',parent,setValue(struct(),right(1),-84));
leaf=write(work,'unrelated_child',child,struct('meta',struct('description','Power authority fixture')));
s=read(leaf); equal(s,left(1),right(1),-84);
assert(s.pucch_resources.power_control.delta_f_db==1.25&& ...
    s.pucch_resources.power_control.closed_loop_adjustment_db==-2);
reverse=write(work,'canonical_child',leaf,setValue(struct(),left(1),-82));
s=read(reverse); equal(s,left(1),right(1),-82);
first=write(work,'first_parent',strings(0,1),setValue(struct(),left(3),18));
second=write(work,'second_parent',strings(0,1),setValue(struct(),right(3),21));
s=read(write(work,'siblings',[base first second],struct())); equal(s,left(3),right(3),21);
s=read(write(work,'siblings_reversed',[base second first],struct())); equal(s,left(3),right(3),18);
end

function conflicts(base,original,work)
[left,right]=paths(); one={-86,2,18,1}; two={-84,3,21,.8};
for k=1:numel(left)
    authored=setValue(setValue(struct(),left(k),one{k}),right(k),two{k});
    file=write(work,"conflict_"+k,base,authored);
    reject(@()read(file),'sixgr:lls6g:config:ConflictingPUCCHPowerAliases');
    raw=sixgr.util.mergeStruct(original,authored);
    reject(@()sixgr.lls6g.buildInternalConfig(raw,tempname), ...
        'sixgr:lls6g:config:ConflictingPUCCHPowerAliases');
end
for value={NaN,Inf,[],true,'23',"23",[1 2],1+1i}
    authored=setValue(struct(),left(3),value{1});
    reject(@()sixgr.lls6g.config.PUCCHPowerAuthority.merge(struct(),authored), ...
        'sixgr:lls6g:config:InvalidPUCCHPowerValue');
end
for value={-.1,1.1}
    authored=setValue(struct(),left(4),value{1});
    reject(@()sixgr.lls6g.config.PUCCHPowerAuthority.merge(struct(),authored), ...
        'sixgr:lls6g:config:InvalidPUCCHPowerValue');
end
end

function overrides(original)
[left,right]=paths();
authored=setValue(struct(),left(2),2.5);
s=sixgr.lls6g.config.normalizeScenarioAliases( ...
    sixgr.util.mergeStruct(original,authored),'Authority',authored);
equal(s,left(2),right(2),2.5);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
authored=setValue(struct(),right(3),19);
s=sixgr.lls6g.config.normalizeScenarioAliases( ...
    sixgr.util.mergeStruct(s,authored),'Authority',authored);
equal(s,left(3),right(3),19);
s.canonical_control.runtime_overrides=struct( ...
    'path',{char(right(1)),char(right(1))},'value',{-85,-87});
s=sixgr.lls6g.config.normalizeScenarioAliases(s);
equal(s,left(1),right(1),-87);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
s.canonical_control.runtime_overrides=struct( ...
    'path',{char(left(1)),char(right(1))},'value',{-81,-82});
reject(@()sixgr.lls6g.config.normalizeScenarioAliases(s), ...
    'sixgr:lls6g:config:ConflictingPUCCHPowerAliases');
end

function nativePower(original)
[left,~]=paths();
declared=setValue(struct(),left(1),-90);
declared=setValue(declared,left(2),2);
declared=setValue(declared,left(3),23);
declared.pucch_resources.power_control.delta_f_db=1.25;
declared.pucch_resources.power_control.closed_loop_adjustment_db=-1;
s=resolve(original,declared);
input=s; before=rng;
[first,power1]=transmit(s);
assert(isequaln(s,input)&&isequal(before,rng),'Config/typed/native TX must not mutate inputs or global RNG.');
assert(power1.P0dBm==-90&&power1.DeltaTFdB==2&&power1.DeltaFdB==1.25&& ...
    power1.ClosedLoopAdjustmentdB==-1&&power1.PCMAXdBm==23);
expected=-90+80+10*log10(2^power1.Mu*power1.MRB)+1.25+2-1;
assert(abs(first.Power.RequestedPowerdBm-expected)<1e-12&&~first.Power.Clipped);
% Changing only the previously ignored canonical P0 changes native samples.
s=resolve(s,setValue(struct(),left(1),-86));
[second,power2]=transmit(s);
assert(power2.P0dBm==-86&&~second.Power.Clipped&& ...
    abs(second.Power.AppliedPowerdBm-first.Power.AppliedPowerdBm-4)<1e-12);
assert(max(abs(second.Waveform-first.Waveform*10^(4/20)),[],'all')<1e-10);
% PCMAX is the declared cap, not an isolated post-RF/hardware measurement.
s=resolve(s,setValue(struct(),left(3),-10));
[capped,~]=transmit(s);
assert(capped.Power.Clipped&&capped.Power.AppliedPowerdBm==-10&& ...
    abs(capped.Power.MeasuredWaveformPowerdBm+10)<1e-9);
for tx={first,second,capped}
    t=tx{1};
    assert(abs(t.Power.PowerError_dB)<1e-9&& ...
        string(t.Power.MeasurementReferenceDomain)=="specified_active_ofdm_symbols_excluding_cp");
end
end

function alphaScope(original)
[left,right]=paths();
bad=resolve(original,setValue(struct(),left(4),.8));
equal(bad,left(4),right(4),.8);
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:lls6g:config:UnsupportedPUCCHAlpha');
% An inherited nonunit alpha may be overridden before final installation.
good=resolve(bad,setValue(struct(),right(4),1));
cfg=sixgr.lls6g.buildInternalConfig(good,tempname);
p=cfg.validation.pucch_resources.power_control;
assert(p.alpha==1&&p.physical_power_terms_applied&&~p.received_tpc_state_applied&& ...
    string(p.tpc_command_source)=="configured_static_pucch_adjustment"&& ...
    string(p.configured_tpc_command_source)==string(good.pucch_resources.power_control.tpc_command_source));
assert(isequaln(p,cfg.lls6g.pucch_resources.power_control)&& ...
    isequaln(cfg.lls6g.resolvedConfig.pucch_resources.power_control,good.pucch_resources.power_control));
% Normalized baseline does not apply absolute terms; no silent alpha rewrite.
normal=read(fullfile(pwd,'simulator','configs','scenarios', ...
    'lls_causal_tdd_connected_feedback_fixture.yaml'));
normal=resolve(normal,setValue(struct(),left(4),.8));
cfg=sixgr.lls6g.buildInternalConfig(normal,tempname);
assert(sixgr.rf.isNormalizedFixedSNRPowerReference(cfg)&& ...
    cfg.validation.pucch_resources.power_control.alpha==.8&& ...
    ~cfg.validation.pucch_resources.power_control.physical_power_terms_applied);
end

function roundTrip(original,work)
[left,right]=paths();
s=resolve(original,setValue(struct(),right(1),-83));
expected=sixgr.lls6g.buildInternalConfig(s,tempname);
for extension=["json","yaml"]
    file=fullfile(work,"resolved_power."+extension);
    if extension=="json", sixgr.util.jsonWrite(file,s);
    else, sixgr.lls6g.config.writeYAML(file,s); end
    bytes=fileread(file); restored=read(file);
    for k=1:numel(left), equal(restored,left(k),right(k),sixgr.util.structGet(s,left(k),[])); end
    actual=sixgr.lls6g.buildInternalConfig(restored,tempname);
    assert(isequaln(actual.validation.pucch_resources.power_control, ...
        expected.validation.pucch_resources.power_control)&&strcmp(bytes,fileread(file)));
end
end

function [tx,power]=transmit(s)
% Declared scalar reference for this transmitter-only component experiment.
% No measurement installation, received pilots, RF or gNB decoder is claimed.
s.pucch_resources.power_control.require_measured_reference_rs=false;
s.pucch_resources.power_control.pathloss_db=80;
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
identity=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',cfg.phy.pusch.RNTI,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'csi');
frame=struct('K1',1,'K1Source','configured_periodic_CSI_report_occasion','PDSCHEndSlot',4, ...
    'TargetSlot',5,'DecodedPRI',pri.PRIValue,'PRIFieldWidth',3, ...
    'PRIProvenance',pri.Source,'FirstCCE',0,'NumCCE',8, ...
    'SlotSymbolOwnership',"UUUUUUUUUUUUUU",'FlexibleResolutionProvided',false, ...
    'TriggeringEventID',"declared_power_yaml_component");
sr=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(sr,frame.TargetSlot-1);
planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI(cfg,ue,int8([1;0;1;0]),int8([]),frame);
bound=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned);
power=bound.Assignment.PowerControlState.Data;
assert(string(power.TPCCommandSource)=="configured_static_pucch_adjustment"&& ...
    ~power.RuntimeMeasuredPathlossUsed&&power.PathlossdB==80);
carrier=sixgr.phy.grid.makeCarrier(cfg);
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,bound.Assignment,bound.Report);
end
function s=resolve(s,authored)
s=sixgr.lls6g.config.normalizeScenarioAliases(sixgr.util.mergeStruct(s,authored),'Authority',authored);
end
function [left,right]=paths()
suffix=["p0_dbm","delta_tf_db","pcmax_dbm","alpha"];
left="rf_frontend.ul_power_control.pucch."+suffix;
right="pucch_resources.power_control."+suffix;
end
function equal(s,left,right,value)
assert(isequal(sixgr.util.structGet(s,left,[]),value)&&isequal(sixgr.util.structGet(s,right,[]),value), ...
    'PUCCH aliases %s / %s must preserve the last authored value.',left,right);
end
function s=read(path)
loaded=sixgr.lls6g.config.loadScenarioConfig(path); s=loaded.toStruct();
end
function path=write(work,name,parents,s)
path=string(fullfile(work,name+".json"));
if ~isempty(parents), s.inherits=string(parents); end
sixgr.util.jsonWrite(path,s);
end
function s=setValue(s,path,value), s=sixgr.util.structSet(s,path,value); end
function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingPUCCHPowerAuthorityGuard','Expected %s.',id);
end
