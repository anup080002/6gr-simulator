function ok=testLinkCalibrationCampaign()
% Small physical wiring checks, not a statistically qualified dataset.
[p,cases,identity]=sixgr.calibration.loadCampaign('configs/calibration/nr_dl_ul_harq_baseline.yaml');
assert(isequal(sort(string({cases.Direction})),["DL","UL"]));
for k=1:numel(cases)
    cfg=cases(k).Config; cfg.channel.model='AWGN'; cfg.channel.delaySpreadSeconds=0;
    phy=sixgr.lls.buildPHYConfig(cfg,0);
    directionField=lower(char(cfg.simulation.link));
    assert(string(phy.phy.(directionField).mcsTable)==string(cfg.(directionField).mcsTable), ...
        'The production PHY must receive the configured MCS table identity.');
    assert(~phy.phy.ssb.enable,'Standalone data-only calibration must not reserve an untransmitted SSB.');
    if cases(k).Direction=="DL"
        carrier=sixgr.phy.grid.makeCarrier(phy); g=zeros(carrier.SlotsPerFrame,1);
        for slot=0:carrier.SlotsPerFrame-1
            carrier.NSlot=slot;
            [~,allocation]=sixgr.phy.grid.allocREsPDSCH(carrier,phy);
            g(slot+1)=allocation.G;
        end
        assert(all(g==g(1)) && g(1)>0,'Fixed allocation G changed across the radio frame.');
    end
    e=sixgr.calibration.executeEpisode(cfg,[-20 35],[0 2],1000*k+(1:5),identity);
    assert(numel(e.Attempts)==2 && e.Attempts(1).CRCError && ~e.Attempts(2).CRCError);
    assert(e.Attempts(2).HARQSoftCombiningApplied);
    assert(~e.Attempts(1).PriorAttemptsFailed && e.Attempts(2).PriorAttemptsFailed);
    assert(e.Attempts(1).TransportBlockSHA256==e.Attempts(2).TransportBlockSHA256);
    assert(all(abs(e.Attempts(1).SINRLinear-10^(-20/10))<1e-10));
    high=sixgr.calibration.executeEpisode(cfg,[35 -20],[0 2],10000*k+(1:5),identity);
    assert(numel(high.Attempts)==1 && high.Delivered);
    cfg.channel=sixgr.util.mergeStruct(cfg.channel,p.target_channel);
    fading=sixgr.calibration.executeEpisode(cfg,[10 10],[0 2],100000*k+(1:5),identity);
    assert(std(fading.Attempts(1).SINRLinear)>1e-6,'A fading feature must not be scalar full-grid substitution.');
    fprintf('LINK_CALIBRATION_PHYSICAL_PASS direction=%s attempts=%d\n',cases(k).Direction, ...
        numel(e.Attempts)+numel(high.Attempts)+numel(fading.Attempts));
end
ok=true;
end
