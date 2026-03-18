function out = MIB_SIB1_Recovery(rxWaveform, cfg, varargin)
%MIB_SIB1_Recovery Initial access recovery: SSB sync + PBCH/MIB (and optional SIB1).
%
%   out = sixgr.phy.rrc.MIB_SIB1_Recovery(rxWaveform, cfg)
%
%   This is a high-level convenience API that ties together:
%     * sixgr.phy.dl.SSB_Rx
%     * sixgr.phy.dl.PBCH_Recovery
%
%   SIB1 recovery is optional and will be attempted only when
%   cfg.phy.sib1.enable is true. This implementation performs:
%     1) CORESET0/SearchSpace0 derivation (when supported by release APIs)
%     2) SIB1 payload recovery from simulator broadcast sources:
%          - cfg.phy.sib1.payloadStruct / decodedStruct
%          - cfg.phy.sib1.payloadJSON / payloadBytes
%          - cfg.rrc.sib1
%          - sixgr.l3.rrc.SystemInformation defaults
%
%   Note: waveform-level SIB1 PDSCH decoding is not performed here unless
%   explicit SIB1 payload context is provided through configuration.
%
%   Name-value options:
%     'SampleRate_Hz'  : Receiver sample rate (Hz). If empty, uses cfg.
%     'BlockPattern'   : Override SSB block pattern (e.g., 'Case B').
%     'Lmax'           : Override Lmax.
%     'SearchBW_Hz'    : Frequency search bandwidth.
%
%   Output 'out' contains:
%     .Ok           : true when MIB decode CRC passes (or CRC unknown)
%     .Sync         : sync struct (cell IDs, offsets)
%     .PBCH         : PBCH output struct
%     .MIB          : parsed MIB (best-effort)
%     .SIB1         : struct with .Ok and .Msg
%
%   See also: sixgr.phy.dl.SSB_Tx, sixgr.phy.dl.SSB_Rx, sixgr.phy.dl.PBCH_Recovery

p = inputParser;
p.addParameter('SampleRate_Hz', [], @(x) isempty(x) || (isscalar(x) && x > 0));
p.addParameter('BlockPattern', '', @(s) (ischar(s) || isstring(s)));
p.addParameter('Lmax', [], @(x) isempty(x) || (isscalar(x) && x >= 4));
p.addParameter('SearchBW_Hz', [], @(x) isempty(x) || (isscalar(x) && x > 0));
p.parse(varargin{:});
opt = p.Results;

% Run SSB synchronization and extraction.
cfgRx = cfg;
if strlength(string(opt.BlockPattern)) > 0
    cfgRx.phy.ssb.blockPattern = char(string(opt.BlockPattern));
end
if ~isempty(opt.Lmax)
    cfgRx.phy.ssb.Lmax = double(opt.Lmax);
end
if ~isempty(opt.SearchBW_Hz)
    cfgRx.phy.sync.freqSearchBW_Hz = double(opt.SearchBW_Hz);
end

% Keep compatibility with SSB_Rx variants that return either 2 or 3 outputs.
try
    [rxSSBGrid, sync, ssbInfo] = sixgr.phy.dl.SSB_Rx(rxWaveform, cfgRx, ...
        'SampleRate_Hz', opt.SampleRate_Hz);
catch ME
    if contains(string(ME.message), "Too many output arguments")
        [rxSSBGrid, sync] = sixgr.phy.dl.SSB_Rx(rxWaveform, cfgRx, ...
            'SampleRate_Hz', opt.SampleRate_Hz);
        ssbInfo = struct();
    else
        rethrow(ME);
    end
end

% PBCH + MIB
[pbch, pbchInfo] = sixgr.phy.dl.PBCH_Recovery(rxSSBGrid, sync, cfg);

out = struct();
out.Ok = logical(pbch.Ok);
out.Sync = sync;
out.SSB = ssbInfo;
out.PBCH = pbch;
if isstruct(pbch) && isfield(pbch, "MIB")
    out.MIB = pbch.MIB;
else
    out.MIB = localBuildMIBFromPBCH(pbch, cfg, sync);
end

% --- Optional SIB1 recovery ---
wantSIB1 = false;
try
    wantSIB1 = logical(sixgr.util.structGet(cfg, 'phy.sib1.enable', false));
catch
    wantSIB1 = false;
end

sib1 = struct();
sib1.Ok = false;
sib1.Source = "disabled";
sib1.Payload = struct();
sib1.Msg = 'SIB1 recovery disabled by cfg.phy.sib1.enable=false.';

