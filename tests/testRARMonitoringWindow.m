function ok=testRARMonitoringWindow()
% Independent symbol/period boundary assertions; no channel execution.
cfg=raStrictAnchorConfig();
cfg=withCanonicalSchedulerTiming(cfg);
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
carrier=sixgr.phy.grid.makeCarrier(cfg);
[~,c]=sixgr.phy.ra.resolveRARCommonControl(cfg,carrier);
c.SlotPeriodAndOffset=[4 1]; c.MonitoringDurationSlots=2;
c.StartSymbol=3;
spec=frame.Numerology;
prior=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(5,2,spec);
w=sixgr.phy.ia.RARMonitoringWindow.resolve(frame,c,prior.Ticks,3);
assert(w.StartSlot==5 && w.StartSymbol==3 && isequal(w.MonitoringSlots,[5;6]));
start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(5,3,spec);
expiry=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(8,3,spec);
assert(w.StartTicks==start.Ticks && w.ExpiryTicksExclusive==expiry.Ticks);
assert(w.LastSlot==8,'A nonzero start symbol leaves a partial final slot inside the window.');
% One Tc late disqualifies this occasion; do not round PRACH down to a
% symbol or move the common CORESET to make the configured RAR fit.
late=sixgr.phy.ia.RARMonitoringWindow.resolve(frame,c,prior.Ticks+1,3);
assert(late.StartSlot==6 && isequal(late.MonitoringSlots,6));
assert(~w.ReceiverExecutionQualified && ~w.ProxyUsed && ~w.FallbackUsed);
% A received DL phase shifts physical timestamps, not the radio-frame
% occasion coordinates. Check both signs and the exact one-Tc boundary.
for phase=int64([-1792 1792])
    shifted=sixgr.phy.ia.RARMonitoringWindow.resolve(frame,c,prior.Ticks+phase,3,phase);
    assert(isequal(shifted.MonitoringSlots,w.MonitoringSlots) && ...
        shifted.StartSlot==w.StartSlot && shifted.StartSymbol==w.StartSymbol && ...
        shifted.LastSlot==w.LastSlot && shifted.ClockOffsetTicks==phase);
    for field=["PRACHActiveEndTicksExclusive","StartTicks","ExpiryTicksExclusive","MonitoringStartTicks"]
        assert(isequal(shifted.(field),w.(field)+phase));
    end
    shiftedLate=sixgr.phy.ia.RARMonitoringWindow.resolve(frame,c,prior.Ticks+phase+1,3,phase);
    assert(isequal(shiftedLate.MonitoringSlots,late.MonitoringSlots) && ...
        shiftedLate.StartTicks==late.StartTicks+phase);
end

for suffix=["_tdd", ""]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
        'lls_causal_access_to_data_wiring'+suffix+'.yaml'));
    cfg=sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(s,tempname));
    baseline=sixgr.mac.ra.RAConfig(cfg);
    % A sparse Type1 period changes the actual Msg2/Msg3 schedule together.
    cfg.initial_access.sib1.pdcch_config_common.commonSearchSpaceList.monitoringSlotPeriodicityAndOffset= ...
        struct('periodicity','sl2','offset',0);
    r=sixgr.mac.ra.RAConfig(cfg,'RuntimeSlot',11);
    assert(mod(r.Msg2Slot,2)==0 && ismember(r.Msg2Slot,r.RARMonitoringWindow.MonitoringSlots));
    assert(r.RARMonitoringWindow.StartTicks>r.PRACHActiveEndTicksExclusive);
    assert(r.PRACHActiveEndTicksExclusive>baseline.PRACHActiveEndTicksExclusive);
    assert(r.Msg3Slot==r.Msg2Slot+r.TimingSchedule.Msg3K2Slots+r.TimingSchedule.Msg3AdditionalDelaySlots);
    f=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
    cc=sixgr.phy.grid.makeCarrier(cfg);
    [~,control]=sixgr.phy.ra.resolveRARCommonControl(cfg,cc);
    if suffix=="_tdd"
        % Slot 4 in each five-slot period is fixed UL: no Type1 DL occasion.
        control.SlotPeriodAndOffset=[5 4];
        localThrows(@()sixgr.phy.ia.RARMonitoringWindow.resolve( ...
            f,control,r.PRACHActiveEndTicksExclusive,8),'sixgr:phy:ia:NoRARMonitoringOccasion');
    end
end
ok=true;
disp('RAR_MONITORING_WINDOW_PASS: exact one-symbol gap, period/duration/offset, partial expiry and TDD/FDD runtime binding.');
end

function localThrows(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testRARMonitoringWindow:MissingRejection','Expected %s.',id);
end
