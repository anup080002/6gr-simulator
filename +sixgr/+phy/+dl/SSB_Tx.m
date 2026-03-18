function [waveform, waveInfo, txCfg] = SSB_Tx(cfg, varargin)
%SSB_Tx Generate a downlink waveform containing an SS burst (SSB).
%
%   [waveform, waveInfo, txCfg] = sixgr.phy.dl.SSB_Tx(cfg, ...)
%
% This wrapper uses 5G Toolbox waveform generation objects:
%   - nrDLCarrierConfig
%   - nrSCSCarrierConfig
%   - nrWavegenBWPConfig
%   - nrWavegenSSBurstConfig
%   - nrWaveformGenerator
%
% The function is designed to be robust to common config mistakes. In
% particular, if cfg.phy.carrier.NSizeGrid exceeds the maximum allowed for
% the configured channel bandwidth and subcarrier spacing, nrWaveformGenerator
% throws an error that includes the maximum allowed RB count. This wrapper
% catches that case, clamps NSizeGrid, and retries.
%
% Outputs:
%   waveform : complex time-domain waveform (column vector)
%   waveInfo : struct from nrWaveformGenerator
%   txCfg    : struct with key parameters used in the generation
%
% Notes:
%   - This is intended for link-level initial access tests (SSB/PBCH).
%   - Data channels are disabled by default.

% -------------------- Inputs --------------------

p = inputParser;

addParameter(p, 'NumSubframes', 10);
addParameter(p, 'NCellID', []);
addParameter(p, 'SSBIndex', 0);
addParameter(p, 'SSBBlockPattern', 'Case B');
addParameter(p, 'SubcarrierSpacingCommon_kHz', []);
addParameter(p, 'ChannelBandwidth_MHz', []);
addParameter(p, 'FrequencyRange', 'FR1');
addParameter(p, 'CarrierFrequency_Hz', sixgr.util.structGet(cfg, 'channel.fc_Hz', 3.5e9));
addParameter(p, 'EnablePDSCH', false);
addParameter(p, 'EnableCSIRS', false);

parse(p, varargin{:});
opt = p.Results;

% Carrier parameters from cfg (with optional overrides)
NCellID = sixgr.util.structGet(cfg, 'phy.carrier.NCellID', 1);
SCSCarrier_kHz = sixgr.util.structGet(cfg, 'phy.carrier.SubcarrierSpacing_kHz', 30);
NSizeGrid = sixgr.util.structGet(cfg, 'phy.carrier.NSizeGrid', 52);
NStartGrid = sixgr.util.structGet(cfg, 'phy.carrier.NStartGrid', 0);
ChannelBW_MHz = sixgr.util.structGet(cfg, 'phy.channelBandwidth_MHz', 20);

if ~isempty(opt.NCellID)
    NCellID = double(opt.NCellID);
end

if ~isempty(opt.SubcarrierSpacingCommon_kHz)
    SCSCarrier_kHz = double(opt.SubcarrierSpacingCommon_kHz);
end

if ~isempty(opt.ChannelBandwidth_MHz)
    ChannelBW_MHz = double(opt.ChannelBandwidth_MHz);
end

% -------------------- Build waveform generator config --------------------

cfgDL = nrDLCarrierConfig;
cfgDL.FrequencyRange = string(opt.FrequencyRange);
cfgDL.ChannelBandwidth = double(ChannelBW_MHz); % MHz
cfgDL.NCellID = double(NCellID);
cfgDL.CarrierFrequency = double(opt.CarrierFrequency_Hz);

% SCS carrier (grid)
scs = nrSCSCarrierConfig;
scs.SubcarrierSpacing = double(SCSCarrier_kHz);
scs.NSizeGrid = double(NSizeGrid);
scs.NStartGrid = double(NStartGrid);
cfgDL.SCSCarriers = {scs};

% Bandwidth part (BWP) covering the grid
bwp = nrWavegenBWPConfig;
bwp.SubcarrierSpacing = scs.SubcarrierSpacing;
bwp.CyclicPrefix = sixgr.util.structGet(cfg, 'phy.carrier.CyclicPrefix', 'normal');
bwp.NStartBWP = double(NStartGrid);
bwp.NSizeBWP = double(NSizeGrid);

% Use BWP 1 by default
cfgDL.BandwidthParts = {bwp};

% SS burst configuration
ssb = nrWavegenSSBurstConfig;
ssb.Enable = true;
ssb.BlockPattern = string(opt.SSBBlockPattern);
ssb.Period = 20; % ms
ssb.Power = 0;

