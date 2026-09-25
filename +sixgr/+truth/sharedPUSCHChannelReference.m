function [grid,evidence]=sharedPUSCHChannelReference(snapshot,prepared,captures,replays,projection)
% Compatibility entry point; all arithmetic lives in the shared data scorer.
assert(prepared.Direction=="UL",'sixgr:truth:MissingPUSCHChannelReference', ...
    'PUSCH scoring requires an actual uplink observation.');
[grid,evidence]=sixgr.truth.sharedDataChannelReference(snapshot,prepared,captures,replays,projection);
end
