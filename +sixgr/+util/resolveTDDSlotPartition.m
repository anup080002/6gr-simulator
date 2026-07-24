function partition = resolveTDDSlotPartition(cfg, absoluteSlot)
%RESOLVETDDSLOTPARTITION Resolve one canonical zero-based TDD slot.
%
% This utility is a compatibility entry point only.  It consumes the
% immutable symbol-level state attached by FrameStructureEngine or delegates
% to that facade.  It has no compact-pattern parser and no legacy fallback.

if nargin < 2
    error("sixgr:util:resolveTDDSlotPartition:MissingAbsoluteSlot", ...
        "An explicit zero-based absolute slot is required.");
end
validateattributes(absoluteSlot, {'numeric'}, ...
    {'scalar','integer','nonnegative','finite'});
if ~(isstruct(cfg) && isscalar(cfg))
    error("sixgr:util:resolveTDDSlotPartition:BadConfig", ...
        "cfg must be one scalar resolved configuration struct.");
end

duplexMode = upper(string(sixgr.util.structGet(cfg, ...
    "phy.duplex.mode", ...
    sixgr.util.structGet(cfg, "frequency.duplex_mode", ""))));
if duplexMode ~= "TDD"
    error("sixgr:phy:frame:TDDResolverCalledForFDD", ...
        "TDD slot partitioning requires DuplexMode=TDD.");
end

state = sixgr.util.structGet(cfg, ...
    "phy.frameStructure.SlotState", struct());
if isstruct(state) && isfield(state, "CommonDirection") && ...
        isfield(state, "ResolvedDirection")
    partition = sixgr.phy.FrameStructureEngine. ...
        SlotPartitionFromState(state, absoluteSlot);
    return;
end

engine = sixgr.phy.FrameStructureEngine(cfg);
partition = engine.SlotPartition(absoluteSlot);
end
