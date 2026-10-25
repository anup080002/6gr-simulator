function ok=testSRSRetainedReferencePreparation()
% Actual native SRS preparation after the configured research age limit.
% SSB/SIB1/access are declared boundary inputs: no RF/channel/receiver runs.
% Uses the real lifecycle, future planning, admission and transmitter owners.
setup6GRSimToolkit('Verbose',false);
random=rng; cleanup=onCleanup(@()rng(random)); %#ok<NASGU>
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
folder=fullfile(pwd,'results','validation','srs_retained_reference_preparation', ...
    char(java.util.UUID.randomUUID())); mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder); cfg.run.rootRunFolder=folder;
assert(sixgr.phy.refsig.pathlossReferenceLifetime(cfg)=="retained_filtered_reference");
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),0);
state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,1,0);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,5,cfg.run.totalSlots,0);
state.CurrentServingIdx(:)=1; state.CellAcquisitionState(:)="acquired";
common=struct('Source',"decoded_sib1",'TreeHash',"declared_received_common_power_boundary", ...
    'ServingCell',1,'ConfigurationEpoch',cfg.initial_access.configuration_epoch, ...
    'AvailableSlot',5,'SSPBCHBlockPower_dBm',5);
row=table(0,1,-90,cfg.initial_access.configuration_epoch, ...
    'VariableNames',{'ReferenceSignalId','ServingCell','SS_RSRP_dBm','ReferenceConfigurationEpoch'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,row,'ProducerSlot',1,'AvailableSlot',5,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','declared_received_power_boundary_not_PHY');
state=sixgr.truth.SSBPowerReferenceLifecycle.install(state,1,common);
state.UECommonCellConfigurationByUE={common};
% The original capture remains unchanged at decision41, for resource45.
% This is the stopped n40 failure's source/availability/decision geometry.
state.CurrentSlot=41; state.CurrentCanonicalSlot=41;
plan=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,45);
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,plan,1,'UL');
[admitted,decision]=sixgr.truth.resolveSharedSRSPowerAdmission(plan,bound,1,45);
reference=bound.lls6g.userContext.RuntimeSRSPowerReference;
assert(admitted && decision.DecisionSlot==41 && decision.SRSResourceSlot==45 && ...
    reference.ProducerSlot==1 && reference.AvailableSlot==5 && reference.ConsumerSlot==45 && ...
    reference.ConfiguredReference.MaximumAgeSlots==20 && isinf(reference.MaximumAgeSlots) && ...
    reference.ReferenceLifecycleStatus=="retained_filtered_reference_available");
save(fullfile(folder,'admission_before_preparation.mat'),'reference','decision');
bound.phy.srs.receivedPowerControlState=sixgr.link.ReceivedULPowerControlState(bound);
args={'SlotIndex',45,'TrialIndex',1,'TimingAdvanceSamples',0,'PrepareOnly',true};
out=sixgr.link.runSRSChannelEstimation(bound,args{:});
assert(isfield(out,'PreparedTransmission'),'test:SRSPreparationMissing','%s',out.Notes);
p=out.PreparedTransmission; power=p.Metadata.PowerEvidence;
assert(p.Channel=="SRS" && p.Tx.Carrier.NSlot==44 && ...
    p.NumPhysicalTransmitAntennas==4 && p.NumReceiveAntennas==64 && ...
    isequaln(power.Reference,reference) && power.Reference.Pathloss_dB==95 && ...
    out.ExecutionStage=="transmit_prepared_not_received");
ofdm=p.TxInfo.OFDMInfo; symbol=double(p.Tx.SRS.SymbolStart);
first=sum(ofdm.SymbolLengths(1:symbol))+ofdm.CyclicPrefixLengths(symbol+1)+1;
samples=p.Tx.Waveform(first:first+ofdm.Nfft-1,:);
measured=10*log10(mean(sum(abs(samples).^2,2)));
assert(abs(measured-power.AppliedPower_dBm)<1e-8,'test:SRSPowerMismatch', ...
    'Original useful-symbol power must match the consumed power request.');

% The finite-age policy still rejects the same original old measurement.
finite=cfg; finite.rf.frontend.ul_power_control.pathloss_reference_lifetime='configured_age_limit';
[finiteBound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(finite,plan,1,'UL');
[admitted,finiteDecision]=sixgr.truth.resolveSharedSRSPowerAdmission(plan,finiteBound,1,45);
assert(~admitted && finiteDecision.PowerReferenceStatus=="stale");
reject(@()sixgr.link.runSRSChannelEstimation(finiteBound,args{:}), ...
    'sixgr:srs:PathlossReferenceMeasurementMissing');
for defect=["resource","consumer","future_available","future_producer","lifetime","effective_age","lifecycle"]
    bad=bound;
    switch defect
        case "resource", bad.rf.frontend.ul_power_control.srs.pathloss_reference.reference_signal_id=1;
        case "consumer", bad.lls6g.userContext.RuntimeCurrentSlot=44;
        case "future_available", bad.lls6g.userContext.RuntimeSRSPowerReference.AvailableSlot=46;
        case "future_producer", bad.lls6g.userContext.RuntimeSRSPowerReference.ProducerSlot=46;
        case "lifetime", bad.rf.frontend.ul_power_control.pathloss_reference_lifetime='configured_age_limit';
        case "effective_age", bad.lls6g.userContext.RuntimeSRSPowerReference.MaximumAgeSlots=20;
        case "lifecycle", bad.lls6g.userContext.RuntimeSRSPowerReference.ReferenceLifecycleStatus="no_received_reference_power_lifecycle";
    end
    reject(@()sixgr.link.runSRSChannelEstimation(bad,args{:}), ...
        'sixgr:srs:PathlossReferenceContextMismatch');
end
scope=struct('DeclaredSSBAndSIB1Boundary',true,'NativeSRSPreparations',1, ...
    'RFExecutions',0,'ReceiverExecutions',0,'ScenarioQualified',false);
save(fullfile(folder,'preparation.mat'),'reference','decision','finiteDecision','power','measured','scope');
fprintf('SRS_RETAINED_REFERENCE_PREPARATION_PASS producer=1 available=5 decision=41 resource=45 prepare=1 RF=0 RX=0 folder=%s\n',folder);
ok=true;
end

function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'test:WrongRejection','%s',getReport(cause)); return;
end
error('test:ExpectedRejection','Missing rejection %s.',id);
end
