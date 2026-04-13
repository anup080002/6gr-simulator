setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg = sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml');
cfg = sixgr.lls6g.buildInternalConfig(scfg,pwd);
ulLow = sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',4,'SNR_dB',-10);
ulMid = sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',4,'SNR_dB',10);
ul20 = sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',4,'SNR_dB',20);
ul30 = sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',4,'SNR_dB',30);
res = table([-10;10;20;30],[ulLow.BLER;ulMid.BLER;ul20.BLER;ul30.BLER],[ulLow.Throughput_Mbps;ulMid.Throughput_Mbps;ul20.Throughput_Mbps;ul30.Throughput_Mbps],[mean(ulLow.TrialTable.MeasuredSINR_dB,'omitnan');mean(ulMid.TrialTable.MeasuredSINR_dB,'omitnan');mean(ul20.TrialTable.MeasuredSINR_dB,'omitnan');mean(ul30.TrialTable.MeasuredSINR_dB,'omitnan')],'VariableNames',{'SNR_dB','BLER','Throughput_Mbps','MeasuredSINR_dB_mean'});
disp(res);
