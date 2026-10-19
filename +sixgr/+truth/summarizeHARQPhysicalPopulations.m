function out=summarizeHARQPhysicalPopulations(trials,feedback,pucch)
% Independent counters; logical feedback is never a count of RF emissions.
out=struct('ContractVersion',"HARQPhysicalPopulations/v2", ...
    'TransportAttemptsObserved',height(trials),'DistinctRadioFrames',NaN, ...
    'LogicalFeedbackAssociations',NaN,'LogicalACKAssociations',NaN,'LogicalACKRate',NaN, ...
    'PhysicalPUCCHTransmissions',NaN,'PhysicalPUCCHInformationBits',NaN, ...
    'FeedbackStatus',"unavailable_identity_or_outcome", ...
    'PUCCHStatus',"unavailable_physical_identity_or_transmission_evidence");
if ~isempty(trials) && ismember('Frame',trials.Properties.VariableNames) && all(isfinite(trials.Frame))
    key=localScope(trials(:,{'Frame'}),trials);
    out.DistinctRadioFrames=height(unique(key,'rows'));
end
if ~isempty(feedback) && all(ismember({'TransmissionID','FeedbackOutcome'},feedback.Properties.VariableNames))
    keys=localScope(feedback(:,{'TransmissionID'}),feedback);
    if all(sixgr.truth.measurementValuePresent(feedback.TransmissionID)) && ...
            all(ismember(string(feedback.FeedbackOutcome),["ACK","NACK","DTX"]))
        [~,first,group]=unique(keys,'rows','stable');
        outcomes=string(feedback.FeedbackOutcome);
        assert(all(outcomes==outcomes(first(group))), ...
            'sixgr:truth:ConflictingHARQPopulation','Duplicate attempt identity has conflicting feedback.');
        out.LogicalFeedbackAssociations=numel(first);
        out.LogicalACKAssociations=nnz(outcomes(first)=="ACK");
        out.LogicalACKRate=out.LogicalACKAssociations/out.LogicalFeedbackAssociations;
        out.FeedbackStatus="counted_unique_attempt_associations_including_NACK_DTX";
    end
end
required={'PhysicalPUCCHOccasionId','PUCCHTransmissionPrepared','ExpectedBitCount'};
if ~isempty(pucch) && all(ismember(required,pucch.Properties.VariableNames))
    prepared=double(pucch.PUCCHTransmissionPrepared);
    if ~all(ismember(prepared,[0 1])), return; end
    sent=pucch(prepared==1,:);
    if isempty(sent)
        out.PhysicalPUCCHTransmissions=0; out.PhysicalPUCCHInformationBits=0;
        out.PUCCHStatus="observed_receiver_only_no_transmitted_payload"; return;
    end
    bits=double(sent.ExpectedBitCount);
    if any(~sixgr.truth.measurementValuePresent(sent.PhysicalPUCCHOccasionId)) || ...
            any(~isfinite(bits) | bits<0 | bits~=fix(bits)), return; end
    keys=localScope(sent(:,{'PhysicalPUCCHOccasionId'}),sent);
    [~,first,group]=unique(keys,'rows','stable');
    assert(all(bits==bits(first(group))), 'sixgr:truth:ConflictingPUCCHPopulation', ...
        'One physical occasion cannot have two transmitted payload lengths.');
    out.PhysicalPUCCHTransmissions=numel(first);
    out.PhysicalPUCCHInformationBits=sum(bits(first));
    out.PUCCHStatus="counted_unique_prepared_physical_occasions_no_receiver_only_trials";
end
end
function key=localScope(key,T)
for field=["RunID","ExecutionID","SweepPointIndex"]
    if ismember(field,string(T.Properties.VariableNames)), key.(field)=T.(field); end
end
end
