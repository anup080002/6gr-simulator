function out = classifyPUCCHGrantDisposition(grants, pucchTrials, puschReceiveOnlyAudit)
%CLASSIFYPUCCHGRANTDISPOSITION Prove how each scheduled feedback grant ended.
%
% A PUCCH grant has an auditable disposition only through an observed
% standalone PUCCH receiver trial (successful or failed), an exact same-waveform
% UCI-on-PUSCH decode consumed by HARQ state, or an explicitly finalized
% cancellation/censoring disposition. A failed observed trial remains a
% failure; it is not mislabeled as a missing trial or promoted to success.

if nargin < 2 || ~istable(pucchTrials)
    pucchTrials = table();
end
if nargin<3 || ~istable(puschReceiveOnlyAudit), puschReceiveOnlyAudit=table(); end
if ~istable(grants)
    grants = table();
end

n = height(grants);
scheduled = localLogical(grants, "GrantScheduledFlag", true(n, 1));
cancelled = localLogical(grants, "CanceledAtSweepBoundary", false(n, 1));
rightCensored = localLogical(grants, "RightCensored", false(n, 1));
finalized = localLogical(grants, "FinalizedFlag", true(n, 1));

transferContext = localString(grants, "PUSCHGrantContextId", repmat("", n, 1));
transferState = lower(localString(grants, "PUCCHGrantState", repmat("", n, 1)));
status = upper(localString(grants, "Status", repmat("", n, 1)));
statusPass = ismember(status, ["PASS","OK","SUCCESS","COMPLETED"]);
transferred = localLogical(grants, "MultiplexedOnPUSCH", false(n, 1)) & ...
    strlength(transferContext) > 0 & ...
    localLogical(grants, "PUSCHUCIDecodeOk", false(n, 1)) & ...
    localLogical(grants, "UCIContentMatch", false(n, 1)) & ...
    localLogical(grants, "RuntimeStateUpdated", false(n, 1)) & ...
    transferState == "pusch_uci_feedback_applied" & statusPass & finalized;

[standaloneObserved,standalone,receiverOnlyObserved] = localMatchedStandaloneReceiverRows(grants, pucchTrials);
puschReceiverOnlyObserved=localMatchedPowerWithheldPUSCH(grants,puschReceiveOnlyAudit);
if ismember('UETransmissionSuppressed',grants.Properties.VariableNames)
    noTX=localBinary(grants,"UETransmissionSuppressed",true);
    % A positive independent receiver row cannot override explicit original
    % UE silence and become a transmitted-success or transferred payload.
    transferred(noTX)=false;standaloneObserved(noTX)=false;standalone(noTX)=false;
end
standaloneFailed=standaloneObserved & ~standalone;
cancelled = cancelled & finalized;
rightCensorReason = lower(localString(grants, "CensorReason", repmat("", n, 1)));
rightCensorStatus = upper(localString(grants, "Status", repmat("", n, 1)));
rightCensored = rightCensored & finalized & ...
    strlength(rightCensorReason) > 0 & ...
    rightCensorReason ~= "not_applicable_for_active_pucch_grant_trace_runtime" & ...
    rightCensorStatus == "RIGHT_CENSORED";
resolved = ~scheduled | transferred | standaloneObserved | receiverOnlyObserved | puschReceiverOnlyObserved | cancelled | rightCensored;
reason = repmat("unresolved_scheduled_feedback_grant", n, 1);
reason(~scheduled) = "not_scheduled";
reason(cancelled) = "explicitly_finalized_cancellation";
reason(rightCensored) = "explicitly_finalized_right_censoring";
reason(standaloneFailed) = "matched_standalone_pucch_receiver_trial_failed";
reason(standalone) = "matched_standalone_pucch_receiver_trial_success";
reason(receiverOnlyObserved) = "power_deferred_UE_no_transmission_original_receiver_observed";
reason(puschReceiverOnlyObserved) = "power_deferred_UE_no_transmission_selected_PUSCH_receiver_observed";
reason(transferred) = "same_waveform_pusch_uci_decode_consumed";

rows = table(scheduled, transferred, standaloneObserved, standalone, standaloneFailed, ...
    receiverOnlyObserved, puschReceiverOnlyObserved, cancelled, rightCensored, resolved, reason, ...
    'VariableNames', {'Scheduled','TransferredOnPUSCH','StandalonePUCCHTrialObserved', ...
    'StandalonePUCCHTrialMatched','StandalonePUCCHTrialFailed', ...
    'PowerDeferredReceiverOnlyObserved','PowerDeferredPUSCHReceiverOnlyObserved', ...
    'CancelledFinalized','RightCensoredFinalized','Resolved','Disposition'});
