function [episodes, selectedRows] = summarizePBCHAccessEpisodes(T, strictPass)
%SUMMARIZEPBCHACCESSEPISODES Separate burst candidates from selected access.
% This is a reduction of receiver evidence, not a selection algorithm. Never
% choose another successfully decoded beam to rescue a failed selected beam.
arguments
    T table
    strictPass (:,1) logical
end
keys=["RunID","ExecutionID","UEIndex","ServingCell","Slot","SNR_dB"];
required=[keys,"SSBIndex","SelectedBeamFlag","SelectedSSBIndex", ...
    "SSBBurstSweepCoverageComplete","SSBBurstSweepExpectedCandidateCount", ...
    "SSBBurstSweepScope","SelectionSource"];
assert(all(ismember(required,string(T.Properties.VariableNames))) && ...
    numel(strictPass)==height(T), ...
    'sixgr:analytics:IncompletePBCHAccessIdentity', ...
    'Burst access reconciliation requires explicit execution, UE, slot and receiver-selection evidence.');
assert(all(string(T.SSBBurstSweepScope)=="configured_active_ss_burst_set"), ...
    'sixgr:analytics:MixedPBCHAccessScopes', ...
    'Do not combine independent trials and configured-burst candidate populations.');
% Preserve explicit realization/point identifiers when a joint table has
% repeated clocks. No grouping by slot alone or by decoded signal energy.
optional=["SweepPointIndex","RealizationIndex","DropIndex"];
keys=[keys,optional(ismember(optional,string(T.Properties.VariableNames)))];
[group,episodes]=findgroups(T(:,cellstr(keys)));
assert(all(isfinite(group)), 'sixgr:analytics:MissingPBCHAccessGroupKey', ...
    'Missing episode identity cannot be silently removed by grouping.');
n=height(episodes);
episodes.CandidateTrialCount=zeros(n,1);
episodes.CandidateStrictPassCount=zeros(n,1);
episodes.CandidateStrictFailureCount=zeros(n,1);
episodes.SelectedRowCount=zeros(n,1);
episodes.SelectedSSBIndex=nan(n,1);
episodes.SelectionValid=false(n,1);
episodes.AccessSuccess=false(n,1);
episodes.FailureReason=strings(n,1);
episodes.EvidenceSource=repmat("receiver_selected_pbch_burst_episode",n,1);
selectedRows=false(height(T),1);
for k=1:n
    ix=find(group==k);
    q=T(ix,:);
    expected=localNumeric(q.SSBBurstSweepExpectedCandidateCount);
    indices=localNumeric(q.SSBIndex);
    flags=localNumeric(q.SelectedBeamFlag);
    selected=localNumeric(q.SelectedSSBIndex);
    coverage=localNumeric(q.SSBBurstSweepCoverageComplete);
    chosen=find(flags==1);
    episodes.CandidateTrialCount(k)=numel(ix);
    episodes.CandidateStrictPassCount(k)=nnz(strictPass(ix));
    episodes.CandidateStrictFailureCount(k)=numel(ix)-nnz(strictPass(ix));
    episodes.SelectedRowCount(k)=numel(chosen);
    complete=all(isfinite(expected) & expected>=1 & expected==fix(expected)) && ...
        all(expected==numel(ix)) && all(coverage==1) && ...
        all(isfinite(indices) & indices>=0 & indices==fix(indices)) && ...
        numel(unique(indices))==numel(ix);
    if ismember('SSBBurstSweepObservedCandidateCount',q.Properties.VariableNames)
        complete=complete && all(localNumeric(q.SSBBurstSweepObservedCandidateCount)==numel(ix));
    end
    if ~complete
        episodes.FailureReason(k)="incomplete_or_duplicate_burst_candidates";
    elseif ~all(isfinite(flags) & (flags==0 | flags==1)) || numel(chosen)~=1
        episodes.FailureReason(k)="missing_or_ambiguous_received_selection";
    elseif ~all(isfinite(selected) & selected==indices(chosen))
        episodes.FailureReason(k)="received_selection_identity_mismatch";
    elseif ismissing(string(q.SelectionSource(chosen))) || ...
            strlength(strtrim(string(q.SelectionSource(chosen))))==0
        episodes.FailureReason(k)="missing_receiver_selection_provenance";
    else
        selectedRows(ix(chosen))=true;
        episodes.SelectedSSBIndex(k)=indices(chosen);
        episodes.SelectionValid(k)=true;
        episodes.AccessSuccess(k)=strictPass(ix(chosen));
        if ~episodes.AccessSuccess(k)
            episodes.FailureReason(k)="selected_pbch_mib_sib1_not_successful";
        end
    end
end
end

function v=localNumeric(v)
if isnumeric(v) || islogical(v), v=double(v); else, v=str2double(string(v)); end
v=v(:);
end
