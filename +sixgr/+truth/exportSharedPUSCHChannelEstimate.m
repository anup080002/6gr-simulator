function T=exportSharedPUSCHChannelEstimate(root,T,snapshot,prepared,captures,replays,projection)
% Compatibility entry point retaining independent post-reception scoring.
assert(prepared.Direction=="UL",'sixgr:truth:PUSCHChannelExportIdentity', ...
    'PUSCH publication requires an actual uplink observation.');
T=sixgr.truth.exportSharedDataChannelEstimate(root,T,snapshot,prepared,captures,replays,projection);
end
