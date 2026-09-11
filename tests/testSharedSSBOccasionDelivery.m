function ok=testSharedSSBOccasionDelivery()
% Actual shared TDD radio samples; connected/SIB1 state is a codec fixture.
% This checks periodic measurement delivery, not initial-access completion.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
root=tempname; cfg=sixgr.lls6g.buildInternalConfig(s,root);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),6);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1;
state.CellAcquisitionState(1)="acquired"; % Declared connected component fixture.
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',0);
c=struct('Config',dl,'Slot',1,'ServingCell',1,'TrackingOnly',true);
owner.queueDownlink("PBCH",1,prototype.PreparedBroadcast,c);
assert(nnz(string({owner.Pending.Kind})=="SSBOccasion")==numel(cfg.phy.ssb.activeCandidateIndices0Based));
[~,before]=sixgr.truth.bindSharedSSBPowerReference(dl,state,1,1,0);
assert(~before.ReferenceUsable);
for slot=1:6
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state=sixgr.truth.SSBOccasionResultDelivery.deliver(state);
    if slot==2
        [~,early]=sixgr.truth.bindSharedSSBPowerReference(dl,state,1,slot,0);
        assert(early.ReferenceUsable && early.AvailableSlot==2 && early.ProducerSlot==1, ...
            'The first complete received SSB must supply slot-2 power control without waiting for slot 6.');
        assert(~isfield(state,'TestFullBroadcastComplete'),'Early measurement must precede full broadcast completion.');
    end
    [state,~]=owner.advanceSlot(state,cfg,@received);
    if slot==1
        assert(~isempty(state.PendingSSBOccasionMeasurements));
        censored=sixgr.truth.SSBOccasionResultDelivery.censorAtSweepBoundary(state);
        assert(isempty(censored.PendingSSBOccasionMeasurements) && ...
            isequaln(censored.CensoredSSBOccasionMeasurements{end}.Measurements,state.PendingSSBOccasionMeasurements));
    end
end
T=state.DeliveredSSBOccasionMeasurements;
assert(height(T)==numel(cfg.phy.ssb.activeCandidateIndices0Based) && ...
    all(T.CRCPass) && all(T.MeasurementValid) && all(T.AvailableSlot<6) && all(~T.SIB1ReceptionAttempted));
assert(all(isfinite(T.SS_RSRP_dBm)) && all(isfinite(T.SS_SINR_dB)));
ledger=state.ReferenceSignalMeasurementTable;
assert(height(ledger)==height(T) && numel(unique(string(ledger.MeasurementId)))==height(T));
assert(all(ledger.UERSRPFilterUpdateCount==1),'Full-burst completion must not update an occasion filter twice.');
assert(all(isfinite(ledger.ObservationEndSampleExclusive)) && ...
    all(strlength(ledger.SSBWindowPowerMeasurementJSON)>0));
file=fullfile(root,'ssb_occasion_measurements.csv');
sixgr.util.csvWriteTable(file,ledger,'PreserveSchema',true);
persisted=sixgr.util.csvReadTable(file,'TextType','string');
for field=["RSRP_dBm","SINR_dB","ObservationEndSampleExclusive","SSBOccasionBCHCRCPass"]
    assert(all(abs(double(persisted.(field))-double(ledger.(field)))<1e-10), ...
        'Actual SSB measurements must survive CSV export.');
end
assert(isequal(string(persisted.SSBWindowPowerMeasurementJSON),ledger.SSBWindowPowerMeasurementJSON));
trial=table(ones(height(T),1),T.ReferenceSignalId,'VariableNames',{'Slot','SSBIndex'});
sixgr.truth.SSBOccasionResultDelivery.assertDelivered(state,1,trial);
try
    sixgr.truth.SSBOccasionResultDelivery.assertDelivered(state,1,[trial;trial(1,:)]);
    error('test:ExpectedDuplicateRejection','Duplicate full-burst identity was accepted.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:truth:DuplicateSSBOccasion'));
end
again=sixgr.truth.SSBOccasionResultDelivery.deliver(state);
assert(isequaln(again.ReferenceSignalMeasurementTable,ledger));
assert(state.TestFullBroadcastComplete);
% Prove actual emitted input, not a private component counter: every TX-RF
% interval must receive exactly the single prepared broadcast (or idle).
x=prototype.PreparedBroadcast.TransmitSamples;
for k=1:numel(owner.Events.ExecutionTrace)
    e=owner.Events.ExecutionTrace{k};
    expected=complex(zeros(e.EndSampleExclusive-e.StartSample,size(x,2),'like',x));
    last=min(e.EndSampleExclusive,size(x,1));
    if last>e.StartSample, expected(1:last-e.StartSample,:)=x(e.StartSample+1:last,:); end
    tx=e.Execution.TX(string({e.Execution.TX.ID})=="gnb_1");
    assert(isscalar(tx) && string(tx.Replay.RFInputWaveformSHA256)==sixgr.rf.waveformSHA256(expected), ...
        'Per-occasion subscriptions must not duplicate or alter actual gNB input samples.');
end
ok=true; fprintf('SHARED_SSB_OCCASION_DELIVERY_PASS: %d actual SSBs, earliest available slot %d, no duplicate TX/filter, root=%s\n',height(T),min(T.AvailableSlot),root);
end

function state=received(state,items)
for item=items
    if item.Kind=="SSBOccasion"
        unacquired=state; unacquired.CellAcquisitionState(1)="searching";
        rejected=false;
        try
            sixgr.truth.SSBOccasionResultDelivery.complete(unacquired,item);
        catch cause
            assert(strcmp(cause.identifier,'sixgr:truth:ServingSSBTrackingBeforeAcquisition'),cause.message);
            rejected=true;
        end
        assert(rejected);
        if item.Context.SSBOccasionHorizon.SSBIndex==0
            otherCell=item;
            otherCell.Context.Prepared.ReceiverConfig.phy.carrier.NCellID= ...
                mod(item.Context.Prepared.ReceiverConfig.phy.carrier.NCellID+1,1008);
            wrong=sixgr.truth.SSBOccasionResultDelivery.complete(state,otherCell);
            last=wrong.PendingSSBOccasionMeasurements(end,:);
            assert(last.CRCPass && ~last.MeasurementValid && last.MeasuredNCellID~=last.ExpectedNCellID, ...
                'A decoded BCH for another cell must remain CRC-successful but unusable for serving-cell power.');
        end
        state=sixgr.truth.SSBOccasionResultDelivery.complete(state,item);
    elseif item.Kind=="PBCH"
        state.TestFullBroadcastComplete=true;
    else
        error('test:UnexpectedObservation','Unexpected observation %s.',item.Kind);
    end
end
end
