function cfg = prepareValidationConfig(cfgIn, opt)
%PREPAREVALIDATIONCONFIG Normalize a strict waveform-truth validation config.

cfg = cfgIn;
cfg.run.mode = "both";
cfg.run.shortRun = true;
cfg.run.strictMode = true;
cfg.run.noProxyTruthContract = true;
cfg.run.useMex = false;
cfg.run.useParallel = false;
cfg.run.autoStartParallelPool = false;
cfg.system.phyBackend = "waveform";

cfg.outputs.saveCSV = true;
cfg.outputs.saveMAT = true;
cfg.outputs.saveFigures = logical(sixgr.util.structGet(opt, "SaveFigures", true));
cfg.outputs.saveFIG = cfg.outputs.saveFigures;
cfg.outputs.savePNG = true;
cfg.outputs.plotVisible = false;

cfg.channel.model = "TDL-C";
cfg.channel.delayProfile = "TDL-C";
cfg.channel.tdlProfile = "TDL-C";
cfg.channel.awgnOnly = false;
cfg.channel.snr_dB = double(sixgr.util.structGet(opt, "LinkSNR_dB", 30));
cfg.channel.dopplerHz = max(0, double(sixgr.util.structGet(cfg, "channel.dopplerHz", 70)));
cfg.channel.doppler_Hz = cfg.channel.dopplerHz;
cfg.channel.fading.enable = true;
cfg.channel.fading.model = "TDL";
cfg.channel.fading.profile = "TDL-C";
cfg.channel.fading.maxDoppler_Hz = cfg.channel.dopplerHz;

trafficModel = lower(strtrim(char(string(sixgr.util.structGet(opt, "E2ETrafficModel", "traceReplay")))));
if ~strcmp(trafficModel, "tracereplay")
    error("sixgr:truth:ValidationTrafficMode", ...
        "run_truth_validation_profile requires E2ETrafficModel='traceReplay' under the no-proxy truth contract.");
end
cfg.traffic.model = "traceReplay";
cfg.traffic.transport = "UDP";
cfg.traffic.flowDirection = "BIDIR";
cfg.traffic.packetDelayBudget_ms = max(1, double(sixgr.util.structGet(cfg, "traffic.packetDelayBudget_ms", 20)));
cfg.traffic.packetSize_bytes = max(64, round(double(sixgr.util.structGet(cfg, "traffic.packetSize_bytes", 1200))));
cfg.traffic.packetInterval_ms = max(1, double(sixgr.util.structGet(cfg, "traffic.packetInterval_ms", 10)));
cfg.traffic.trace = struct( ...
    "offeredBitsDL", 8 * double(cfg.traffic.packetSize_bytes), ...
    "offeredBitsUL", 8 * double(max(64, round(cfg.traffic.packetSize_bytes / 2))), ...
    "transport", "UDP", ...
    "flowDirection", "BIDIR", ...
    "packetDelayBudget_ms", double(cfg.traffic.packetDelayBudget_ms));

cfg.phy.carrier.NSizeGrid = 48;
cfg = localSetNestedField(cfg, "phy.pdcch.nStartBWP", 0);
cfg = localSetNestedField(cfg, "phy.pdcch.nSizeBWP", 48);
cfg = localSetNestedField(cfg, "phy.pdsch.prbSet", 0:5);
cfg = localSetNestedField(cfg, "phy.pdsch.PRBSet", 0:5);
cfg = localSetNestedField(cfg, "phy.pdsch.symbolAllocation", [0 10]);
cfg = localSetNestedField(cfg, "phy.pdsch.SymbolAllocation", [0 10]);
cfg = localSetNestedField(cfg, "phy.pdsch.modulation", "QPSK");
cfg = localSetNestedField(cfg, "phy.pdsch.Modulation", "QPSK");
cfg = localSetNestedField(cfg, "phy.pdsch.codeRate", 0.30);
cfg = localSetNestedField(cfg, "phy.pusch.prbSet", 0:5);
cfg = localSetNestedField(cfg, "phy.pusch.PRBSet", 0:5);
cfg = localSetNestedField(cfg, "phy.pusch.symbolAllocation", [0 10]);
cfg = localSetNestedField(cfg, "phy.pusch.SymbolAllocation", [0 10]);
cfg = localSetNestedField(cfg, "phy.pusch.modulation", "QPSK");
cfg = localSetNestedField(cfg, "phy.pusch.Modulation", "QPSK");
cfg = localSetNestedField(cfg, "phy.pusch.codeRate", 0.30);
cfg = localSetNestedField(cfg, "phy.pusch.transformPrecoding", true);
cfg = localSetNestedField(cfg, "phy.ul.pusch.TransformPrecoding", true);

