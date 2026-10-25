function ok=testRSPeriodAliasAuthority()
% Actual YAML -> native pilot calendars. No received-waveform qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> unique test fixture only
base=string(fullfile(pwd,'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
s=read(base);
assert(s.reference_signals.csi_rs_periodicity_slots==10&& ...
    s.reference_signals.nzp_csi_rs.periodicity_slots==10&& ...
    s.reference_signals.trs_periodicity_slots==20);
% Parent numeric alias, child nested alias, unrelated leaf: no revival.
parent=write(work,'parent',base,set(struct(),'reference_signals.csi_rs_periodicity_slots',20));
child=write(work,'child',parent,set(struct(),'reference_signals.nzp_csi_rs.periodicity','5ms'));
leaf=write(work,'leaf',child,struct('meta',struct('description','Period authority test')));
s=read(leaf); assert(s.reference_signals.csi_rs_periodicity_slots==10);
assert(s.reference_signals.nzp_csi_rs.periodicity_slots==10);
% Order of multiple parents is explicit, not inferred from merged values.
a=write(work,'a',strings(0,1),set(struct(),'reference_signals.trs_periodicity_slots',40));
b=write(work,'b',strings(0,1),set(struct(),'reference_signals.trs.periodicity_ms',10));
s=read(write(work,'ab',[base a b],struct())); assert(s.reference_signals.trs_periodicity_slots==20);
s=read(write(work,'ba',[base b a],struct())); assert(s.reference_signals.trs_periodicity_slots==40);
% Same-layer conflicts and fractional conversions must not silently win.
bad=set(set(struct(),'reference_signals.trs_periodicity_slots',40), ...
    'reference_signals.trs_periodicity_ms',10);
reject(@()read(write(work,'conflict',base,bad)),'sixgr:lls6g:config:ConflictingRSPeriodAliases');
bad=set(struct(),'reference_signals.nzp_csi_rs.periodicity','0.6ms');
reject(@()read(write(work,'fractional',base,bad)),'sixgr:lls6g:config:NonIntegralCarrierPeriod');
for value={[],NaN,Inf,true,'20',1+1i}
    bad=set(struct(),'reference_signals.trs_periodicity_slots',value{1});
    reject(@()sixgr.lls6g.config.RSPeriodAuthority.merge(struct(),bad), ...
        'sixgr:lls6g:config:InvalidCarrierPeriod');
end
% Portable resolved configuration: no source-path provenance dependency.
s=read(base); file=write(work,'resolved',strings(0,1),s); reread=read(file);
assert(reread.reference_signals.csi_rs_periodicity_slots==10&& ...
    reread.reference_signals.trs_periodicity_slots==20);
assert(string(reread.config_inheritance.provenance.config_path)==file&& ...
    ~isequaln(reread.config_inheritance.provenance,s.config_inheritance.provenance), ...
    'A real file reload records its new source, not the old serialized file provenance.');
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
authored=set(struct(),'reference_signals.trs.periodicity_ms',20);
resolved=sixgr.lls6g.config.normalizeScenarioAliases( ...
    sixgr.util.mergeStruct(s,authored),'Authority',authored);
assert(resolved.reference_signals.trs_periodicity_slots==40&& ...
    resolved.reference_signals.trs.periodicity=="20ms");
explicitMs=read(write(work,'trs_ms_token',base, ...
    set(struct(),'reference_signals.trs.periodicity','20ms')));
assert(explicitMs.reference_signals.trs_periodicity_slots==40);
resolved.canonical_control.runtime_overrides=struct( ...
    'path','reference_signals.trs.periodicity_slots','value',20);
resolved=sixgr.lls6g.config.normalizeScenarioAliases(resolved);
assert(resolved.reference_signals.trs_periodicity_ms==10);
% A direct merged struct has no last-author knowledge: conflict is an error.
bad=s; bad.reference_signals.nzp_csi_rs.periodicity_slots=20;
reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:lls6g:config:ConflictingRSPeriodAliases');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.csirs.period_slots==10&&cfg.phy.trs.period_slots==20);
carrier=nrCarrierConfig('NSizeGrid',cfg.phy.carrier.NSizeGrid, ...
    'SubcarrierSpacing',30,'NCellID',cfg.phy.carrier.NCellID);
for slot0=[5 6 15]
    carrier.NSlot=slot0;
    [indices,~,~,native]=sixgr.phy.refsig.csirs(carrier,cfg);
    assert(isequal(double(native.CSIRSPeriod),[10 5]));
    assert(~isempty(indices)==ismember(slot0,[5 15]));
end
trs=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
assert(trs.PeriodicityValidation.PeriodSlots==20&& ...
    trs.PeriodicityValidation.PeriodMilliseconds==10);
fprintf('RS_PERIOD_ALIAS_AUTHORITY_PASS inherited_units conflict_guards native_calendars\n');
ok=true;
end
function out=set(s,path,value), out=sixgr.util.structSet(s,path,value); end
function s=read(file)
loaded=sixgr.lls6g.config.loadScenarioConfig(file); s=loaded.toStruct();
end
function file=write(work,name,parents,s)
file=string(fullfile(work,name+".json"));
if ~isempty(parents), s.inherits=parents; end
sixgr.util.jsonWrite(file,s);
end
function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRSPeriodGuard','Expected %s.',id);
end
