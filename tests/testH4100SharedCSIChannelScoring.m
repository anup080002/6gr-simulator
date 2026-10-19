function ok=testH4100SharedCSIChannelScoring()
% One actual full-band H4 CSI occasion. No access/data/UCI/statistical claim.
setup6GRSimToolkit('Verbose',false);
scenario='simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml';
source=sixgr.lls6g.config.loadScenarioConfig(scenario);
prior=rng; restore=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(double(source.get('simulation.random_seed')),'twister');
root=fullfile(pwd,'results','lls','h4_shared_csi_channel_scoring', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(source,root); cfg.run.rootRunFolder=root;
scope=struct('Scope',"one_full_band_shared_CSI_RS_scoring_component", ...
    'ScenarioAccepted',false,'AccessExecuted',false,'PhysicalUCIExecuted',false, ...
    'SourceScenario',scenario,'SameExecutionReference',true);
sixgr.util.matSave(fullfile(root,'configuration.mat'),struct('cfg',cfg,'scope',scope),'UseArtifactStore',false);
fprintf('H4_CSI_CHANNEL_SCORING_ROOT=%s\n',root);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,fullfile(root,'air_interface'),multi,struct(),6);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,"DL",1,1,1,200,40);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
assert(owner.SampleRateHz==122.88e6 && cfg.phy.nTxAnt==64 && cfg.phy.nRxAnt==4);
for slot=1:6
    state.CurrentSlot=slot;
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    if slot==6
        [dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(current,state,1,'DL');
        [state,queued,~,prepared]=sixgr.truth.queueSharedPeriodicCSIRS(state,dl,1,slot,1,1,1,40);
        assert(queued && prepared.Carrier.NSizeGrid==273 && ...
            prepared.Tx.CSIRSRuntimeEvent.NumResources==8 && prepared.NumPhysicalTransmitAntennas==64);
    end
    [state,~]=owner.advanceSlot(state,current,@complete);
    fprintf('H4_CSI_CHANNEL_SCORING_SLOT=%d/6 measured=%d\n',slot,height(state.ControlTrials.CSIRS));
end
trial=state.ControlTrials.CSIRS;
assert(height(trial)==1 && trial.Slot==6 && trial.NMSEScoringAvailable && ...
    trial.ChannelNMSEAllResourcesMeasured && trial.ChannelNMSEMeasuredResourceCount==8 && ...
    trial.HestRxPorts==4 && trial.HestTxPorts==4 && ...
    ~trial.ChannelNMSEReferenceUsedByReceiver && ~trial.ChannelNMSEGainOrPhaseFitted);
rows=sixgr.util.csvReadTable(fullfile(root,trial.ChannelEstimateResourcesCSV),'TextType','string');
expected=sum(arrayfun(@(r)numel(r.Indices),prepared.Tx.CSIRSInfo.Resources))*4;
assert(height(rows)==expected && height(rows)==trial.ChannelNMSEComparedComplexValues && ...
    strlength(trial.CSIChannelEstimateObservationID)>0 && ...
    all(rows.CSIChannelEstimateObservationID==trial.CSIChannelEstimateObservationID) && ...
    numel(unique(rows.ResourceID))==8 && numel(unique(rows.ReferencePortIndex0))==4 && ...
    numel(unique(rows.RxBranchIndex0))==4 && all(isfinite(rows.ReferenceHReal)) && ...
    all(isfinite(rows.HReal)) && ...
    abs(10*log10(sum(rows.ChannelErrorEnergy)/sum(rows.ReferenceChannelEnergy))-trial.NMSE_dB)<1e-10);
sixgr.util.csvWriteTable(fullfile(root,'air_interface','csv','csi_rs_trials.csv'),trial, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
sixgr.util.jsonWrite(fullfile(root,'scope.json'),scope);
fprintf('H4_SHARED_CSI_CHANNEL_SCORING_PASS resources=8 ports=4 rx=4 paired_values=%d NMSE=%g pilot_residual=%g CQI=%g RI=%g\n', ...
    height(rows),trial.NMSE_dB,trial.PilotResidualNMSE_dB,trial.CQI,trial.RI);
ok=true;
end
function state=complete(state,items)
for item=reshape(items,1,[])
    assert(item.Kind=="CSIRS");
    before=state.SharedWaveformStream.Events.NextSampleIndex;
    [state,~,reception,csi]=sixgr.truth.completeSharedCSIRSReception(state,item);
    [recomputed,~]=sixgr.phy.refsig.computeCSIRSFeedback( ...
        item.Context.Prepared.Carrier,item.Context.Prepared.ReceiverConfig,reception);
    assert(isequaln(csi,recomputed) && state.SharedWaveformStream.Events.NextSampleIndex==before, ...
        'Independent scoring must not change the practical CSI decision or advance the physical stream.');
end
end
