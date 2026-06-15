function [tx, occasion] = generateMsg1PRACHWaveform(cfg, raCfg)
%GENERATEMSG1PRACHWAVEFORM Generate MSG1 PRACH waveform for the selected preamble.
prachCfg = sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg, raCfg);
occasion = sixgr.rach.mapPRACHToOccasion(prachCfg, "OccasionIndex", 1);
tx = sixgr.rach.generatePRACHWaveform(prachCfg, "Occasion", occasion, ...
    "PreambleIndex", double(raCfg.PreambleIndex));
tx.PRACHRuntimeConfig = prachCfg;
end
