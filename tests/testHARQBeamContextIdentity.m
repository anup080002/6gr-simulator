function ok=testHARQBeamContextIdentity()
% Exact H4 context regression; no waveform/beam-performance claim.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_short.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.pdsch.RNTI=4660; cfg.phy.pusch.RNTI=4660;
for fmt=["1_1","0_1"]
    baseline=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,fmt);
    selected=cfg; selected.phy.pdsch.qclTCI.state_id=18;
    selected.phy.pdsch.qclTCI.codepoint=2;
    changed=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(selected,fmt);
    assert(baseline.Digest~=changed.Digest && ...
        sixgr.phy.pdcch.harqContextDigest(baseline)==sixgr.phy.pdcch.harqContextDigest(changed));
    % Any other installed-field change remains visible in the HARQ key.
    names={'RNTIValue','ConfigurationEpoch','ScheduledServingCell', ...
        'ScheduledCarrier','ScheduledBWP','ActiveDLBWPSize','ActiveULBWPSize'};
    for k=1:numel(names)
        data=changed.Data; data.(names{k})=data.(names{k})+1;
        other=sixgr.phy.pdcch.DCIContext(data);
        assert(sixgr.phy.pdcch.harqContextDigest(other)~= ...
            sixgr.phy.pdcch.harqContextDigest(baseline), ...
            'test:HARQContextFailOpen','Changed %s must not retain HARQ ownership.',names{k});
    end
end
fprintf('HARQ_BEAM_CONTEXT_IDENTITY_PASS exact_H4_contexts=2 protected_fields=14 no_waveform_claim=1\n');
ok=true;
end
