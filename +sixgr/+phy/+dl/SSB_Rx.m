function [rxSSBGrid, sync] = SSB_Rx(rxWaveform, cfg, varargin)
%sixgr.phy.dl.SSB_Rx  Receiver-side SS/PBCH block extraction (grid)
%
%   [rxSSBGrid, sync] = sixgr.phy.dl.SSB_Rx(rxWaveform, cfg, ...)
%
%   This is a simulator-oriented wrapper that follows the MathWorks example
%   flow (PSS-based coarse sync) but is tolerant to single-antenna grid
%   dimensionality (240x4 vs 240x4xNr).
%
%   Outputs
%     rxSSBGrid : 240-by-4-by-Nr resource grid containing the SS/PBCH block
%     sync      : struct with timing/frequency estimates and IDs

% Parse inputs
p = inputParser;
p.addParameter('SampleRate_Hz', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
p.parse(varargin{:});
fs = p.Results.SampleRate_Hz;
if isempty(fs)
    fs = sixgr.util.structGet(cfg,'phy.sampleRate_Hz',[]);
end
if isempty(fs)
    error('SSB_Rx:SampleRateMissing','SampleRate_Hz must be provided (or cfg.phy.sampleRate_Hz set).');
end

% Ensure waveform is 2-D (Nsamp-by-Nr)
if isvector(rxWaveform)
    rxWaveform = rxWaveform(:);
end

% Burst parameters
blockPattern = char(sixgr.util.structGet(cfg,'phy.ssb.blockPattern','Case B'));
Lmax = double(sixgr.util.structGet(cfg,'phy.ssb.Lmax',8));

% Coarse frequency correction + NID2 detection
try
    [rxF, fOffHz, NID2, finfo] = sixgr.phy.sync.freqOffsetCorrect(rxWaveform, blockPattern, fs, ...
        'SearchBW_Hz', sixgr.util.structGet(cfg,'phy.sync.freqSearchBW_Hz',[]));
catch
    % For pure simulation (no CFO), fall back gracefully
    rxF = rxWaveform;
    fOffHz = 0;
    NID2 = mod(double(sixgr.util.structGet(cfg,'phy.NCellID',1)),3);
    finfo = struct('UsedFallback',true);
end
NID2 = mod(double(NID2),3);

% Timing estimation (PSS-based)
try
    [tOff, tinfo] = sixgr.phy.sync.timingEstimate(rxF, NID2, blockPattern, fs);
catch
    tOff = 0;
    tinfo = struct('UsedFallback',true);
end

% Synchronize waveform
startIdx = 1 + max(0, round(tOff));
if startIdx > size(rxF,1)
    startIdx = 1;
end
rxSync = rxF(startIdx:end, :);

% OFDM demodulation at SSB numerology (nrbSSB=20)
nrbSSB = 20;
scsSSB = localSSBSubcarrierSpacing_kHz(blockPattern);
nSlot = 0;

% Use the numeric-argument syntax from MathWorks examples for maximum
% compatibility across 5G Toolbox releases.
rxGrid = nrOFDMDemodulate(rxSync, nrbSSB, scsSSB, nSlot, 'SampleRate', fs);

% Normalize dimensionality: force 3-D grid (Nsc-by-Nsym-by-Nr)
if ndims(rxGrid) == 2
    rxGrid = reshape(rxGrid, size(rxGrid,1), size(rxGrid,2), 1);
end


% Ensure we have at least 5 OFDM symbols available for extraction of 2:5
if size(rxGrid,2) < 5
    rxGrid(:, end+1:5, :) = 0;
end

% Extract SS/PBCH block (symbols 2..5)
rxSSBGrid = rxGrid(:, 2:5, :);

% Ensure 240-by-4-by-Nr
if ndims(rxSSBGrid) == 2
    rxSSBGrid = reshape(rxSSBGrid, size(rxSSBGrid,1), size(rxSSBGrid,2), 1);
end

sync = struct();
sync.SampleRate_Hz = fs;
sync.BlockPattern = blockPattern;
sync.Lmax = Lmax;
sync.NID2 = NID2;
sync.FreqOffset_Hz = fOffHz;
sync.TimingOffset = tOff;
sync.SCS_SSB_kHz = scsSSB;
sync.nRBSSB = nrbSSB;

% In simulation we usually know the cell ID. Populate it to make downstream
% blocks deterministic.
sync.NCellID = double(sixgr.util.structGet(cfg,'phy.NCellID', (3*0)+NID2));

% Attach debug info
sync.FreqInfo = finfo;
sync.TimingInfo = tinfo;

end

function scs = localSSBSubcarrierSpacing_kHz(blockPattern)
%localSSBSubcarrierSpacing_kHz  Map SS burst pattern to SCS (kHz)
bp = upper(strtrim(char(blockPattern)));
switch bp
    case {'CASE A','A'}
        scs = 15;
    case {'CASE B','B'}
        scs = 30;
    case {'CASE C','C'}
        scs = 30;
    case {'CASE D','D'}
        scs = 120;
    case {'CASE E','E'}
        scs = 240;
    otherwise
        % Conservative default for FR1
        scs = 30;
end
end