if wantSIB1
    try
        sib1 = localDeriveCORESET0Params(sync, cfg);
        [sib1Payload, meta] = localRecoverSIB1Payload(cfg, sync, pbch);
        sib1.Payload = sib1Payload;
        sib1.Source = string(meta.Source);
        if logical(meta.Ok)
            sib1.Ok = true;
            sib1.Msg = "Recovered SIB1 payload (" + string(meta.Source) + ").";
            sib1.PayloadTimestamp = char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
        else
            sib1.Ok = false;
            sib1.Msg = string(meta.Msg);
        end
    catch ex
        sib1.Ok = false;
        sib1.Source = "recovery_error";
        sib1.Msg = sprintf('SIB1 params derive failed: %s', ex.message);
    end
end

out.SIB1 = sib1;

% Attach detailed info
out.Info = struct();
out.Info.SSB = ssbInfo;
out.Info.PBCH = pbchInfo;

end

% -------------------------------------------------------------------------
function sib1 = localDeriveCORESET0Params(sync, cfg)
% Try to derive CORESET0/SearchSpace0 using 5G Toolbox helpers.

sib1 = struct();
sib1.Ok = false;
sib1.Source = "params_only";
sib1.Payload = struct();

NCellID = sync.NCellID;
scsCommon_kHz = sixgr.util.structGet(cfg, 'phy.carrier.SubcarrierSpacing_kHz', ...
    sixgr.util.structGet(cfg, 'phy.carrier.SubcarrierSpacing', 30));

% Derive a minimal carrier config for common numerology.
carrier = nrCarrierConfig;
carrier.NCellID = NCellID;
carrier.SubcarrierSpacing = scsCommon_kHz;
carrier.NStartGrid = 0;
carrier.NSizeGrid = sixgr.util.structGet(cfg, 'phy.carrier.NSizeGrid', 64);
carrier.CyclicPrefix = 'normal';

% Attempt CORESET0 resources (if helper exists in this release)
coreset0 = [];
ss0 = [];

if exist('nrCORESET0Resources', 'file') == 2
    % Parameters for CORESET0 depend on SCS... use defaults for now.
    try
        [coreset0, ss0] = nrCORESET0Resources(carrier);
    catch
        % Some releases require additional inputs (e.g., pdcchConfigSIB1).
        coreset0 = [];
        ss0 = [];
    end
end

sib1.NCellID = NCellID;
sib1.SCSCommon_kHz = scsCommon_kHz;
sib1.Carrier = carrier;
sib1.CORESET0 = coreset0;
sib1.SearchSpace0 = ss0;

% Parameter derivation is considered successful even if helper APIs are
% unavailable; Payload recovery still decides final SIB1.Ok.
sib1.Ok = true;
sib1.Msg = 'Derived SIB1 scheduling parameters (best effort).';

end

function [sib1Payload, meta] = localRecoverSIB1Payload(cfg, sync, pbch)
sib1Payload = struct();
meta = struct("Ok", false, "Source", "none", "Msg", "No SIB1 payload source found.");

% Priority 1: explicit decoded/payload struct.
sibIn = sixgr.util.structGet(cfg, "phy.sib1.decodedStruct", struct());
if isempty(fieldnames(sibIn))
    sibIn = sixgr.util.structGet(cfg, "phy.sib1.payloadStruct", struct());
end
if ~isempty(fieldnames(sibIn))
    sib1Payload = localNormalizeSIB1Struct(sibIn, cfg, sync, pbch);
    meta.Ok = true;
    meta.Source = "cfg.phy.sib1.payloadStruct";
    meta.Msg = "";
    return;
end

% Priority 2: JSON string.
payloadJSON = sixgr.util.structGet(cfg, "phy.sib1.payloadJSON", "");
if strlength(string(payloadJSON)) > 0
    s = localDecodeJSONString(char(string(payloadJSON)));
    if ~isempty(fieldnames(s))
        sib1Payload = localNormalizeSIB1Struct(s, cfg, sync, pbch);
        meta.Ok = true;
        meta.Source = "cfg.phy.sib1.payloadJSON";
        meta.Msg = "";
        return;
    end
end

% Priority 3: encoded bytes.
payloadBytes = sixgr.util.structGet(cfg, "phy.sib1.payloadBytes", []);
if ~isempty(payloadBytes)
    s = localDecodeJSONBytes(payloadBytes);
    if ~isempty(fieldnames(s))
        sib1Payload = localNormalizeSIB1Struct(s, cfg, sync, pbch);
        meta.Ok = true;
        meta.Source = "cfg.phy.sib1.payloadBytes";
        meta.Msg = "";
        return;
    end
