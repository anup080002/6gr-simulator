function out = classifyPUCCHGrantDisposition(grants, pucchTrials)
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

[standaloneObserved,standalone] = localMatchedStandaloneReceiverRows(grants, pucchTrials);
standaloneFailed=standaloneObserved & ~standalone;
cancelled = cancelled & finalized;
rightCensorReason = lower(localString(grants, "CensorReason", repmat("", n, 1)));
rightCensorStatus = upper(localString(grants, "Status", repmat("", n, 1)));
rightCensored = rightCensored & finalized & ...
    strlength(rightCensorReason) > 0 & ...
    rightCensorReason ~= "not_applicable_for_active_pucch_grant_trace_runtime" & ...
    rightCensorStatus == "RIGHT_CENSORED";
resolved = ~scheduled | transferred | standaloneObserved | cancelled | rightCensored;
reason = repmat("unresolved_scheduled_feedback_grant", n, 1);
reason(~scheduled) = "not_scheduled";
reason(cancelled) = "explicitly_finalized_cancellation";
reason(rightCensored) = "explicitly_finalized_right_censoring";
reason(standaloneFailed) = "matched_standalone_pucch_receiver_trial_failed";
reason(standalone) = "matched_standalone_pucch_receiver_trial_success";
reason(transferred) = "same_waveform_pusch_uci_decode_consumed";

rows = table(scheduled, transferred, standaloneObserved, standalone, standaloneFailed, ...
    cancelled, rightCensored, resolved, reason, ...
    'VariableNames', {'Scheduled','TransferredOnPUSCH','StandalonePUCCHTrialObserved', ...
    'StandalonePUCCHTrialMatched','StandalonePUCCHTrialFailed', ...
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
    "CancelledCount", double(nnz(scheduled & cancelled)), ...
    "RightCensoredCount", double(nnz(scheduled & rightCensored)), ...
    "ResolvedCount", double(nnz(scheduled & resolved)), ...
    "UnresolvedCount", double(nnz(scheduled & ~resolved)), ...
    "AllScheduledResolved", logical(all(~scheduled | resolved)), ...
    "SchemaVersion", "pucch_grant_disposition_v4");
end

function [observed,matched] = localMatchedStandaloneReceiverRows(grants, trials)
n = height(grants);
observed = false(n, 1);
matched = false(n, 1);
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
trialPass = trialObserved & attempted & observationAvailable & ...
    localLogical(trials, "DetectionUsable", false(height(trials), 1)) & ...
    localLogical(trials, "ReceiverUsable", false(height(trials), 1)) & ...
    localLogical(trials, "PUCCHDecodeOk", false(height(trials), 1)) & ...
    localLogical(trials, "UCIContentMatch", false(height(trials), 1));
crcApplicable = localLogical(trials, "CRCApplicable", ...
    localLogical(trials, "UCICRCApplicable", false(height(trials), 1)));
crcPass = localLogical(trials, "CRCPass", false(height(trials), 1));
trialPass = trialPass & (~crcApplicable | crcPass);
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
    observed(i)=any(same & trialObserved);
    matched(i)=any(same & trialPass);
end
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
