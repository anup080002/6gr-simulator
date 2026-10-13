function ok=testH4100SharedCSIIM()
% One H4 CSI-RS receive occasion on the actual 64x4 CDL-C/RF shared clock.
% No access, PUCCH delivery, data CRC or complete-scenario acceptance claim.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
folder=fullfile(pwd,'results','lls','h4_shared_csiim', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(source,folder); cfg.run.rootRunFolder=folder;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),40);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,200,40);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
scope=struct('Scope',"one_shared_H4_CSI_IM_receiver_occasion", ...
    'AccessExecuted',false,'ScenarioAccepted',false,'StatisticallyQualified',false);
save(fullfile(folder,'configuration.mat'),'cfg','scope');
% There is no fabricated attach/CSI/SRS state. CSI-RS is a cell-common
% producer and the receiver uses only the installed resource configuration.
for slot=1:6
    state=sixgr.truth.CoupledTruthRuntime.beginSlot(state,cfg,cfg,1,'DL',1,1,slot,200,40);
    if slot==6
        [dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
        dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
        [state,queued]=sixgr.truth.queueSharedPeriodicCSIRS(state,dl,1,slot,1,1,1,40);
        assert(queued);
    end
    [state,~]=owner.advanceSlot(state,cfg,@complete);
    fprintf('H4_SHARED_CSIIM_SLOT=%d/6\n',slot);
end
rows=state.ControlTrials.CSIRS;
assert(height(rows)==1 && rows.Slot==6 && rows.CSIMeasurementAvailable);
sixgr.util.csvWriteTable(fullfile(folder,'csirs_trials.csv'),rows,'PreserveSchema',true);
fprintf('H4_SHARED_CSIIM_PASS folder=%s\n',folder);
ok=true;
end

function state=complete(state,items)
for item=reshape(items,1,[])
    assert(string(item.Kind)=="CSIRS");
    [state,row,rx,csi]=sixgr.truth.completeSharedCSIRSReception(state,item);
    im=rx.CSIRSChannelEstimation.InterferenceMeasurement;
    assert(im.Available && im.SampleCount==1092 && im.IncludesNoise && ...
        rx.CSIMeasurementState.NoiseVariance==im.MeanPower && ...
        rx.CSIRSNoiseVar==im.MeanPower);
    assert(rx.CSIRSChannelEstimation.NumMeasuredResources==8 && ...
        size(rx.CSIRSChannelEstimate,3)==4 && size(rx.CSIRSChannelEstimate,4)==4);
    measurement=jsondecode(rx.CSIRSObservation.ReferenceSINRMeasurementJSON);
    assert(measurement.InterferenceMeasurement.Available && ...
        string(measurement.DisturbanceSource)=="configured_CSI_IM_received_RE_second_moment");
    contextFolder=char(item.Context.Config.run.rootRunFolder);
    scope="actual_shared_CDL_C_and_RX_RF_not_grid_fixture_or_injected_variance";
    save(fullfile(contextFolder,'received_measurement.mat'),'im','row','csi','measurement','scope');
    fprintf('H4_SHARED_CSIIM_RECEIVED noise=%g SINR=%g RI=%g CQI=%g\n', ...
        im.MeanPower,measurement.CSI_SINR_dB,csi.RI,csi.CQI);
end
end
