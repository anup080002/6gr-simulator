function ok=testSharedSRSPowerAdmission()
% Exact production SRS preparation admission, not full access qualification.
% Access/TAG and published SSB measurements below are declared boundary
% fixtures. One native SRS PrepareOnly/queue is real; RF/channel/RX never run.
setup6GRSimToolkit('Verbose',false);
prior=rng; restore=onCleanup(@()rng(prior)); %#ok<NASGU>
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
% Explicit finite-age research-policy regression; the retained-filter mode
% has separate original-power/capture lifecycle tests.
s=s.toStruct();
assert(string(s.rf_frontend.ul_power_control.pathloss_reference_lifetime)=="retained_filtered_reference");
s.rf_frontend.ul_power_control.pathloss_reference_lifetime='configured_age_limit';
folder=fullfile(pwd,'results','validation','shared_srs_power_admission', ...
    char(java.util.UUID.randomUUID())); mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(s,folder); cfg.run.rootRunFolder=folder;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),0);
state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,1,0);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,cfg.run.totalSlots,0);
state.CurrentServingIdx(:)=1;
% Use the actual n40 SIB1 tree, including its 30-kHz initial UL BWP. The
% codec result is not evidence that the shared receiver acquired this cell.
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
received=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),received);
common=installed.UECommonCellConfiguration;
common.ServingCell=1; common.AvailableSlot=1;
common.ConfigurationEpoch=cfg.initial_access.configuration_epoch;
assert(common.InitialULBWP.SubcarrierSpacing_kHz==30);
state.UECommonCellConfigurationByUE={common};
fresh=publish(state,1,1);
groups=0;

% The real resolver decides age at the SRS resource, independently of the
% knowledge clock. Neither missing data nor stale data is turned into IQ.
for condition=["missing","missing_sib1","future_sib1","future_rsrp","wrong_beam","stale"]
    v=fresh; target=5;
    switch condition
        case "missing", v=state;
        case "missing_sib1", v.UECommonCellConfigurationByUE={struct()};
        case "future_sib1", v.UECommonCellConfigurationByUE{1}.AvailableSlot=6;
        case "future_rsrp", v.ReferenceSignalMeasurementTable.AvailableSlot(:)=6;
        case "wrong_beam", v.ReferenceSignalMeasurementTable.ResourceId(:)=1;
        case "stale", target=25;
    end
    v.CurrentSlot=target;
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
    original=v; originalCfg=bound; random=rng;
    [admit,row]=sixgr.truth.resolveSharedSRSPowerAdmission(v,bound,1,target);
    assert(~admit && ~row.PreparationAdmitted && row.MeasuredPowerReferenceRequired && ...
        ~row.SRSTransmissionPrepared && ~row.SRSReceiverExecuted && ...
        row.PowerReferenceStatus==bound.lls6g.userContext.RuntimeSRSPowerReference.Status && ...
        row.Action=="defer_SRS_unavailable_measured_power_reference" && ...
        row.EvidenceClass=="preparation_admission_not_PHY_execution" && ...
        isequaln(v,original) && isequaln(bound,originalCfg) && isequal(random,rng));
    if condition=="stale", assert(row.PowerReferenceStatus=="stale"); end
end
groups=groups+1;
v=fresh; v.CurrentSlot=25;
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
[admit,old]=sixgr.truth.resolveSharedSRSPowerAdmission(v,bound,1,25);
assert(~admit && old.PowerReferenceStatus=="stale");
v=publish(v,24,24);
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
[admit,row]=sixgr.truth.resolveSharedSRSPowerAdmission(v,bound,1,25);
assert(admit && row.PowerReferenceProducerSlot==24 && row.PowerReferenceAvailableSlot==24 && ...
    row.MaximumPowerReferenceAgeSlots==20 && row.PowerReferenceRS=="SSB-0");
% A future plan cannot consume a row that arrives after its decision.
v.RuntimeViewMode="future_ul_grant_planning"; v.PlanningDecisionSlot=23;
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
[admit,row]=sixgr.truth.resolveSharedSRSPowerAdmission(v,bound,1,25);
assert(~admit && row.DecisionSlot==23 && row.SRSResourceSlot==25);
groups=groups+1;

v=fresh; v.CurrentSlot=5;
[bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,v,1,'UL');
for defect=["missing","numeric_usable","changed_power","changed_identity"]
    bad=bound;
    switch defect
        case "missing", bad.lls6g.userContext.RuntimeSRSPowerReference=struct();
        case "numeric_usable", bad.lls6g.userContext.RuntimeSRSPowerReference.Usable=1;
        case "changed_power", bad.lls6g.userContext.RuntimeSRSPowerReference.Pathloss_dB=0;
        case "changed_identity", bad.lls6g.userContext.RuntimeSRSPowerReference.MeasurementId="unrelated";
    end
    reject(@()sixgr.truth.resolveSharedSRSPowerAdmission(v,bad,1,5), ...
        'sixgr:srs:PreparationAdmissionContext');
