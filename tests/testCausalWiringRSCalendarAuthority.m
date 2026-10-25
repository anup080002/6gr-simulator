function ok=testCausalWiringRSCalendarAuthority()
% Original self-contained FDD YAML -> native CSI-RS/SRS/TRS calendars.
% Reference-symbol production only: no received PHY/access qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
root=fileparts(fileparts(mfilename('fullpath')));
path=fullfile(root,'simulator','configs','scenarios','lls_causal_access_to_data_wiring.yaml');
original=fileread(path);
raw=sixgr.lls6g.config.readConfigFile(path);
assert(~isfield(raw,'inherits') && raw.frame.scs_khz==15);
assert(raw.reference_signals.csi_rs_periodicity_slots==4 && ...
    raw.reference_signals.csi_rs_offset_slots==3 && ...
    string(raw.reference_signals.nzp_csi_rs.periodicity)=="4ms");
assert(raw.reference_signals.srs_periodicity_slots==4 && ...
    raw.reference_signals.srs_slot_within_period==4 && ...
    raw.reference_signals.srs.period_offset==3 && ...
    raw.reference_signals.srs_periodicity_ms==4 && ...
    string(raw.reference_signals.srs.periodicity)=="4");
assert(raw.reference_signals.trs_periodicity_slots==10 && ...
    string(raw.reference_signals.trs.periodicity)=="10ms" && ...
    isequal(double(raw.reference_signals.trs.slot_numbers(:).'),[7 8]));
% Preserve fail-closed same-layer authority. These are the original stale
% declarations, not a caller-provided precedence override or guard bypass.
bad=raw; bad.reference_signals.nzp_csi_rs.periodicity="20ms";
reject(@()sixgr.lls6g.config.RSPeriodAuthority.apply(bad), ...
    'sixgr:lls6g:config:ConflictingRSPeriodAliases');
bad=raw; bad.reference_signals.trs_periodicity_slots=4;
reject(@()sixgr.lls6g.config.RSPeriodAuthority.apply(bad), ...
    'sixgr:lls6g:config:ConflictingRSPeriodAliases');
scenario=sixgr.lls6g.config.loadScenarioConfig(path);
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(cfg.phy.carrier.NSizeGrid==25 && cfg.phy.carrier.SubcarrierSpacing==15);
assert(cfg.phy.csirs.period_slots==4 && cfg.phy.csirs.offset_slots==3 && ...
    cfg.phy.srs.period_slots==4 && cfg.phy.srs.period_offset==3 && ...
    cfg.phy.trs.period_slots==10);
carrier=sixgr.phy.grid.makeCarrier(cfg);
srs=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
assert(isequal(double(srs.ToolboxSRS.SRSPeriod),[4 3]) && ...
    srs.NumRB==24 && srs.ExpectedNumRB==24);
activeCSI=false(1,20); activeSRS=false(1,20);
for slot0=0:19
    carrier.NFrame=floor(slot0/carrier.SlotsPerFrame);
    carrier.NSlot=mod(slot0,carrier.SlotsPerFrame);
    [indices,symbols,~,native]=sixgr.phy.refsig.csirs(carrier,cfg);
    assert(isequal(double(native.CSIRSPeriod),[4 3]));
    activeCSI(slot0+1)=~isempty(indices);
    assert(numel(indices)==numel(symbols));
    srsIndices=nrSRSIndices(carrier,srs.ToolboxSRS);
    srsSymbols=nrSRS(carrier,srs.ToolboxSRS);
    activeSRS(slot0+1)=~isempty(srsIndices);
    assert(numel(srsIndices)==numel(srsSymbols));
end
expected=mod(0:19,4)==3;
assert(isequal(activeCSI,expected) && isequal(activeSRS,expected), ...
    'Native CSI-RS/SRS must retain the authored absolute four-slot calendar across frames.');
for first0=[7 17]
    trs=sixgr.phy.trs.buildTRSConfigFromScenario(cfg,'RuntimeSlot',first0+1);
    assert(trs.NumRB==25 && trs.PeriodicityValidation.Valid && ...
        trs.PeriodicityValidation.PeriodMilliseconds==10 && ...
        trs.PeriodicityValidation.PeriodSlots==10 && ...
        trs.SlotAuthority=="explicit_slot_numbers" && ...
        isequal(trs.ConfiguredSlotNumbers,[7 8]) && isequal(trs.SlotNumbers,first0+[0 1]));
    emitted=sixgr.phy.trs.generateTRSSymbolsAndIndices(trs);
    assert(numel(emitted.SlotResources)==2);
    for k=1:2
        actual=emitted.SlotResources(k);
        assert(actual.Slot==first0+k-1 && ~isempty(actual.Indices) && ...
            numel(actual.Indices)==numel(actual.Symbols));
        assert(sixgr.truth.isActiveTRSOccasion(cfg,actual.Slot+1));
    end
end
for slot0=setdiff(0:19,[7 8 17 18])
    assert(~sixgr.truth.isActiveTRSOccasion(cfg,slot0+1));
end
assert(strcmp(original,fileread(path)),'Loading and native calendar checks must not rewrite source YAML.');
fprintf('CAUSAL_WIRING_RS_CALENDAR_PASS CSI_SRS_period4_offset3 TRS_period10_width25_slots7_8 native_reference_symbols_only receiver_trials=0\n');
ok=true;
end

function reject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRSPeriodGuard','Expected %s.',id);
end
