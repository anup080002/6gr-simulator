function ok=testFailedSSBOccasionDelivery()
% Actual 4-TX/2-RX shared samples, including undetected monitored candidates.
% Connected state is an explicit fixture; this is NOT an access acceptance run.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
root=tempname(fullfile(pwd,'logs')); mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),6);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1; state.CellAcquisitionState(1)="acquired";
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
    'UseRuntimeChannel',true,'RuntimeSlot',0);
power=prototype.PreparedBroadcast.Tx.SSBPowerReferenceContract;
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture( ...
    cfg,power.SSPBCHBlockPower_dBm,1,1)};
c=struct('Config',dl,'Slot',1,'ServingCell',1,'TrackingOnly',true,'Prototype',prototype);
owner.queueDownlink('PBCH',1,prototype.PreparedBroadcast,c);
for slot=1:6
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state=sixgr.truth.SSBOccasionResultDelivery.deliver(state);
    [state,~]=owner.advanceSlot(state,cfg,@received);
end
trial=state.TestFullBurstTrial;
ledger=state.DeliveredSSBOccasionMeasurements;
before=trial;
sixgr.truth.SSBOccasionResultDelivery.assertDelivered(state,1,trial);
assert(isequaln(trial,before),'Matching a delivery must not replace receiver evidence.');
assert(any(~trial.CRCPass & isnan(trial.SSBIndex)) && any(trial.CRCPass), ...
    'The low-SNR physical fixture must exercise both detected and undetected candidates.');
assert(height(ledger)==height(trial) && any(~ledger.MeasurementValid));
for k=1:height(trial)
    hit=ledger.ReferenceSignalId==trial.RequestedSSBOccasionIndex(k);
    assert(nnz(hit)==1 && ledger.AvailableSlot(hit)<=state.CurrentSlot);
end
localReject(state,[trial;trial(1,:)],'sixgr:truth:DuplicateSSBOccasion');
bad=trial; bad.RequestedSSBOccasionIndex(1)=NaN;
localReject(state,bad,'sixgr:truth:InvalidSSBOccasionRequest');
bad=removevars(trial,'RequestedSSBOccasionIndex');
localReject(state,bad,'sixgr:truth:MissingSSBOccasionRequest');
missing=state; missing.DeliveredSSBOccasionMeasurements(1,:)=[];
localReject(missing,trial,'sixgr:truth:MissingSSBOccasionDelivery');
late=state; late.DeliveredSSBOccasionMeasurements.AvailableSlot(1)=state.CurrentSlot+1;
localReject(late,trial,'sixgr:truth:MissingSSBOccasionDelivery');
writetable(trial,fullfile(root,'full_burst_observations.csv'));
writetable(ledger,fullfile(root,'occasion_deliveries.csv'));
ok=true;
fprintf('FAILED_SSB_OCCASION_DELIVERY_PASS detected=%d failed=%d root=%s\n', ...
    nnz(trial.CRCPass),nnz(~trial.CRCPass),root);
end

function state=received(state,items)
for item=items
    if item.Kind=="SSBOccasion"
        state=sixgr.truth.SSBOccasionResultDelivery.complete(state,item);
    elseif item.Kind=="PBCH"
        c=item.Context;
        [~,pre,tx,~,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
        opts=struct('UseRuntimeChannel',true,'RuntimeSlot',c.Slot-1, ...
            'CandidateSSBIndices',c.Config.phy.ssb.activeCandidateIndices0Based, ...
            'SSBIndex',[],'WriteArtifacts',false,'RunFolder','','RunId','ssb_delivery_test', ...
            'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
        out=sixgr.link.completeCellSearchBroadcast(c.Prepared,post,c.Prototype,opts,tic);
        n=numel(out.CandidateResults);
        t=table(repmat(c.Slot,n,1),nan(n,1),nan(n,1),false(n,1), ...
            'VariableNames',{'Slot','RequestedSSBOccasionIndex','SSBIndex','CRCPass'});
        for k=1:n
            r=out.CandidateResults{k};
            t.RequestedSSBOccasionIndex(k)=r.RequestedSSBOccasionIndex;
            t.SSBIndex(k)=r.SSBIndex; t.CRCPass(k)=r.SIB1.BCHCrcPass;
        end
        state.TestFullBurstTrial=t;
    else
        error('test:UnexpectedObservation','Unexpected observation %s.',item.Kind);
    end
end
end

function localReject(state,trial,id)
try
    sixgr.truth.SSBOccasionResultDelivery.assertDelivered(state,1,trial);
catch cause
    assert(strcmp(cause.identifier,id),cause.message); return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