if ismember("PUCCHGrantId", string(grants.Properties.VariableNames))
    rows.PUCCHGrantId = localString(grants, "PUCCHGrantId", repmat("", n, 1));
    rows = movevars(rows, "PUCCHGrantId", "Before", 1);
end

out = struct( ...
    "Rows", rows, ...
    "ScheduledCount", double(nnz(scheduled)), ...
    "TransferredCount", double(nnz(scheduled & transferred)), ...
    "StandaloneObservedCount", double(nnz(scheduled & standaloneObserved)), ...
    "StandaloneTrialCount", double(nnz(scheduled & standalone)), ...
    "StandaloneFailedCount", double(nnz(scheduled & standaloneFailed)), ...
    "ReceiverOnlyObservedCount", double(nnz(scheduled & receiverOnlyObserved)), ...
    "PUSCHReceiverOnlyObservedCount", double(nnz(scheduled & puschReceiverOnlyObserved)), ...
    "CancelledCount", double(nnz(scheduled & cancelled)), ...
    "RightCensoredCount", double(nnz(scheduled & rightCensored)), ...
    "ResolvedCount", double(nnz(scheduled & resolved)), ...
    "UnresolvedCount", double(nnz(scheduled & ~resolved)), ...
    "AllScheduledResolved", logical(all(~scheduled | resolved)), ...
    "SchemaVersion", "pucch_grant_disposition_v6");
end

function matched=localMatchedPowerWithheldPUSCH(grants,audit)
% An original selected-PUSCH receiver invocation is distinct from a PUCCH
% transmission/decoder and from successful UCI-on-PUSCH transfer. CRC/UCI
% false acceptance remains the receiver's result, never proof of UE TX.
matched=false(height(grants),1);
required=["ObservationID","GrantContextID","GNBControlObservationID","ReceivedUCIObservationID", ...
    "PowerAdmissionObservationID","LogicalPUCCHGrantIdSet","UEProducerDisposition", ...
    "UEReceivedCodebookDigest","PhysicalOccasionID","SelectedGNBTransport", ...
    "UEIndex","RNTI","ScheduledSlot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex", ...
    "AdmissionDecisionSample","ClockEpoch","ReceiverClockEpoch","ObservationStartSample","ObservationEndSampleExclusive", ...
    "AvailableAtSample","SampleRateHz","ReceiverInvocationCompleted","UETransmissionExecuted", ...
    "UEDataTransmissionExecuted","UEPUCCHTransmissionExecuted","TransmittedTBScored","Source"];
if isempty(grants)||isempty(audit)||~all(ismember(required,string(audit.Properties.VariableNames))), return; end
grantRequired=["PUCCHGrantId","UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier", ...
    "ActiveULBWP","SweepPointIndex","UETransmissionSuppressed","GrantExecutedFlag", ...
    "MultiplexedOnPUSCH","UEProducerDisposition","PowerAdmissionObservationID"];
if ~all(ismember(grantRequired,string(grants.Properties.VariableNames))), return; end
for field=["PUCCHGrantId","UEProducerDisposition","PowerAdmissionObservationID"]
    if ~isstring(grants.(field))||~isequal(size(grants.(field)),[height(grants),1]), return; end
end
n=height(audit); valid=true(n,1);
textFields=["ObservationID","GrantContextID","GNBControlObservationID","ReceivedUCIObservationID", ...
    "PowerAdmissionObservationID","LogicalPUCCHGrantIdSet","UEProducerDisposition", ...
    "UEReceivedCodebookDigest","PhysicalOccasionID","SelectedGNBTransport","Source"];
for field=textFields
    raw=audit.(field);
    if ~isstring(raw)||~isequal(size(raw),[n,1]), return; end
    valid=valid & ~ismissing(raw) & strlength(raw)>0;
