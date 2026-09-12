function ok=testResolveWaveformGrantClock()
% Explicit zero-based control scheduling vs one-based execution/HARQ aliases.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_received_ul_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
for slot1=[1 3 6 21]
    c=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot1);
    carrier=sixgr.phy.grid.makeCarrier(c);
    frame1=floor((slot1-1)/carrier.SlotsPerFrame)+1;
    g=sixgr.link.resolveWaveformGrant(c,'DL',frame1,'Slot',slot1, ...
        'SFN',carrier.NFrame,'ControlAbsoluteSlot',slot1-1);
    assert(g.Valid && g.ExactPHYFeasible && g.ControlAbsoluteSlot==slot1-1 && ...
        g.ScheduledAbsoluteSlot==slot1-1 && g.Frame==frame1 && g.Slot==slot1);
    sixgr.phy.grant.assertGrantTimingIdentity(g,'DL');
    bound=sixgr.link.bindExecutedHARQClock(g,carrier,slot1);
    assert(bound.ScheduledAbsoluteSlot==slot1-1);
end
fprintf('RESOLVE_WAVEFORM_GRANT_CLOCK_PASS slots=1,3,6,21 explicit control0/execution1\n');
ok=true;
end