cfg.phy.rx.useFastChannelEstMex = false;
cfg.phy.rx.UseFastChannelEstMex = false;

cfg = localSetNestedField(cfg, "phy.ssb.enable", true);
cfg = localSetNestedField(cfg, "phy.ssb.Enable", true);
cfg = localSetNestedField(cfg, "phy.pbch.enable", true);
cfg = localSetNestedField(cfg, "phy.mib.enable", true);
cfg = localSetNestedField(cfg, "phy.sib1.enable", true);
cfg = localSetNestedField(cfg, "phy.pdsch.enable", true);
cfg = localSetNestedField(cfg, "phy.pdsch.Enable", true);
cfg = localSetNestedField(cfg, "phy.pusch.enable", true);
cfg = localSetNestedField(cfg, "phy.pusch.Enable", true);
cfg = localSetNestedField(cfg, "phy.pdcch.enable", true);
cfg = localSetNestedField(cfg, "phy.pdcch.Enable", true);
cfg = localSetNestedField(cfg, "phy.pucch.enable", true);
cfg = localSetNestedField(cfg, "phy.pucch.Enable", true);
cfg = localSetNestedField(cfg, "phy.srs.enable", true);
cfg = localSetNestedField(cfg, "phy.srs.Enable", true);
cfg = localSetNestedField(cfg, "phy.prach.enable", true);
cfg = localSetNestedField(cfg, "phy.prach.Enable", true);
cfg = localSetNestedField(cfg, "phy.prach.configurationIndex", 86);
cfg = localSetNestedField(cfg, "phy.prach.ConfigurationIndex", 86);
cfg = localSetNestedField(cfg, "phy.prach.subcarrierSpacing_kHz", 15);
cfg = localSetNestedField(cfg, "phy.prach.SubcarrierSpacing", 15);
cfg = localSetNestedField(cfg, "phy.prach.preambleFormat", "A1");
cfg = localSetNestedField(cfg, "phy.prach.PreambleFormat", "A1");
cfg = localSetNestedField(cfg, "prach_lls.PRACHFormat", "A1");
cfg = localSetNestedField(cfg, "random_access.prach_format", "A1");
cfg = localSetNestedField(cfg, "phy.csirs.enable", false);
cfg = localSetNestedField(cfg, "phy.csirs.Enable", false);
cfg = localSetNestedField(cfg, "phy.dl.pdcch.Enable", true);
cfg = localSetNestedField(cfg, "phy.ul.pucch.Enable", true);
cfg = localSetNestedField(cfg, "phy.ul.srs.Enable", true);
cfg = localSetNestedField(cfg, "phy.ul.prach.Enable", true);
cfg = localSetNestedField(cfg, "phy.dl.csirs.Enable", false);

cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
end

function s = localSetNestedField(s, dottedPath, value)
parts = split(string(dottedPath), ".");
s = localSetRec(s, parts, value);
end

function s = localSetRec(s, parts, value)
name = char(parts(1));
if numel(parts) == 1
    s.(name) = value;
    return;
end
if ~isfield(s, name) || ~isstruct(s.(name))
    s.(name) = struct();
end
s.(name) = localSetRec(s.(name), parts(2:end), value);
end
