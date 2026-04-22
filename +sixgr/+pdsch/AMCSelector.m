function amc = AMCSelector(cfg, varargin)
%AMCSelector Resolve the active MCS and modulation choice for the study.
%
% The truth path keeps waveform decoding as the KPI source. This selector is
% only the scheduling policy that decides which MCS to try.

opts = struct("EstimatedSNR_dB", NaN, "PreviousBLER", NaN);
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

if strcmpi(cfg.MCSMode, "fixed")
    idx = double(cfg.FixedMCS);
    policy = "fixed_configured_truth_schedule";
else
    idx = localSNRToMCS(double(opts.EstimatedSNR_dB));
    policy = "study_amc_from_estimated_snr_not_from_truth_kpi";
end

tableToken = localResolveMCSTable(cfg);
profile = sixgr.link.resolveMCSProfile(tableToken, idx);
if ~logical(profile.Valid)
    error("sixgr:pdsch:AMCSelector:BadMCS", ...
        "Unable to resolve MCS index %d against table '%s'.", round(idx), tableToken);
end

amc = struct();
amc.MCSIndex = double(idx);
amc.MCSTable = char(tableToken);
amc.Modulation = char(profile.Modulation);
amc.TargetCodeRate = double(profile.TargetCodeRate);
amc.SpectralEfficiency = double(profile.SpectralEfficiency);
amc.Policy = char(policy);
end

function idx = localSNRToMCS(snr_dB)
if ~isfinite(snr_dB)
    idx = 4;
elseif snr_dB < 0
    idx = 0;
elseif snr_dB < 2
    idx = 2;
elseif snr_dB < 5
    idx = 4;
elseif snr_dB < 8
    idx = 9;
elseif snr_dB < 12
    idx = 14;
elseif snr_dB < 18
    idx = 18;
else
    idx = 22;
end
end

function tableToken = localResolveMCSTable(cfg)
if any(strcmpi(cfg.ModulationPerCodeword{1}, {"256QAM"}))
    tableToken = "qam256_table2";
else
    tableToken = "qam64_table1";
end
end
