function ok=testRAN1AI1032F1ExecutionConfig()
% Verify dimensional, reference-power, immutable-MCS and exact-TBS binding.
study=sixgr.studies.ran1ai1032.loadStudyConfig();
study.lls.execution.rf_branch='ideal_debug'; % This test's explicit impairment-free reference.
plan=sixgr.studies.ran1ai1032.buildLLSCasePlan(study);
T=plan.CasePlan;
T=T(T.ExperimentID=="F1" & T.ChannelProfile=="AWGN" & ...
    T.AntennaCaseID=="mimo_4x4_r1_r4" & ismember(T.EntryID,["B27","H0","H3"]),:);
for i=1:height(T)
    cfg=sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,T(i,:),30,10321);
    assert(cfg.phy.carrier.NSizeGrid==273 && cfg.phy.carrier.SubcarrierSpacing==30);
    assert(cfg.phy.fc_Hz==7e9 && cfg.phy.pusch.nLayers==T.Rank(i));
    assert(sixgr.rf.isNormalizedFixedSNRPowerReference(cfg));
    assert(~cfg.phy.harq.enable && ~cfg.phy.linkAdaptation.innerLoopFlag && ...
        ~cfg.phy.linkAdaptation.outerLoopFlag && ~cfg.mac.scheduler.fastNREApprox);
    assert(~cfg.phy.pusch.enablePTRS && cfg.phy.channelEstimation.method=="LS");
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    [~,info,geometry,transport]=sixgr.phy.grid.allocPUSCHTransport(carrier,cfg);
    assert(geometry.NumLayers==T.Rank(i) && geometry.NumAntennaPorts==4 && ~isempty(transport));
    assert(geometry.DMRS.DMRSAdditionalPosition==1 && geometry.DMRS.DMRSTypeAPosition==2);
    expected=nrTBS(char(cfg.phy.pusch.modulation),T.Rank(i),273,info.NREPerPRB,cfg.phy.pusch.codeRate,0);
    assert(expected>0 && info.G>expected);
    H=cfg.channel.awgnSpatialMatrixDL.';
    assert(norm(H'*H-eye(4),'fro')<1e-10);
end
bad=T(1,:); bad.Rank=5;
localReject(@()sixgr.studies.ran1ai1032.buildF1RuntimeConfig(study,bad,30,10321), ...
    'sixgr:ran1ai1032:F1Rank');
ok=true; fprintf('RAN1_AI1032_F1_EXECUTION_CONFIG_PASS cases=%d\n',height(T));
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s',id,ME.identifier); return; end
error('test:ExpectedFailure','Expected %s',id);
end