end
for field=["UEIndex","RNTI","ScheduledSlot","BaseStationID","ComponentCarrier","ActiveULBWP", ...
        "SweepPointIndex","AdmissionDecisionSample","ClockEpoch","ReceiverClockEpoch","ObservationStartSample", ...
        "ObservationEndSampleExclusive","AvailableAtSample","SampleRateHz"]
    raw=audit.(field);
    if ~isnumeric(raw)||~isreal(raw)||~isequal(size(raw),[n,1]), return; end
    valid=valid & isfinite(raw)&raw>=0&raw==fix(raw)&raw<=flintmax;
end
valid=valid & localBinary(audit,"ReceiverInvocationCompleted",true) & ...
    localBinary(audit,"UETransmissionExecuted",false) & localBinary(audit,"UEDataTransmissionExecuted",false) & ...
    localBinary(audit,"UEPUCCHTransmissionExecuted",false) & localBinary(audit,"TransmittedTBScored",false) & ...
    audit.SelectedGNBTransport=="PUSCH" & ...
    audit.UEProducerDisposition=="closed_untransmitted_missing_measured_power_reference" & ...
    audit.Source=="stream_owned_gnb_capture_and_scheduled_grant_independent_receiver" & ...
    audit.ClockEpoch==audit.ReceiverClockEpoch & ...
    audit.SampleRateHz>0 & audit.ObservationEndSampleExclusive>audit.ObservationStartSample & ...
    audit.AvailableAtSample>=audit.ObservationEndSampleExclusive & ...
    audit.AdmissionDecisionSample<=audit.AvailableAtSample;
for field=["Placeholder","PlaceholderFlag","Fallback","FallbackFlag"]
    if ismember(field,string(audit.Properties.VariableNames))
        valid=valid & localBinary(audit,field,false);
    end
end
if ismember('ApproximationMode',audit.Properties.VariableNames)
    valid=valid & ismember(localString(audit,"ApproximationMode",strings(n,1)),["","none","not_applicable"]);
end
% A local projection of the ORIGINAL scheduled slot is not a new clock.
if ismember('Slot',audit.Properties.VariableNames)
    if ~isequaln(audit.Slot,audit.ScheduledSlot), return; end
end
view=audit;view.Slot=audit.ScheduledSlot;
for j=find(valid).'
    if nnz(audit.ObservationID==audit.ObservationID(j))~=1 || ...
            nnz(audit.PowerAdmissionObservationID==audit.PowerAdmissionObservationID(j))~=1, continue; end
    ids=split(audit.LogicalPUCCHGrantIdSet(j),'|');
    if any(strlength(ids)==0)||numel(unique(ids))~=numel(ids), continue; end
    originalIDs=grants.PUCCHGrantId(grants.PowerAdmissionObservationID==audit.PowerAdmissionObservationID(j));
    if ~isequal(sort(originalIDs(:)),sort(ids(:))), continue; end
    indices=zeros(numel(ids),1); good=true;
    for k=1:numel(ids)
        index=find(localString(grants,"PUCCHGrantId",strings(height(grants),1))==ids(k));
        if ~isscalar(index), good=false; break; end
        indices(k)=index;
        g=grants(index,:);
        for field=["UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex"]
            raw=g.(field);
            good=good && isnumeric(raw)&&isreal(raw)&&isscalar(raw)&&isfinite(raw)&& ...
                raw==fix(raw)&&raw==view.(field)(j);
        end
        good=good && localSameOccasion(g,view(j,:)) && ...
            localBinary(g,"UETransmissionSuppressed",true) && localBinary(g,"GrantExecutedFlag",false) && ...
            localBinary(g,"MultiplexedOnPUSCH",false) && ...
            localString(g,"UEProducerDisposition","")==audit.UEProducerDisposition(j) && ...
            localString(g,"PowerAdmissionObservationID","")==audit.PowerAdmissionObservationID(j);
        if ~good, break; end
    end
    if good, matched(indices)=true; end
end
end

function [observed,matched,receiverOnlyObserved] = localMatchedStandaloneReceiverRows(grants, trials)
n = height(grants);
observed = false(n, 1);
matched = false(n, 1);
receiverOnlyObserved = false(n, 1);
if isempty(grants) || ~(istable(trials) && ~isempty(trials))
    return;
end
grantVars = string(grants.Properties.VariableNames);
trialVars = string(trials.Properties.VariableNames);
if ~ismember("PUCCHGrantId", grantVars) || ~ismember("PUCCHGrantId", trialVars)
    return;
end

