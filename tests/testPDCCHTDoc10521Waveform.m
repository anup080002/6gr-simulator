function ok=testPDCCHTDoc10521Waveform
%TESTPDCCHTDOC10521WAVEFORM One short strict waveform-path check.
setup6GRSimToolkit("Verbose",false);
c=sixgr.phy.pdcch.tdoc.loadCampaignConfig( ...
    "simulator/configs/pdcch_tdoc10521/master.yaml");
c.Config.waveform.aggregation_levels=4;c.Config.waveform.channels={'AWGN'};
c.Config.waveform.channel_delay_spread_ns=0;c.Config.waveform.doppler_hz=0;
c.Config.waveform.snr_db=35;c.Config.waveform.trials_per_point=1;
w=sixgr.phy.pdcch.tdoc.WaveformSuite.run(c);
positive=w.Trials(w.Trials.ScenarioID=="LLS-00",:);
assert(height(positive)==1&&positive.CorrectDetection&&positive.CRCCheckPassed);
assert(positive.ExecutionBackend=="strict_pdcch_waveform_campaign_kernel");
assert(~positive.KnownLocationUsed&&~positive.OracleTimingUsed);
assert(isfinite(positive.CENMSE)&&positive.CENMSE>=0);
ok=true;fprintf("PDCCH TDoc 10.5.2.1 strict waveform check: PASS\n");
end
