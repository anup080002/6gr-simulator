function ok=testFrozenSymbolAllocationReplay()
% Replay exact captured allocations; missing aliases never authorize drift.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
s=load(fullfile(root,'docs','lls','evidence_20260913', ...
    'dl_harq_replay_base_and_retx.mat'),'dlGrant');
g=s.dlGrant;
assert(~isfield(g,'SymbolAllocation'));
fixed=sixgr.link.restoreFrozenSymbolAllocation(g,g.PHYGrant,'DL');
assert(isequal(fixed.SymbolAllocation,g.PHYGrant.ResourceAllocation.SymbolAllocation));
assert(isequaln(fixed,sixgr.link.restoreFrozenSymbolAllocation(fixed,g.PHYGrant,'DL')));
bad=g; bad.TimingDecision.DataDecision.TargetStartSymbol= ...
    bad.TimingDecision.DataDecision.TargetStartSymbol+1;
reject(@()sixgr.link.restoreFrozenSymbolAllocation(bad,g.PHYGrant,'DL'), ...
    'sixgr:phy:grant:TimingIdentityMismatch');
reject(@()sixgr.link.restoreFrozenSymbolAllocation(g,struct(),'DL'), ...
    'sixgr:link:FrozenSymbolAllocationRequired');
reject(@()sixgr.link.restoreFrozenSymbolAllocation(g,g.PHYGrant,'UL'), ...
    'sixgr:phy:grant:TimingIdentityMismatch');
fprintf('FROZEN_SYMBOL_ALLOCATION_PASS captured_grant=1 negative_guards=3\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Unexpected error: %s',ME.identifier); return; end
error('test:MissingRejection','Expected frozen-allocation rejection.');
end
