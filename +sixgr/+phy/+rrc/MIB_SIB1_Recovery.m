function out = MIB_SIB1_Recovery(rxWaveform, cfg, varargin)
%MIB_SIB1_Recovery Initial access recovery: SSB sync + PBCH/MIB/SIB1.
%
%   out = sixgr.phy.rrc.MIB_SIB1_Recovery(rxWaveform, cfg)
%
%   This is a high-level convenience API that ties together:
%     * sixgr.phy.dl.SSB_Rx
%     * sixgr.phy.dl.PBCH_Recovery
%
%   When cfg.phy.sib1.enable is true this wrapper requires the waveform to
%   contain the strict AUD-015 path: Type0-PDCCH CSS SI-RNTI DCI format 1_0,
%   PDSCH/DL-SCH SIB1 transport block, and repo-owned constrained
%   TS 38.331 SIB1 ASN.1 profile decode. It never returns SIB1.Ok=true from
%   cfg payload structs, JSON, defaults, or transmitter-side oracle fields.
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
%     .SIB1         : strict waveform SIB1 result with .Ok/.StrictOk
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

% --- Optional strict SIB1 recovery ---
wantSIB1 = false;
try
    wantSIB1 = logical(sixgr.util.structGet(cfg, 'phy.sib1.enable', false));
catch
    wantSIB1 = false;
end

sib1 = struct("Ok", false, "StrictOk", false, "Source", "disabled", ...
    "Payload", struct(), "Msg", "SIB1 recovery disabled by cfg.phy.sib1.enable=false.");

if wantSIB1
    try
        rec = sixgr.phy.broadcast.recoverSIB1FromWaveform(rxWaveform, cfg);
        sib1 = rec;
        sib1.Ok = logical(rec.StrictOk);
        sib1.Source = "strict_waveform_si_rnti_pdcch_pdsch_dlsch_asn1";
        sib1.Msg = string(rec.Status);
    catch ex
        sib1.Ok = false;
        sib1.StrictOk = false;
        sib1.Source = "strict_waveform_recovery_error";
        sib1.Msg = sprintf('SIB1 waveform recovery failed: %s', ex.message);
    end
end

out.SIB1 = sib1;

% Attach detailed info
out.Info = struct();
out.Info.SSB = ssbInfo;
out.Info.PBCH = pbchInfo;

end

% -------------------------------------------------------------------------
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