% Transmit only one SSB by default (user can override later)
% NOTE: nrWavegenSSBurstConfig.TransmittedBlocks expects a NUMERIC binary row
% vector (logical is rejected in some releases). Use uint8 0/1.
ssb.TransmittedBlocks = zeros(1, 8, 'uint8');
idx = max(0, min(7, round(opt.SSBIndex)));
ssb.TransmittedBlocks(idx+1) = uint8(1);

cfgDL.SSBurst = ssb;

% Disable other channels unless explicitly enabled
cfgDL.PDSCH{1}.Enable = logical(opt.EnablePDSCH);
if isprop(cfgDL, 'CSIRS')
    cfgDL.CSIRS{1}.Enable = logical(opt.EnableCSIRS);
end

% Waveform length
cfgDL.NumSubframes = double(opt.NumSubframes);

% -------------------- Generate waveform (with clamp/retry) --------------------

[waveform, waveInfo, NSizeGridUsed] = localWavegenWithClamp(cfgDL, scs, bwp, NSizeGrid);

% -------------------- Outputs --------------------

txCfg = struct;
txCfg.NCellID = double(NCellID);
txCfg.SubcarrierSpacing_kHz = double(SCSCarrier_kHz);
txCfg.NSizeGrid = double(NSizeGridUsed);
txCfg.NStartGrid = double(NStartGrid);
txCfg.ChannelBandwidth_MHz = double(ChannelBW_MHz);
txCfg.FrequencyRange = char(cfgDL.FrequencyRange);
txCfg.CarrierFrequency_Hz = double(cfgDL.CarrierFrequency);

txCfg.SSB = struct;
txCfg.SSB.BlockPattern = char(ssb.BlockPattern);
txCfg.SSB.SSBIndex = idx;
txCfg.SSB.Period_ms = double(ssb.Period);

% Sample rate: nrWaveformGenerator returns it in waveInfo
sr = [];
try
    if isfield(waveInfo, 'ResourceGrids') && ~isempty(waveInfo.ResourceGrids)
        rg = waveInfo.ResourceGrids(1);
        if isfield(rg, 'Info') && isfield(rg.Info, 'SampleRate')
            sr = rg.Info.SampleRate;
        end
        % Some releases may also expose SampleRate directly on ResourceGrids
        if isempty(sr) && isfield(rg, 'SampleRate')
            sr = rg.SampleRate;
        end
    end
end
if isempty(sr) && isfield(waveInfo, 'SampleRate')
    sr = waveInfo.SampleRate;
end

txCfg.SampleRate_Hz = sr;


end

% ======================================================================
% Local helpers
% ======================================================================

function [waveform, waveInfo, nGridOut] = localWavegenWithClamp(cfgDL, scs, bwp, nGridIn)

nGridOut = double(nGridIn);
persistent clampWarned
if isempty(clampWarned)
    clampWarned = false;
end

maxIter = 3;
for it = 1:maxIter
    try
        % Ensure objects reflect the current grid size
        scs.NSizeGrid = double(nGridOut);
        bwp.NSizeBWP = double(nGridOut);
        cfgDL.SCSCarriers = {scs};
        cfgDL.BandwidthParts = {bwp};

        [waveform, waveInfo] = nrWaveformGenerator(cfgDL);
        return;

    catch ME
        maxRB = localParseMaxRB(ME.message);
        if ~isempty(maxRB) && isfinite(maxRB) && maxRB > 0 && nGridOut > maxRB
            if ~clampWarned
                warning('sixgr:phy:SSB_Tx:ClampNSizeGrid', ...
                    'Clamping NSizeGrid from %d to %d to satisfy BW/SCS limits in nrWaveformGenerator.', ...
                    nGridOut, maxRB);
                clampWarned = true;
            end
            nGridOut = double(maxRB);
            continue;
        end
        rethrow(ME);
    end
end

error('sixgr:phy:SSB_Tx:WavegenFailed', 'nrWaveformGenerator failed after %d attempts.', maxIter);

end

function maxRB = localParseMaxRB(msg)
% Extract "maximum RB number is <N>" from nrWaveformGenerator validation errors.

maxRB = [];
if isempty(msg)
    return;
end

tokens = regexp(char(msg), 'maximum\s+RB\s+number\s+is\s+(\d+)', 'tokens', 'once');
if ~isempty(tokens)
    maxRB = str2double(tokens{1});
end

end
