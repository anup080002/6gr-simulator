function [ok,checks]=testCompletedCSIProjectionIdentity(actualApplicationMAT,outputRoot)
%TESTCOMPLETEDCSIPROJECTIONIDENTITY Value-copy negatives on retained evidence.
% Supply an original received_csi_later_application.mat from an actually
% completed shared DL application. Load only its value-only completedEvidence
% and finalized trial, not live owners, waveforms or prepared channel objects.
% This exercises the production post-commit projector; it does not repeat
% reception or establish execution from an authored JSON/receipt fixture.
%
% The projection must reject a row with a contradictory direction, sample
% plane, completion time or identity even when another subset of its fields
% matches. All mutations stay in local negative-test copies, never primary
% measurement tables. Exact owner revalidation remains the live builder's
% responsibility, already exercised by testCompletedCSIApplicationEvidence.
assert(nargin>=1 && isscalar(string(actualApplicationMAT)) && ...
    isfile(actualApplicationMAT),'test:CompletedCSIProjectionSourceRequired', ...
    'Supply one retained actual application MAT; no synthetic positive or passing skip.');
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
actualApplicationMAT=char(string(actualApplicationMAT));
sourceSHA=string(sixgr.util.sha256File(actualApplicationMAT));
source=load(actualApplicationMAT,'completedEvidence','trial');
assert(all(isfield(source,{'completedEvidence','trial'})) && ...
    istable(source.trial) && height(source.trial)==1, ...
    'test:CompletedCSIProjectionSourceRequired','Retain the original value-only evidence and final row together.');
e=source.completedEvidence; trial=source.trial;
project=@sixgr.truth.bindCompletedCSIApplicationEvidence;
bound=project(trial,e);
assert(isequaln(bound(:,trial.Properties.VariableNames),trial) && ...
    isequaln(project(bound,e),bound),'test:CompletedCSIProjectionReplay', ...
    'Exact retained source projection must be lossless and idempotent.');
names=string(trial.Properties.VariableNames);
receiverFields=["ObservationCompletionTime_s","ObservationCoverageSource", ...
    "RuntimeStageWaveformsUsed","ReceiverObservationHashPlane", ...
    "ReceiverObservationHashSerialization"];
assert(ismember("Direction",names) && string(trial.Direction)=="DL" && ...
    all(ismember(receiverFields,names)) && all(isfield(e.ReceiverInput,receiverFields)), ...
    'test:CompletedCSIProjectionSourceRequired','This regression needs the actual retained receiver-plane fields.');
for name=receiverFields
    assert(isequaln(trial.(name),e.ReceiverInput.(name)), ...
        'test:CompletedCSIProjectionOriginalMismatch','Original receiver field %s already disagrees.',name);
end
if nargin<2 || strlength(string(outputRoot))==0
    root=fileparts(fileparts(mfilename('fullpath')));
    outputRoot=tempname(fullfile(root,'logs'));
end
assert(isscalar(string(outputRoot)) && ~isfolder(outputRoot) && ~isfile(outputRoot), ...
    'test:CompletedCSIProjectionOutputExists','Use a new diagnostic folder.');
mkdir(outputRoot);
rows=repmat(struct('Check',"",'Passed',false,'ObservedErrorID',"", ...
    'Detail',"",'Scope',"retained_actual_value_projection_negative_no_PHY_execution"),0,1);

% Positive controls above and these existing rejection contracts make a
% missing new guard distinguishable from a malformed fixture/API call.
changed=trial; changed.FrozenGrantContextId="transplanted_physical_context";
runNegative("physical_grant_identity",changed);
changed=trial; changed.GrantContextId="transplanted_logical_context";
runNegative("logical_grant_identity",changed);
changed=trial; changed.ReceivedAssignmentDigest="transplanted_received_assignment";
runNegative("received_control_identity",changed);
changed=trial; changed.ReceiverObservationSHA256="transplanted_receiver_samples";
runNegative("receiver_sample_hash",changed);
changed=trial; changed.ObservationStartSample=changed.ObservationStartSample+1;
runNegative("receiver_start_sample",changed);
changed=trial; changed.ObservationEndSampleExclusive=changed.ObservationEndSampleExclusive+1;
runNegative("receiver_end_sample",changed);
changed=trial; changed.ObservationSampleRateHz=changed.ObservationSampleRateHz+1;
runNegative("receiver_sample_rate",changed);

% Expected-red missing projection guards in the original implementation.
% These names carry existing producer-owned semantics; no aliases, guessed
% epochs, inferred population or added successful receipt is introduced.
changed=trial; changed.Direction="UL";
runNegative("direction_cannot_be_relabelled",changed);
changed=trial;
changed.ObservationCompletionTime_s=changed.ObservationCompletionTime_s+1/double(trial.ObservationSampleRateHz);
runNegative("completion_time_matches_original_samples",changed);
changed=trial; changed.ObservationCoverageSource="declared_window_not_received_coverage";
runNegative("coverage_source_matches_original_receiver",changed);
changed=trial; changed.RuntimeStageWaveformsUsed=false;
runNegative("runtime_sample_use_cannot_be_denied",changed);
changed=trial; changed.ReceiverObservationHashPlane="transmitter_intent_not_decoder_input";
runNegative("sample_hash_plane_matches_original_receiver",changed);
changed=trial; changed.ReceiverObservationHashSerialization="another_sample_serialization";
runNegative("sample_hash_serialization_matches_original_receiver",changed);

% No mutation to the loaded source values or original evidence file, and
% no change to admitted CSI/frozen application status during these probes.
assert(isequaln(source.trial,trial) && isequaln(source.completedEvidence,e) && ...
    string(sixgr.util.sha256File(actualApplicationMAT))==sourceSHA);
checks=struct2table(rows);
scope=struct('SourceMAT',string(actualApplicationMAT),'SourceSHA256',sourceSHA, ...
    'SourceEvidenceSHA256',string(e.EvidenceSHA256), ...
    'OriginalCRCPass',double(trial.CRCPass),'AdditionalPHYExecutions',0, ...
    'OriginalApplicationRevalidated',false,'ULCompletionQualified',false, ...
    'FullScenarioQualified',false);
save(fullfile(outputRoot,'completion_projection_identity_checks.mat'),'checks','scope');
sixgr.util.csvWriteTable(fullfile(outputRoot,'completion_projection_identity_checks.csv'), ...
    checks,'PreserveSchema',true);
fprintf('COMPLETED_CSI_PROJECTION_IDENTITY checks=%d passed=%d additional_PHY=0 output=%s\n', ...
    height(checks),nnz(checks.Passed),string(outputRoot));
assert(all(checks.Passed),'test:CompletedCSIProjectionIdentityFailure', ...
    'Projection rejection failures: %s',strjoin(checks.Check(~checks.Passed),', '));
ok=true;

    function runNegative(name,changedRow)
        record=struct('Check',name,'Passed',false,'ObservedErrorID',"", ...
            'Detail',"",'Scope',"retained_actual_value_projection_negative_no_PHY_execution");
        try
            project(changedRow,e);
            record.ObservedErrorID="test:CompletedCSIProjectionMissingRejection";
            record.Detail="Contradictory receiver row was accepted.";
        catch failure
            record.ObservedErrorID=string(failure.identifier);
            record.Detail=string(failure.message);
            record.Passed=strcmp(failure.identifier,'sixgr:truth:CompletedCSIProjectionRow');
        end
        rows(end+1,1)=record;
        fprintf('COMPLETION_PROJECTION_CHECK name=%s pass=%d observed=%s\n', ...
            name,record.Passed,record.ObservedErrorID);
    end
end
