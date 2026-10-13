function ok=testH4100CausalRAStagePublication()
% Physical access regression on the requested full H4 configuration.
% Starts at an explicit configured SSB-selection boundary; this does not
% claim to exercise cold SSB acquisition, connected traffic or full-run acceptance.
ok=testTDDCausalFourStepRARuntimeTiming(2,fullfile( ...
    'simulator','configs','scenarios','h4_100_cdlc100_connected_adaptive.yaml'));
end
