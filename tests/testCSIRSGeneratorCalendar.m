function ok=testCSIRSGeneratorCalendar()
% Config-driven TX, allocation and planning share an absolute calendar.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
period=double(cfg.phy.csirs.period_slots);
offset=double(cfg.phy.csirs.offset_slots);
for slot0=0:2*period
    localCheck(cfg,slot0,mod(slot0-offset,period)==0);
end
% Declared boundary fixture, not a replacement for the production calendar.
crossFrame=cfg;
crossFrame.phy.csirs.period_slots=20;
crossFrame.phy.csirs.offset_slots=11;
for slot0=[1 11 21 31]
    localCheck(crossFrame,slot0,any(slot0==[11 31]));
end
active=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,offset+1);
carrier=sixgr.phy.grid.makeCarrier(active);
bad=active;
bad.lls6g.runtime.AbsoluteSlotIndex0=offset+1;
localMustFail(@()sixgr.phy.refsig.csirs(carrier,bad), ...
    'sixgr:phy:csirs:CalendarClockMismatch');
bad=active; bad.phy.csirs=rmfield(bad.phy.csirs,'period_slots');
localMustFail(@()sixgr.phy.refsig.csirs(carrier,bad), ...
    'sixgr:pdsch:InvalidCSIRSOccasionConfig');
resource=nrCSIRSConfig; resource.CSIRSPeriod=[20 11]; resource.NumRB=carrier.NSizeGrid;
carrier.NFrame=0; carrier.NSlot=1;
[ind,sym]=sixgr.phy.refsig.csirs(carrier,resource);
assert(isempty(ind) && isempty(sym));
fprintf('CSIRS_GENERATOR_CALENDAR_PASS baseline_period=%d offset=%d\n',period,offset);
ok=true;
end

function localCheck(cfg,slot0,expected)
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
carrier=sixgr.phy.grid.makeCarrier(cfg);
[ind,sym,info,resource]=sixgr.phy.refsig.csirs(carrier,cfg,'IndexBase','0based');
assert(info.Enabled && info.Scheduled==expected && info.AbsoluteSlot0==slot0);
assert(isempty(ind)==~expected && isempty(sym)==~expected && ~isempty(resource));
assert(isequal(resource.CSIRSPeriod,[cfg.phy.csirs.period_slots cfg.phy.csirs.offset_slots]));
if expected
    resources={resource};
    if isfield(info,'Resources') && ~isempty(info.Resources)
        resources=arrayfun(@(r){r.Configuration},info.Resources);
    end
    expectedInd=[]; expectedSym=[];
    for k=1:numel(resources)
        ii=nrCSIRSIndices(carrier,resources{k},'IndexBase','0based');
        ss=nrCSIRS(carrier,resources{k});
        expectedInd=[expectedInd; ii(:)]; %#ok<AGROW>
        expectedSym=[expectedSym; ss(:)]; %#ok<AGROW>
    end
    assert(isequal(double(ind(:)),double(expectedInd(:))) && ...
        isequal(sym(:),expectedSym(:)));
else
    assert(info.NRE==0 && info.NoDataReason=="outside_configured_period_offset");
end
end

function localMustFail(action,identifier)
try
    action();
catch ME
    assert(strcmp(ME.identifier,identifier),'Unexpected error: %s',ME.identifier);
    return;
end
error('testCSIRSGeneratorCalendar:MissingGuard','Expected %s.',identifier);
end
