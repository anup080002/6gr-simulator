function ok=testPUCCHTrialIndependentRetained(outputRoot)
% Retained actual shared IQ and received SRS timing. Counts are prescribed
% component hypotheses, not an independently scheduled missing-DCI test.
setup6GRSimToolkit('Verbose',false);
if nargin<1
    logsRoot=fullfile(pwd,'logs');
    if ~isfolder(logsRoot), mkdir(logsRoot); end
    outputRoot=tempname(logsRoot);
end
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve existing evidence.');
mkdir(outputRoot);
capture=fullfile('docs','lls','evidence_20260913','pucch_baseline_signal_04','received_pucch.mat');
x=load(capture); p=x.item.Context.Prepared; cfg=p.ReceiverConfig;
prior=x.timingReferences{1};
[~,pre,tx,replay,actual]=sixgr.truth.sharedObservationEvidence(x.item.Planes,p);
input=struct('Prepared',p,'Observation',actual,'PhysicalMeasurementObservation',pre, ...
    'TransmitterObservation',tx,'Replay',replay,'ChannelState',struct(), ...
    'Channel',struct('Profile',sixgr.channel.resolveConcreteProfile(cfg)), ...
    'ReceivedULTimingReference',prior);
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
audit=table();
for count=1:2
    context=sixgr.phy.pucch.UCIReportContext(struct( ...
        'ReportID',"gnb-retained-format0-"+count,'ConfigurationEpoch',rrc.ConfigurationEpoch, ...
        'Sequence1Length',count,'Sequence2Length',0,'HARQACKBits',count, ...
        'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
    assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
        'ObservationID',context.ReportID,'ResourceID',0,'RNTI',1,'AbsoluteSlot0',8, ...
        'Source','retained_component_prescribed_resource_and_length', ...
        'TimingSource','prior_received_SRS_clock'),rrc,context);
    input.GNBReception=struct('Assignment',assignment,'Context',context);
    saved=rng;
    trial=sixgr.link.runPUCCHWaveformTrial(x.item.Context.Config, ...
        x.item.Context.Arguments{:},'ReceivedContext',input);
    direct=sixgr.link.receivePUCCHObservation(cfg,assignment,context,actual,prior);
    assert(isequal(saved,rng));
    names=string(fieldnames(direct)); latency=cellstr(names(endsWith(names,'Latency_ms')));
    assert(isequaln(rmfield(trial.Rx,latency),rmfield(direct,latency)));
    assert(trial.IndependentReceiverAssignment && trial.ReceiverExpectedBitCount==count && ...
        ~trial.CRCApplicable && isnan(trial.CRCPass) && isempty(trial.CodeBlockCRCError) && ...
        ~trial.Rx.PreparedTransmitterConsumed && ~trial.Rx.InjectedNoiseVarianceConsumed && ...
        ~trial.Rx.ReceiveTiming.OracleTimingUsed);
    changed=input; changed.GNBReception.Context=x.item.Context.Prepared.RequestBinding.ReceiverContext;
    % The historical request may omit its context. Either way it cannot
    % replace the context bound into the independent receive assignment.
    reject(@()sixgr.link.runPUCCHWaveformTrial(x.item.Context.Config, ...
        x.item.Context.Arguments{:},'ReceivedContext',changed), ...
        'sixgr:link:InvalidGNBUCIReceiveHypothesis');
    audit=[audit;table(count,trial.DetectionMetric,trial.DetectionThreshold,trial.DTXFlag, ...
        string(trial.UCIDecodedBitVector),true,'VariableNames', ...
        {'RXExpectedBits','DetectionMetric','DetectionThreshold','DTX','DecodedBits','DirectRXEqual'})]; %#ok<AGROW>
end
writetable(audit,fullfile(outputRoot,'retained_receiver_authority_audit.csv'));
fprintf('PUCCH_TRIAL_RETAINED_INDEPENDENT_PASS hypotheses=2 actual_shared_IQ=1 prior_received_SRS=1 evidence=retained_component\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
