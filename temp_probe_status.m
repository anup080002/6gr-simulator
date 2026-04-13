setup6GRSimToolkit('Verbose',false);
scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs','scenarios','lls_100mhz_tdlc_bidirectional_truth.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir,'status_probe'));
configs = { ...
 struct('snr',-10,'dlmcs',27,'ulmcs',27,'mod','256QAM'), ...
 struct('snr',-20,'dlmcs',27,'ulmcs',27,'mod','256QAM'), ...
 struct('snr',-30,'dlmcs',27,'ulmcs',27,'mod','256QAM'), ...
 struct('snr',-20,'dlmcs',28,'ulmcs',28,'mod','1024QAM'), ...
 struct('snr',-30,'dlmcs',28,'ulmcs',28,'mod','1024QAM')};
for i=1:numel(configs)
    p = configs{i};
    c = cfg;
    c.channel.snr_dB = p.snr;
    c.phy.pdsch.mcsIndex = p.dlmcs;
    c.phy.pusch.mcsIndex = p.ulmcs;
    c.phy.pdsch.modulation = p.mod;
    c.phy.pusch.modulation = p.mod;
    c.linkAdaptation.enabled = false;
    try
        dl = sixgr.link.runDLPDSCHThroughput(c,'NumFrames',8,'SNR_dB',p.snr);
    catch ME
        dl = struct('Ok',false,'BLER',nan,'Notes',string(ME.message));
    end
    try
        ul = sixgr.link.runULPUSCHThroughput(c,'NumFrames',8,'SNR_dB',p.snr);
    catch ME
        ul = struct('Ok',false,'BLER',nan,'Notes',string(ME.message));
    end
    fprintf('cfg %d snr=%g mod=%s dlmcs=%g ulmcs=%g | DL ok=%d bler=%g note=%s | UL ok=%d bler=%g note=%s\n', ...
        i,p.snr,string(p.mod),p.dlmcs,p.ulmcs,logical(dl.Ok),double(sixgr.util.structGet(dl,'BLER',NaN)),string(sixgr.util.structGet(dl,'Notes','')),logical(ul.Ok),double(sixgr.util.structGet(ul,'BLER',NaN)),string(sixgr.util.structGet(ul,'Notes','')));
end
