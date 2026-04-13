setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg = sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml');
cfg = sixgr.lls6g.buildInternalConfig(scfg,pwd);
dlLow = sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',4,'SNR_dB',4);
dlHigh = sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',4,'SNR_dB',29);
ulLow = sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',4,'SNR_dB',4);
ulHigh = sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',4,'SNR_dB',29);
disp(struct('dlLowBLER',dlLow.BLER,'dlHighBLER',dlHigh.BLER,'ulLowBLER',ulLow.BLER,'ulHighBLER',ulHigh.BLER,'dlLowSINR',mean(dlLow.TrialTable.MeasuredSINR_dB,'omitnan'),'dlHighSINR',mean(dlHigh.TrialTable.MeasuredSINR_dB,'omitnan'),'ulLowSINR',mean(ulLow.TrialTable.MeasuredSINR_dB,'omitnan'),'ulHighSINR',mean(ulHigh.TrialTable.MeasuredSINR_dB,'omitnan')));
