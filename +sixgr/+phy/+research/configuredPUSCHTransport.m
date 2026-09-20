function transport=configuredPUSCHTransport(cfg,carrier)
% Build transport from endpoint-installed policy and its own allocation.
% No peer TX object, waveform, UCI contents or coding layout is accepted.
transport=[]; root=cfg.phy.pusch;
definition=sixgr.phy.research.resolveExperimentalMCSTable(root.mcsTable);
if isempty(definition)
    assert(~startsWith(string(root.mcsTable),"experimental_"), ...
        'sixgr:research:InvalidMCSTable','Unknown experimental MCS table.');
    return;
end
profile=sixgr.phy.pdcch.resolveConnectedMCS(root,double(root.mcsIndex));
assert(profile.Valid && string(root.modulation)==string(profile.Modulation), ...
    'sixgr:research:TransportMCSMismatch','Configured transport modulation must match its installed codepoint.');
[~,~,~,transport]=sixgr.phy.grid.allocPUSCHTransport(carrier,cfg);
end