end

% Priority 4: direct rrc.sib1 block.
rrcSib1 = sixgr.util.structGet(cfg, "rrc.sib1", struct());
if isstruct(rrcSib1) && ~isempty(fieldnames(rrcSib1))
    sib1Payload = localNormalizeSIB1Struct(rrcSib1, cfg, sync, pbch);
    meta.Ok = true;
    meta.Source = "cfg.rrc.sib1";
    meta.Msg = "";
    return;
end

% Priority 5: SystemInformation default content.
si = sixgr.l3.rrc.SystemInformation(cfg, "CellID", double(sync.NCellID));
s = si.getSIB1();
if isstruct(s) && ~isempty(fieldnames(s))
    sib1Payload = localNormalizeSIB1Struct(s, cfg, sync, pbch);
    meta.Ok = true;
    meta.Source = "system_information_default";
    meta.Msg = "";
    return;
end

meta.Msg = "No SIB1 payload source found (cfg payload fields and rrc.sib1 empty).";
end

function s = localDecodeJSONString(js)
s = struct();
if isempty(js)
    return;
end
try
    tmp = jsondecode(js);
    if isstruct(tmp)
        s = tmp;
    end
catch
end
end

function s = localDecodeJSONBytes(bytes)
s = struct();
if isempty(bytes)
    return;
end
try
    js = native2unicode(uint8(bytes(:)).', "UTF-8");
    s = localDecodeJSONString(js);
catch
end
end

function sib1 = localNormalizeSIB1Struct(sibIn, cfg, sync, pbch)
sib1 = sibIn;
if isfield(sib1, "sib1") && isstruct(sib1.sib1) && numel(fieldnames(sib1)) == 1
    sib1 = sib1.sib1;
end
if ~isfield(sib1, "cellID")
    sib1.cellID = double(sync.NCellID);
end
if ~isfield(sib1, "plmn")
    sib1.plmn = sixgr.util.structGet(cfg, "rrc.sib1.plmn", "00101");
end
if ~isfield(sib1, "tac")
    sib1.tac = double(sixgr.util.structGet(cfg, "rrc.sib1.tac", 1));
end
if ~isfield(sib1, "prach") || ~isstruct(sib1.prach)
    sib1.prach = struct();
end
if ~isfield(sib1.prach, "configurationIndex")
    sib1.prach.configurationIndex = double(sixgr.util.structGet(cfg, "phy.prach.configurationIndex", 16));
end
if ~isfield(sib1.prach, "subcarrierSpacing_kHz")
    sib1.prach.subcarrierSpacing_kHz = double(sixgr.util.structGet(cfg, "phy.prach.subcarrierSpacing_kHz", 1.25));
end
if ~isfield(sib1.prach, "preambleFormat")
    sib1.prach.preambleFormat = char(string(sixgr.util.structGet(cfg, "phy.prach.preambleFormat", "A1")));
end
if ~isfield(sib1.prach, "nPreambles")
    sib1.prach.nPreambles = double(sixgr.util.structGet(cfg, "phy.prach.nPreambles", 64));
end
if ~isfield(sib1, "mib")
    mib = struct();
    mib.NCellID = double(sync.NCellID);
    mib.SSBIndex = double(sixgr.util.structGet(pbch, "SSBIndex", 0));
    mib.HalfFrame = double(sixgr.util.structGet(pbch, "HalfFrame", 0));
    sib1.mib = mib;
end
if ~isfield(sib1, "timestamp")
    sib1.timestamp = char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
end

end

function mib = localBuildMIBFromPBCH(pbch, cfg, sync)
mib = struct();
mib.CellID = double(sixgr.util.structGet(pbch, "NCellID", sixgr.util.structGet(sync, "NCellID", ...
    sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1))));
mib.SSBIndex = double(sixgr.util.structGet(pbch, "SSBIndex", 0));
mib.HalfFrame = double(sixgr.util.structGet(pbch, "HalfFrame", 0));
mib.SFN4LSB = sixgr.util.structGet(pbch, "SFN4LSB", []);
mib.SubcarrierSpacingCommon_kHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mib.DMRS_TypeA_Position = double(sixgr.util.structGet(cfg, "phy.mib.dmrsTypeAPosition", 2));
mib.Timestamp = char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
end