end
bad=bound; bad.lls6g.userContext.RuntimeCurrentDirection='DL';
reject(@()sixgr.truth.resolveSharedSRSPowerAdmission(v,bad,1,5),'sixgr:srs:PreparationAdmissionIdentity');
bad=bound; bad.rf.frontend.ul_power_control.srs.pathloss_reference.reference_signal_type='CSI-RS';
reject(@()sixgr.truth.resolveSharedSRSPowerAdmission(v,bad,1,5),'sixgr:srs:PreparationAdmissionConfiguration');
bad=bound; bad.rf.frontend.ul_power_control.srs.pathloss_reference.reference_signal_id=-1;
reject(@()sixgr.truth.resolveSharedSRSPowerAdmission(v,bad,1,5),'sixgr:refsig:InvalidPathlossReferenceSignalId');
% Admission-only policy boundary, not a normalized physical execution.
bad=bound; bad.rf.frontend.ul_power_control.require_measured_reference_rs=false;
bad.lls6g.userContext.RuntimeSRSPowerReference=struct();
[admit,row]=sixgr.truth.resolveSharedSRSPowerAdmission(v,bad,1,5);
assert(admit && ~row.MeasuredPowerReferenceRequired && row.PowerReferenceStatus=="not_required_by_applied_power_mode");
bad=bound; bad.run.noiseOperatingMode='standalone_awgn_snr_argument';
bad.lls6g.userContext.RuntimeSRSPowerReference=struct();
[admit,row]=sixgr.truth.resolveSharedSRSPowerAdmission(v,bad,1,5);
assert(admit && ~row.MeasuredPowerReferenceRequired);
groups=groups+1;

