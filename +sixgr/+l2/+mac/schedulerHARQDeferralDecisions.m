function rows=schedulerHARQDeferralDecisions(info)
% Retain actual scheduler deferrals even when no new-data candidate exists.
rows=sixgr.util.structGet(info,'HARQDeferrals',table());
if ~istable(rows) || isempty(rows), rows=table(); return; end
n=height(rows);
% CSV/union-table evidence uses scalar columns. Keeping a two-column table
% variable makes older candidate rows acquire a one-column missing value
% and fails concatenation (or loses start/count meaning on export).
assert(size(rows.StoredSymbolAllocation,2)==2 && size(rows.AvailableSymbolAllocation,2)==2, ...
    'sixgr:mac:InvalidHARQDeferralAllocation','Deferrals require exact [start,count] allocations.');
rows.StoredStartSymbol0=rows.StoredSymbolAllocation(:,1);
rows.StoredNumSymbols=rows.StoredSymbolAllocation(:,2);
rows.AvailableStartSymbol0=rows.AvailableSymbolAllocation(:,1);
rows.AvailableNumSymbols=rows.AvailableSymbolAllocation(:,2);
rows.StoredSymbolAllocation=[]; rows.AvailableSymbolAllocation=[];
rows.RejectionReason=string(rows.Reason);
rows.CandidateScope=repmat("harq_retransmission",n,1);
rows.Scheduled=false(n,1); rows.Rejected=true(n,1); rows.HARQBlocked=true(n,1);
rows.DecisionKind=repmat("stored_harq_allocation_deferred",n,1);
rows.SourceClassification=repmat("runtime_scheduler_harq_deferral",n,1);
rows.ValueRole=repmat("runtime_scheduler_deferral_not_transmission",n,1);
rows.CandidateDecisionRowsAvailable=true(n,1);
rows.DecisionTruthStatus=repmat("runtime_scheduler_harq_deferral_truth",n,1);
end