trialId = localString(trials, "PUCCHGrantId", repmat("", height(trials), 1));
attempted=localLogical(trials, "DetectionAttempted", false(height(trials), 1));
observationAvailable=localLogical(trials,"ControlObservationAvailable",true(height(trials),1));
finalized=localLogical(trials,"FinalizedFlag",true(height(trials),1));
placeholder=localLogical(trials,"Placeholder",false(height(trials),1)) | ...
    localLogical(trials,"PlaceholderFlag",false(height(trials),1));
fallback=localLogical(trials,"Fallback",false(height(trials),1)) | ...
    localLogical(trials,"FallbackFlag",false(height(trials),1));
mode=lower(localString(trials,"ApproximationMode",repmat("",height(trials),1)));
approximate=~ismember(mode,["","none","not_applicable"]);
% Identity plus a finalized non-placeholder row proves that a receiver
% trial record exists even when observation/detection itself failed.  Such
% a row is a failed trial disposition, never a "without trial rows" case.
trialObserved=finalized & ~placeholder & ~fallback & ~approximate;
% Receiver-only observations can decode noise/interference successfully.
% Such a result is never evidence that the UE transmitted its payload.
receiverOnly=localLogical(trials,"ReceiverOnlyAssignment",false(height(trials),1));
trialPass = trialObserved & attempted & observationAvailable & ...
    localLogical(trials, "DetectionUsable", false(height(trials), 1)) & ...
    localLogical(trials, "ReceiverUsable", false(height(trials), 1)) & ...
    localLogical(trials, "PUCCHDecodeOk", false(height(trials), 1)) & ...
    localLogical(trials, "UCIContentMatch", false(height(trials), 1));
crcApplicable = localLogical(trials, "CRCApplicable", ...
    localLogical(trials, "UCICRCApplicable", false(height(trials), 1)));
crcPass = localLogical(trials, "CRCPass", false(height(trials), 1));
trialPass = trialPass & (~crcApplicable | crcPass);
trialPass = trialPass & ~receiverOnly;
receiverOnlyEligible=localPowerDeferredReceiverEvidence(trials,trialObserved,observationAvailable);
% One physical PUCCH occasion can carry a codebook containing several
% logical HARQ-ACK grants.  In that case PUCCHGrantId identifies the
% physical occasion and LogicalPUCCHGrantIdSet preserves the exact logical
% grants consumed by the decoded bit vector.  Match both identity domains;
% requiring only the physical identifier incorrectly leaves every bundled
% logical grant unresolved even after a successful waveform decode.
grantId = localString(grants, "PUCCHGrantId", repmat("", n, 1));
logicalSets=localString(trials,"LogicalPUCCHGrantIdSet",repmat("",height(trials),1));
for i=1:n
    if ismissing(grantId(i)) || strlength(grantId(i))==0, continue; end
    sameID=trialId==grantId(i);
    for j=1:height(trials)
        if ~ismissing(logicalSets(j)) && strlength(logicalSets(j))>0
            sameID(j)=sameID(j) || any(strtrim(split(logicalSets(j),"|"))==grantId(i));
        end
    end
    % Grant IDs normally encode UE/occasion identity, but the independent
    % exported columns must agree too. Never credit another UE, BWP, sweep
    % point or physical slot merely because a copied ID string matches.
    same=localSameOccasion(grants(i,:),trials) & sameID;
    observed(i)=any(same & trialObserved & ~receiverOnly);
    matched(i)=any(same & trialPass);
    receiverOnlyObserved(i)=any(same & receiverOnlyEligible & localPowerDeferredGrantJoin(grants(i,:),trials));
end
end

function valid=localPowerDeferredReceiverEvidence(T,observed,available)
% Require the actual completion owner's original admission join. A producer
% disposition alone does not finalize the independent receiver window.
n=height(T); valid=false(n,1);
required=["ReceiverOnlyAssignment","PUCCHTransmissionPrepared","ExecutionBackend", ...
    "EvidenceClass","UEProducerDisposition","PowerAdmissionObservationID","PUCCHGrantId", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "FinalizedFlag","ControlObservationAvailable"];
if ~all(ismember(required,string(T.Properties.VariableNames))), return; end
valid=observed & available & localBinary(T,"ReceiverOnlyAssignment",true) & ...
    localBinary(T,"PUCCHTransmissionPrepared",false) & localBinary(T,"FinalizedFlag",true) & ...
    localBinary(T,"ControlObservationAvailable",true) & ...
    localString(T,"ExecutionBackend",strings(n,1))=="pucch_shared_gnb_receive_only" & ...
    localString(T,"EvidenceClass",strings(n,1))=="actual_shared_receiver_observation_no_PUCCH_transmission_claim" & ...
    localString(T,"UEProducerDisposition",strings(n,1))=="closed_untransmitted_missing_measured_power_reference";
