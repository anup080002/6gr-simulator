function ok = testLinkPrimaryExportIntegrity()
%TESTLINKPRIMARYEXPORTINTEGRITY Keep primary link summaries aligned with primary trials.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "TDL-C";
cfg.channel.tdlProfile = "TDL-C";

raw = struct();
raw.DL = localTrialTable(["PASS"; "FAIL"; "CRASH"], "TDL-C", ["", "", ""]);
raw.UL = localTrialTable(["PASS"; "FAIL"], "TDL-C", ["", ""]);
raw.SRS = localTrialTable("PASS", "TDL-C", "");

kpi = table( ...
    ["DL_PDSCH_Throughput"; "UL_PUSCH_Throughput"; "UL_SRS_ChannelEst"], ...
    [true; true; true], ...
    [false; false; false], ...
    [0.1; 0.2; NaN], ...
    [0.2; 0.5; NaN], ...
    [100; 90; NaN], ...
    strings(3,1), ...
    'VariableNames', {'Case','Ok','Skipped','BER','BLER','Throughput_Mbps','Notes'});

[kpiOut, meta] = sixgr.link.enforcePrimaryLinkExportIntegrity(cfg, kpi, raw);
assert(all(double(kpiOut.TrialCount) == [3; 2; 1]), "Primary summary trial counts were not derived from raw tables.");
assert(all(double(kpiOut.PassCount) == [1; 1; 1]), "Primary summary pass counts were not derived from raw tables.");
assert(all(double(kpiOut.FailCount) == [1; 1; 0]), "Primary summary fail counts were not derived from raw tables.");
assert(all(double(kpiOut.CrashCount) == [1; 0; 0]), "Primary summary crash counts were not derived from raw tables.");
assert(all(string(kpiOut.RequestedChannelModel) == "TDL-C"), "Requested channel model was not propagated into the primary summary.");
assert(all(string(kpiOut.ObservedChannelModel) == "TDL-C"), "Observed channel model was not derived from the primary raw tables.");
assert(meta.DL.rows == 3 && meta.UL.rows == 2 && meta.SRS.rows == 1, "Primary raw trial metadata was not captured.");

badRaw = raw;
badRaw.DL.Notes(1) = "fallback_awgn_profile|rescue";
threw = false;
try
    sixgr.link.enforcePrimaryLinkExportIntegrity(cfg, kpi, badRaw); %#ok<NASGU>
catch ME
    threw = contains(string(ME.identifier), "PrimaryTrialContainsFallbackNote");
end
assert(threw, "Primary raw trials with fallback notes must be rejected.");

badRaw = raw;
badRaw.DL.ChannelModel(1) = "AWGN";
threw = false;
try
    sixgr.link.enforcePrimaryLinkExportIntegrity(cfg, kpi, badRaw); %#ok<NASGU>
catch ME
    threw = contains(string(ME.identifier), "PrimaryTrialChannelModelMismatch");
end
assert(threw, "Primary raw trials with channel-model drift must be rejected.");

badKpi = kpiOut;
badKpi.PassCount(1) = 7;
threw = false;
try
    sixgr.link.enforcePrimaryLinkExportIntegrity(cfg, badKpi, raw); %#ok<NASGU>
catch ME
    threw = contains(string(ME.identifier), "PrimarySummaryCountMismatch");
end
assert(threw, "Primary summary counts must be checked against raw primary trials.");

badKpi = kpiOut;
badKpi.Skipped(1) = true;
threw = false;
try
    sixgr.link.enforcePrimaryLinkExportIntegrity(cfg, badKpi, raw); %#ok<NASGU>
catch ME
    threw = contains(string(ME.identifier), "PrimarySummarySkipped");
end
assert(threw, "Primary summaries with skipped rows must be rejected.");

badKpi = kpiOut;
badKpi.Notes(2) = "proxy_packet_model";
threw = false;
try
    sixgr.link.enforcePrimaryLinkExportIntegrity(cfg, badKpi, raw); %#ok<NASGU>
catch ME
    threw = contains(string(ME.identifier), "PrimarySummaryContainsNonPrimaryNote");
end
assert(threw, "Primary summaries with proxy notes must be rejected.");

ok = true;
end

function T = localTrialTable(statuses, channelModel, notes)
statuses = string(statuses(:));
channelModel = repmat(string(channelModel), numel(statuses), 1);
notes = string(notes(:));
if numel(notes) == 1 && numel(statuses) > 1
    notes = repmat(notes, numel(statuses), 1);
end

n = numel(statuses);
T = table( ...
    repmat("DL", n, 1), ...
    10 * ones(n,1), ...
    (1:n).', ...
    (1:n).', ...
    (1:n).', ...
    zeros(n,1), ...
    10 * ones(n,1), ...
    ones(n,1), ...
    100 * ones(n,1), ...
    channelModel, ...
    zeros(n,1), ...
    double(statuses == "PASS"), ...
    NaN(n,1), ...
    NaN(n,1), ...
    NaN(n,1), ...
    NaN(n,1), ...
    zeros(n,1), ...
    100 * ones(n,1), ...
    statuses, ...
    statuses == "CRASH", ...
    notes, ...
    'VariableNames', {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','TBSize_bits', ...
    'ChannelModel','DopplerHz','CRCPass','DecoderIterations','EVM_rms','NMSE_dB','DetectionMetric', ...
    'BitErrors','BitsCompared','Status','Crash','Notes'});
end
