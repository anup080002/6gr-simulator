setup6GRSimToolkit(''Verbose'',false);
scfg = sixgr.lls6g.config.loadScenarioConfig(''simulator/configs/scenarios/lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_5gnb_50ue_10slot.yaml'');
cfg = sixgr.lls6g.buildInternalConfig(scfg,''results'');
out = sixgr.link.runULPUSCHThroughput(cfg,''NumFrames'',1,''SNR_dB'',12);
fprintf(''ok=%d skipped=%d bler=%g thr=%g\n'', logical(out.Ok), logical(out.Skipped), double(out.BLER), double(out.Throughput_Mbps));
fprintf(''notes=%s\n'', string(out.Notes));
fprintf(''trialRows=%g\n'', height(out.TrialTable));