% Original caller-body proof: retain all dependencies unchanged. No test
% switch or hook is added to production. Only its main function name changes.
[prepare,projectionCleanup,sourceHash]=projection(); %#ok<ASGLU>
state.AccessState(1)="succeeded"; state.LastSuccessfulPRACHSlotByUE(1)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
tag=struct('DLReference',struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',0,'AvailableAtSample',0), ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.03*fs));
state.ConnectedULTimingByUE={tag};
assert(isempty(sixgr.util.structGet(state,'SharedUEULPowerControlStates',{})), ...
    'test:SRSUnexpectedPowerState','The missing-reference call must start without a power-control owner.');
before=state; pending=owner.Pending; trace=owner.Events.ExecutionTrace;
% Public read-only event inspection covers every possible preparation in
% this run; do not expose the coordinator's private decision array.
horizon=sixgr.phy.frame.slotStartSample(carrier,cfg.run.totalSlots+1,fs);
assert(owner.Events.nextEventSample(horizon)==horizon);
ledger=owner.Physical.readRFExecutionLedger(); channel=owner.directionalChannelState(1,'DL');
random=rng; queuedUL=struct([]);
[deferred,afterUL,queued]=prepare(state,cfg,1,0,queuedUL);
assert(~queued && isequaln(afterUL,queuedUL) && isequaln(owner.Pending,pending) && ...
    owner.Events.nextEventSample(horizon)==horizon && isequaln(owner.Events.ExecutionTrace,trace) && ...
    owner.Events.NextSampleIndex==0 && isequaln(owner.Physical.readRFExecutionLedger(),ledger) && ...
    owner.directionalChannelState(1,'DL').CurrentSampleIndex==channel.CurrentSampleIndex && ...
    isempty(sixgr.util.structGet(deferred,'SharedUEULPowerControlStates',{})) && isequal(random,rng));
assert(isequaln(rmfield(deferred,'ControlTrials'),rmfield(before,'ControlTrials')));
beforeControl=before.ControlTrials; afterControl=deferred.ControlTrials;
if isfield(beforeControl,'SRSResourceDecisions'), beforeControl=rmfield(beforeControl,'SRSResourceDecisions'); end
afterControl=rmfield(afterControl,'SRSResourceDecisions');
assert(isequaln(beforeControl,afterControl));
audit=deferred.ControlTrials.SRSResourceDecisions;
assert(height(audit)==1 && ~audit.PreparationAdmitted && audit.SRSResourceSlot==5 && audit.DecisionSlot==1);
groups=groups+1;
% Same owner, unchanged clock, now receives a declared public measurement
% boundary. Fresh reference permits native SRS preparation and original queue.
retry=publish(deferred,1,1);
[prepared,afterUL,queued]=prepare(retry,cfg,1,0,queuedUL);
assert(queued && isequaln(afterUL,queuedUL) && owner.hasPending('SRS',1) && ...
    owner.Events.nextEventSample(horizon)<horizon && ...
    owner.Events.NextSampleIndex==0 && isequaln(owner.Events.ExecutionTrace,trace) && ...
    isequaln(owner.Physical.readRFExecutionLedger(),ledger) && ...
    isequaln(prepared.LastSRSSlotByUE,before.LastSRSSlotByUE) && ...
    isequaln(prepared.LastSuccessfulSRSSlotByUE,before.LastSuccessfulSRSSlotByUE));
item=owner.Pending(string({owner.Pending.Kind})=="SRS");
assert(isscalar(item) && item.Context.Slot==5 && item.Context.DecisionSlot==1 && ...
    isa(prepared.SharedUEULPowerControlStates{1},'sixgr.link.ReceivedULPowerControlState'));
p=item.Context.Prepared; ref=p.Metadata.PowerEvidence.Reference;
assert(isa(p,'sixgr.link.PreparedUplinkControlTransmission') && p.Channel=="SRS" && ...
    p.NumPhysicalTransmitAntennas==4 && p.NumReceiveAntennas==64 && ...
    ref.Usable && ref.ProducerSlot==1 && ref.AvailableSlot==1 && ...
    ref.Pathloss_dB==common.SSPBCHBlockPower_dBm+90 && ...
    item.Context.Config.lls6g.userContext.RuntimeSRSPowerReference.MeasurementId==ref.MeasurementId && ...
    ~isempty(p.Tx.Waveform) && all(isfinite(p.Tx.Waveform),'all'));
audit=prepared.ControlTrials.SRSResourceDecisions;
assert(height(audit)==2 && isequal(audit.PreparationAdmitted,[false;true]) && ...
    ~any(audit.SRSTransmissionPrepared) && ~any(audit.SRSReceiverExecuted));
sixgr.util.csvWriteTable(fullfile(folder,'preparation_admission.csv'),audit,'PreserveSchema',true);
scope=struct('SourceSHA256',sourceHash,'SourceBodyExact',true, ...
    'AccessAndReceivedReferenceBoundaryDeclared',true,'NativeSRSPreparations',1, ...
    'QueuedSRS',1,'RFExecutions',0,'ChannelExecutions',0,'SRSReceiverExecutions',0, ...
    'FullScenarioQualified',false);
save(fullfile(folder,'preparation_evidence.mat'),'audit','scope','ref');
assert(string(sixgr.util.sha256File(which('sixgr.truth.runWaveformLinkBundle')))==sourceHash);
groups=groups+1;
fprintf('SHARED_SRS_POWER_ADMISSION_PASS groups=%d exact_source=%s prepare=1 RX=0 folder=%s\n', ...
    groups,sourceHash,folder);
ok=true;
end

function state=publish(state,sourceSlot,availableSlot)
row=table(0,110,"SSB-0","declared_admission_boundary_diagnostic",1,-90,20, ...
    'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB', ...
    'PathlossReferenceRS','MeasuredReferenceSignalPathlossSource','ServingCell', ...
    'SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,row,'ProducerSlot',sourceSlot,'AvailableSlot',availableSlot, ...
    'Valid',true,'Direction','DL','SourceSignal','SSB', ...
    'MeasurementSource','declared_admission_boundary_not_on_air');
end

function [fn,cleanup,hash]=projection()
path=which('sixgr.truth.runWaveformLinkBundle'); source=fileread(path);
names=["localPrepareSharedSRS","localResolveCoupledSRSPUSCHResourceDecision", ...
    "localSerializeExactCollisionDecision","localAppendCompatTable", ...
    "localAppendRuntimeLog","localRuntimeLogPath"];
parts=cell(1,numel(names));
for k=1:numel(names)
    start=regexp(source,['(?m)^function[^\r\n]*\<' char(names(k)) '\('],'start');
    assert(isscalar(start),'Require one exact production local function.');
    following=regexp(source(start+1:end),'(?m)^function ','start');
    stop=numel(source); if ~isempty(following), stop=start+following(1)-1; end
    parts{k}=source(start:stop);
end
original=parts{1};
parts{1}=strrep(original,'localPrepareSharedSRS(','srsPreparationOwnerProjection(');
assert(strcmp(strrep(parts{1},'srsPreparationOwnerProjection(','localPrepareSharedSRS('),original));
generated=strjoin(parts,'');
folder=tempname; mkdir(folder); file=fullfile(folder,'srsPreparationOwnerProjection.m');
cleanup=onCleanup(@()cleanupProjection(folder,file));
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); close=onCleanup(@()fclose(fid));
fwrite(fid,generated,'char'); clear close;
assert(strcmp(fileread(file),generated),'The installed test projection must preserve all exact source bytes.');
addpath(folder); fn=@srsPreparationOwnerProjection; hash=string(sixgr.util.sha256File(path));
end

function cleanupProjection(folder,file)
if any(strcmp(strsplit(path,pathsep),folder)), rmpath(folder); end
if isfile(file), delete(file); end
if isfolder(folder), rmdir(folder); end % Only the new, now empty test scratch.
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, received %s: %s',id,cause.identifier,cause.message); return;
end
error('test:SRSAdmissionMissingGuard','Expected %s.',id);
end
