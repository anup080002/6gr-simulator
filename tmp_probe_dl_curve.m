setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg = sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml');
cfg = sixgr.lls6g.buildInternalConfig(scfg,pwd);
dlLow = sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',4,'SNR_dB',-10);
dlMid = sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',4,'SNR_dB',10);
dl20 = sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',4,'SNR_dB',20);
dl30 = sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',4,'SNR_dB',30);
res = table([-10;10;20;30],[dlLow.BLER;dlMid.BLER;dl20.BLER;dl30.BLER],[dlLow.Throughput_Mbps;dlMid.Throughput_Mbps;dl20.Throughput_Mbps;dl30.Throughput_Mbps],[mean(dlLow.TrialTable.MeasuredSINR_dB,'omitnan');mean(dlMid.TrialTable.MeasuredSINR_dB,'omitnan');mean(dl20.TrialTable.MeasuredSINR_dB,'omitnan');mean(dl30.TrialTable.MeasuredSINR_dB,'omitnan')],'VariableNames',{'SNR_dB','BLER','Throughput_Mbps','MeasuredSINR_dB_mean'});
disp(res);
