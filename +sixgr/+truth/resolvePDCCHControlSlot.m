function slotOneBased = resolvePDCCHControlSlot(grant, runtimeSlotOneBased)
%RESOLVEPDCCHCONTROLSLOT Bind PDCCH to control time, never future data time.
% Canonical scheduler/TimingDecision control slots are zero based. The
% coupled runtime ControlSlot alias and runtime argument are one based.
if nargin < 2, runtimeSlotOneBased = NaN; end
if ~(isstruct(grant) && isscalar(grant))
    error('sixgr:truth:InvalidPDCCHControlSlot', 'Grant must be a scalar struct.');
end
control0 = localSlot(sixgr.util.structGet(grant,'ControlAbsoluteSlot',NaN),false);
alias1 = localSlot(sixgr.util.structGet(grant,'ControlSlot',NaN),true);
runtime1 = localSlot(runtimeSlotOneBased,true);
decision = sixgr.util.structGet(grant,'TimingDecision',struct());
if ~(isstruct(decision) && isscalar(decision))
    error('sixgr:truth:InvalidPDCCHControlSlot', 'TimingDecision must be a scalar struct.');
end
if ~isempty(fieldnames(decision))
    convention = string(sixgr.util.structGet(decision,'IndexConvention',""));
    if ~isequal(sixgr.util.structGet(decision,'Valid',false),true) || ...
            ~isscalar(convention) || convention ~= "zero_based"
        error('sixgr:truth:InvalidPDCCHControlSlot', ...
            'A control TimingDecision must be valid and explicitly zero based.');
    end
    control0 = localMerge(control0,localSlot( ...
        sixgr.util.structGet(decision,'ControlAbsoluteSlot',NaN),false));
end
control0 = localMerge(control0,alias1-1);
control0 = localMerge(control0,runtime1-1);
if isnan(control0)
    error('sixgr:truth:MissingPDCCHControlSlot', ...
        'An integrated PDCCH grant requires an absolute control slot; a data Slot is not control authority.');
end
slotOneBased = control0 + 1;
end

function value = localSlot(value,oneBased)
if isempty(value), value = NaN; end
if ~(isnumeric(value) && isscalar(value) && isreal(value) && ...
        (isnan(value) || (isfinite(value) && value == fix(value) && value >= double(oneBased))))
    error('sixgr:truth:InvalidPDCCHControlSlot', ...
        'Control slots must be finite integers in their declared index convention, or unset NaN.');
end
value = double(value);
end

function value = localMerge(value,other)
if isfinite(value) && isfinite(other) && value ~= other
    error('sixgr:truth:PDCCHControlSlotMismatch', ...
        'Conflicting absolute PDCCH control slots: %g and %g (zero based).',value,other);
end
if isfinite(other), value = other; end
end