id=localString(T,"PowerAdmissionObservationID",strings(n,1));
valid=valid & ~ismissing(id) & strlength(id)>0 & id==localString(T,"PUCCHGrantId",strings(n,1));
for name=["ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz"]
    v=T.(name);
    if ~isnumeric(v)||~isreal(v)||~isequal(size(v),[n,1]), valid(:)=false; return; end
    valid=valid & isfinite(v) & v>=0;
end
valid=valid & T.ObservationStartSample==fix(T.ObservationStartSample) & ...
    T.ObservationEndSampleExclusive==fix(T.ObservationEndSampleExclusive) & ...
    T.ObservationEndSampleExclusive>T.ObservationStartSample & T.ObservationSampleRateHz>0;
end

function valid=localPowerDeferredGrantJoin(grant,trials)
n=height(trials); valid=false(n,1);
required=["UETransmissionSuppressed","GrantExecutedFlag","UEProducerDisposition","PowerAdmissionObservationID"];
if ~all(ismember(required,string(grant.Properties.VariableNames))), return; end
identity=["UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex"];
if ~all(ismember(identity,string(grant.Properties.VariableNames))) || ...
        ~all(ismember(identity,string(trials.Properties.VariableNames))), return; end
if ~(localBinary(grant,"UETransmissionSuppressed",true) && ...
        localBinary(grant,"GrantExecutedFlag",false) && ...
        localString(grant,"UEProducerDisposition","")=="closed_untransmitted_missing_measured_power_reference")
    return;
end
id=localString(grant,"PowerAdmissionObservationID","");
if ismissing(id)||strlength(id)==0, return; end
valid=id==localString(trials,"PowerAdmissionObservationID",strings(n,1));
end

function value=localBinary(T,name,expected)
raw=T.(name); value=false(height(T),1);
if ~(isnumeric(raw)||islogical(raw))||~isreal(raw)||~isequal(size(raw),[height(T),1]), return; end
value=isfinite(raw)&raw==double(expected);
end

function same=localSameOccasion(grant,trials)
same=true(height(trials),1);
for field=["UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex"]
    g=ismember(field,string(grant.Properties.VariableNames));
    t=ismember(field,string(trials.Properties.VariableNames));
    if ~g && ~t
        % Legacy ID-only schemas remain readable. If either schema declares
        % a dimension, absent/NaN identity on the other side is not a match.
        continue;
    end
    if ~g || ~t, same(:)=false; continue; end
    a=str2double(string(grant.(field)));
    b=str2double(string(trials.(field)));
    same=same & isfinite(a) & isfinite(b) & a==fix(a) & b==fix(b) & a==b;
end
for field=["RunUUID","ConfigHash"]
    g=ismember(field,string(grant.Properties.VariableNames));
    t=ismember(field,string(trials.Properties.VariableNames));
    if ~g && ~t, continue; end
    if ~g || ~t, same(:)=false; continue; end
    a=strtrim(string(grant.(field))); b=strtrim(string(trials.(field)));
    aEmpty=ismissing(a) | strlength(a)==0;
    bEmpty=ismissing(b) | strlength(b)==0;
    % Legacy component exporters can write empty run metadata on both
    % tables. That does not override a present identity on either side;
    % the campaign acceptance audit separately requires a known run hash.
    same=same & ((aEmpty & bEmpty) | (~aEmpty & ~bEmpty & a==b));
end
end

function value = localLogical(T, field, defaultValue)
if ~ismember(string(field), string(T.Properties.VariableNames))
    value = logical(defaultValue(:));
    return;
end
raw = T.(char(field));
if islogical(raw)
    value = raw(:);
elseif isnumeric(raw)
    value = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    value = ismember(lower(strtrim(string(raw(:)))), ...
        ["1","true","yes","on","pass","passed","ok","success","completed"]);
end
value = logical(value(:));
end

function value = localString(T, field, defaultValue)
if ~ismember(string(field), string(T.Properties.VariableNames))
    value = string(defaultValue(:));
    return;
end
value = strtrim(string(T.(char(field))));
value = value(:);
end
