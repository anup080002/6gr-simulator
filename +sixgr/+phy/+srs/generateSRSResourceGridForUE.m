function out = generateSRSResourceGridForUE(srsCfg, ueId)
%GENERATESRSRESOURCEGRIDFORUE Generate a UE-tagged SRS grid bundle.

cfg = srsCfg;
cfg.UEId = double(ueId);
cfg.ConfigHash = sixgr.phy.srs.hashSRSConfig(cfg);
out = sixgr.phy.srs.generateSRSWaveform(cfg);
out.UEId = double(ueId);
out.ConfigHash = string(cfg.ConfigHash);
end
