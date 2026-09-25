function root=diagnoseShared4Tx2RxTRS(scenario)
% Component diagnostic on the actual shared channel/noise/receiver path.
% No assertion of low-SNR success: retain measured failures for diagnosis.
setup6GRSimToolkit('Verbose',false);
if nargin<1, scenario='simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml'; end
s=sixgr.lls6g.config.loadScenarioConfig(scenario);
root=fullfile(pwd,'results','lls','shared_4tx2rx_trs_diagnostic', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
last=double(cfg.phy.trs.slotNumbers(end))+1;
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),last);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
p=sixgr.link.prepareTRSTransmission(dl,-10,'RuntimeSlot',double(cfg.phy.trs.slotNumbers(1))+1);
owner.queueDownlink("TRS",1,p,struct('Config',dl,'Slot',double(cfg.phy.trs.slotNumbers(1))+1));
seen=false;
for slot=1:last
    state.CurrentSlot=slot;
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    [state,items]=owner.advanceSlot(state,current);
    for item=items
        if item.Kind~="TRS", continue; end
        assert(~seen); seen=true;
        p=item.Context.Prepared;
        [~,~,~,replay,observation]=sixgr.truth.sharedObservationEvidence(item.Planes);
        replay.PowerContext=p.PowerContext;
        [~,~,captures]=sixgr.truth.sharedLinkScoringObservation( ...
            item.Planes,p,item.Context.DesiredReferencePlane);
        ch=owner.directionalChannelState(1,"DL");
        before=owner.Events.NextSampleIndex;
        out=sixgr.link.completeTRSReception(p,observation,replay,ch,'ScoringChannelReferences',captures);
        assert(owner.Events.NextSampleIndex==before && ~out.Crash,'%s',out.FailureReason);
        receivedWaveform=observation.readComplete();
        assert(size(receivedWaveform,2)==2 && out.AppliedAWGNSNR_dB==-10);
        rx=struct('Waveform',receivedWaveform,'InjectedTimingOffset_samples',0, ...
            'NoiseVariance',replay.InjectedNoiseVariance,'FaultMode',"normal");
        rx.WhiteGaussianNoiseModelEstablished= ...
            isequal(sixgr.util.structGet(replay,'ReceiverGainCompensation.GainOnlyRFExecuted',false),true) && ...
            strcmpi(string(replay.NoiseOperatingMode),'standalone_awgn_snr_argument');
        timing=sixgr.phy.trs.estimateTRSTiming(rx,p.StrictConfig,p.Tx);
        det=sixgr.phy.trs.detectTRSResources(rx,p.StrictConfig,p.Tx,'Timing',timing);
        writetable(det.Table,fullfile(root,'detection.csv'));
        save(fullfile(root,'received_trs.mat'),'p','replay','ch','captures', ...
            'out','receivedWaveform','det','timing','-v7.3');
        fprintf('SHARED_4TX2RX_TRS: detection=%d metric=%g threshold=%g tracking=%d applied_snr=%g\n', ...
            out.DetectionSuccess,out.DetectionMetric,out.DetectionThreshold, ...
            out.TRSRuntimeEvidenceUsable,out.AppliedAWGNSNR_dB);
    end
end
assert(seen && ~owner.hasPending("TRS",1));
fprintf('TRS_DIAGNOSTIC_FOLDER=%s\n',root);
end
