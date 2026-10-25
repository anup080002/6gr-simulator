function tx = generateSSB_MIB_SIB1_Waveform(cfg, varargin)
%GENERATESSB_MIB_SIB1_WAVEFORM Generate actual configured broadcast content.
% Content selects a production composition boundary, not a feature enable
% override. SSB_MIB leaves SI to its independent cell scheduler; it does not
% encode SI and then erase it. The default preserves the legacy composite.
p = inputParser;
p.addParameter("SNRdB", Inf, @(x) isnumeric(x) && isscalar(x));
p.addParameter("Seed", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("Content", "SSB_MIB_SIB1");
p.parse(varargin{:});
rawContent=p.Results.Content;
assert(((ischar(rawContent) && isrow(rawContent)) || ...
    (isstring(rawContent) && isscalar(rawContent))) && ...
    any(string(rawContent)==["SSB_MIB","SSB_MIB_SIB1"]), ...
    'sixgr:phy:broadcast:InvalidBroadcastContent', ...
    'Content must be SSB_MIB or SSB_MIB_SIB1.');
content=string(rawContent);
channel="SSB_SIB1";
if content=="SSB_MIB", channel="SSB_MIB"; end
sixgr.runtime.RuntimeCallLedger.record( ...
    "sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform", channel, "DL", ...
    struct("Stage","TX","Content",content));
if nargin < 1 || isempty(cfg)
    cfg = sixgr.config.defaultConfig();
end
if content=="SSB_MIB_SIB1"
    [siSupported, siReason] = sixgr.phy.broadcast.siRNTIWaveformSupported();
    if ~siSupported
        error("sixgr:phy:broadcast:SIRNTIUnsupported", ...
            "Strict SIB1 waveform generation requires SI-RNTI 65535 support: %s", siReason);
    end
end
if ~isempty(p.Results.Seed)
    rng(round(double(p.Results.Seed)), "twister");
end
cfg=localNormalizeBroadcastCfg(cfg);
[cfg,powerContract]=sixgr.rf.resolveSSBPowerContract(cfg);
if content=="SSB_MIB"
    tx=localSSBOnly(cfg,powerContract,p.Results.SNRdB);
    return;
end
indices=sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(cfg);
% The emitted cell waveform is independent of the receiving UE's chosen
% candidate. Generate the SSB burst once and each configured SI occasion
% once. Receiver search hypotheses never decide which samples are emitted.
cfg.phy.ssb.runtimeSSBIndex=indices(1);
[ssbWaveform,ssbWaveInfo,ssbInfo]=sixgr.phy.dl.SSB_Tx(cfg, ...
    'NumSubframes',localSSBObservationSubframes(cfg),'SSBIndex',indices(1));
parts=cell(1,numel(indices));
for ordinal=1:numel(indices)
    occasionCfg=cfg;
    occasionCfg.phy.ssb.runtimeSSBIndex=indices(ordinal);
    occasionCfg.phy.sib1.transmissionScope="selected_ssb_occasion";
    occasionInfo=ssbInfo;
    occasionInfo.SSBTiming=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig( ...
        occasionCfg,'SSBIndex',indices(ordinal));
    part=sixgr.phy.broadcast.generateSIB1Transmission(occasionCfg,occasionInfo);
    originCarrier=sixgr.phy.grid.makeCarrier(cfg);
    originSlot=double(cfg.phy.carrier.NFrame)*double(originCarrier.SlotsPerFrame);
    originSample=localAbsoluteSlotStartSample(originSlot,originCarrier,part.SampleRateHz);
    localAssertNoSSBSIResourceCollision(ssbWaveInfo,occasionInfo,part.SIB1Grid, ...
        part.SIB1AbsoluteSlot-originSlot,part.Carrier);
    part.SIB1WaveformStartSample=part.SIB1WaveformAbsoluteStartSample-originSample;
    assert(part.SIB1WaveformStartSample>=0,'sixgr:phy:broadcast:SIB1BeforeBroadcastOrigin', ...
        'The selected SI occasion must not precede its generated broadcast frame.');
    % These are composite-owner fields, never claims made by SI-only TX.
    part.BroadcastStartAbsoluteSlot=originSlot;
    part.BroadcastStartSample=originSample;
    part.SSBWaveform=ssbWaveform;
    part.SSBWaveInfo=ssbWaveInfo;
    part.SSBBurstPlan=sixgr.util.structGet(occasionInfo,"SSBBurstPlan",struct());
    part.SSBComposite=sixgr.util.structGet(ssbWaveInfo,"SSBComposite",struct());
    parts{ordinal}=part;
    for prior=1:ordinal-1
        if parts{prior}.SIB1AbsoluteSlot==parts{ordinal}.SIB1AbsoluteSlot
            overlap=any(parts{prior}.SIB1Grid~=0,3) & any(parts{ordinal}.SIB1Grid~=0,3);
            assert(~any(overlap,'all'),'sixgr:phy:broadcast:SIB1BeamResourceCollision', ...
                'Configured SI beam occasions must not superpose independent codewords on the same RE.');
        end
        assert(strcmp(parts{prior}.SIB1PayloadHash,parts{ordinal}.SIB1PayloadHash), ...
            'sixgr:phy:broadcast:InconsistentCellSIB1','All cell SI beam occasions must carry the same SIB1.');
    end
end
tx=parts{1};
sampleRate=tx.SampleRateHz;
composer=sixgr.phy.waveform.WaveformStreamComposer(sampleRate,size(ssbWaveform,2),0);
composer.enqueue('SSB-burst',sixgr.phy.waveform.WaveformChunk(ssbWaveform,0),sampleRate);
numSamples=size(ssbWaveform,1);
for ordinal=1:numel(parts)
    part=parts{ordinal};
    composer.enqueue("SI-RNTI-SIB1-"+indices(ordinal), ...
        sixgr.phy.waveform.WaveformChunk(part.SIB1Waveform,part.SIB1WaveformStartSample),sampleRate);
    numSamples=max(numSamples,part.SIB1WaveformStartSample+size(part.SIB1Waveform,1));
    % Retain every exact SI allocation/grid/map without duplicating the
    % full SS burst in each occasion's export contract.
    parts{ordinal}=rmfield(part,{'SSBWaveform','SSBWaveInfo','SSBBurstPlan','SSBComposite'});
end
composite=composer.readThrough(numSamples);
[tx.Waveform,tx.ReferenceNoise]=localApplyAWGN(composite.Samples,tx.Carrier,p.Results.SNRdB);
tx.SIB1Transmissions=[parts{:}];
tx.Content=content;
tx.WaveformContent="ssb_mib_sib1_composite";
tx.SSBEmissionIncluded=true;
tx.SIB1EmissionIncluded=true;
tx.WaveformStartAbsoluteSample=tx.BroadcastStartSample;
tx.WaveformStartAbsoluteSymbolIndex0=tx.BroadcastStartAbsoluteSlot*double(tx.Carrier.SymbolsPerSlot);
tx.SIB1TransmitSSBIndices0Based=indices;
tx.SIB1TransmissionScope=string(sixgr.util.structGet(cfg,'phy.sib1.transmissionScope', ...
    sixgr.util.structGet(cfg,'initial_access.sib1_transmission_scope','selected_ssb_occasion')));
end

function tx=localSSBOnly(cfg,powerContract,snrDB)
% Keep original native samples and mapping. The selected metadata index does
% not prune the configured active burst bitmap or create a receiving UE.
index=sixgr.util.structGet(cfg,'phy.ssb.runtimeSSBIndex',0);
[samples,waveInfo,info]=sixgr.phy.dl.SSB_Tx(cfg, ...
    'NumSubframes',localSSBObservationSubframes(cfg),'SSBIndex',index);
carrier=sixgr.phy.grid.makeCarrier(cfg);
originSlot=double(carrier.NFrame)*double(carrier.SlotsPerFrame);
originSample=localAbsoluteSlotStartSample(originSlot,carrier,info.SampleRate_Hz);
[waveform,noise]=localApplyAWGN(samples,carrier,snrDB);
tx=struct('Content',"SSB_MIB",'WaveformContent',"ssb_mib_only", ...
    'Waveform',waveform,'ReferenceNoise',noise,'Config',cfg,'Carrier',carrier, ...
    'SampleRateHz',info.SampleRate_Hz,'SSBPowerReferenceContract',powerContract, ...
    'SSBWaveform',samples,'SSBWaveInfo',waveInfo,'SSBInfo',info, ...
    'SSBBurstPlan',info.SSBBurstPlan, ...
    'SSBComposite',sixgr.util.structGet(waveInfo,'SSBComposite',struct()), ...
    'BroadcastStartAbsoluteSlot',originSlot,'BroadcastStartSample',originSample, ...
    'WaveformStartAbsoluteSample',originSample, ...
    'WaveformStartAbsoluteSymbolIndex0',originSlot*double(carrier.SymbolsPerSlot), ...
    'SSBEmissionIncluded',true,'SIB1EmissionIncluded',false, ...
    'SIB1Transmissions',struct([]),'SIB1TransmitSSBIndices0Based',zeros(1,0), ...
    'UsedOracleFields',strings(0,1),'ProxyUsed',false,'Skipped',false,'ToolboxMissing',false);
end

function cfg = localNormalizeBroadcastCfg(cfg)
if ~isfield(cfg, "phy")
    cfg.phy = struct();
end
if ~isfield(cfg.phy, "carrier")
    cfg.phy.carrier = struct();
end
cfg.phy.carrier.NCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1));
cfg.phy.carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", 30)));
cfg.phy.carrier.SubcarrierSpacing_kHz = cfg.phy.carrier.SubcarrierSpacing;
cfg.phy.carrier.NSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 52));
cfg.phy.carrier.NStartGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NStartGrid", 0));
frame = sixgr.util.structGet(cfg,"phy.carrier.NFrame",0);
slot = sixgr.util.structGet(cfg,"phy.carrier.NSlot",0);
validateattributes(frame,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax/10});
validateattributes(slot,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
assert(slot==0,'sixgr:phy:broadcast:NonFrameAlignedBroadcast', ...
    'Composite SS/PBCH/SI buffers require an explicit frame-aligned origin; NSlot is not silently reset.');
cfg.phy.carrier.NSlot = double(slot);
cfg.phy.carrier.NFrame = double(frame);
cfg.phy.carrier.CyclicPrefix = char(string(sixgr.util.structGet(cfg, "phy.carrier.CyclicPrefix", "normal")));
end

function localAssertNoSSBSIResourceCollision( ...
        ssbWaveInfo, ssbInfo, siGrid, siAbsoluteSlot, carrier)
% Fail before OFDM composition when common SI overwrites an SS/PBCH RE.
%
% Both inputs are the exact production transmitter grids.  This check does
% not infer occupancy from YAML ranges and therefore remains valid when the
% band, BWP, SCS, SSB frequency offset, beam count, CORESET0, or SIB1
% allocation changes.  A gNB may time- or frequency-multiplex the signals,
% but it may never silently add two independently encoded channels onto the
% same antenna-port RE.
ssbCarrierGrid = localSSBGridInCarrierNumerology( ...
    ssbWaveInfo, ssbInfo, carrier);
symbolsPerSlot = double(carrier.SymbolsPerSlot);
if ~(isscalar(symbolsPerSlot) && isfinite(symbolsPerSlot) && ...
        symbolsPerSlot >= 1 && symbolsPerSlot == round(symbolsPerSlot))
    error("sixgr:phy:broadcast:InvalidCarrierSymbolsPerSlot", ...
        "SIB1/SSB collision validation requires a valid SymbolsPerSlot.");
end

if size(ssbCarrierGrid, 1) ~= size(siGrid, 1)
    error("sixgr:phy:broadcast:SSBSICarrierGridMismatch", ...
        ["SSB carrier grid has %d subcarriers while the Type-0/SIB1 grid " ...
         "has %d; both must share the resolved initial DL BWP."], ...
        size(ssbCarrierGrid, 1), size(siGrid, 1));
end
firstSymbol = round(double(siAbsoluteSlot)) * symbolsPerSlot + 1;
lastSymbol = firstSymbol + size(siGrid, 2) - 1;
if firstSymbol < 1 || lastSymbol > size(ssbCarrierGrid, 2)
    % The observation waveform can legitimately end before a later Type-0
    % occasion.  Timeline composition extends it; there is then no SSB RE
    % at that absolute slot with which SI can collide.
    return;
end
ssbSlice = ssbCarrierGrid(:, firstSymbol:lastSymbol, :);
ssbOccupied = any(abs(ssbSlice) > 0, 3);
siOccupied = any(abs(siGrid) > 0, 3);
collisionMask = ssbOccupied & siOccupied;
if any(collisionMask, "all")
    [subcarrierOneBased, symbolOneBased] = find(collisionMask, 1, "first");
    error("sixgr:phy:broadcast:SIB1SSBResourceCollision", ...
        "The resolved Type-0 PDCCH/SIB1 PDSCH allocation collides with " + ...
        "the transmitted SS/PBCH burst at absolute slot %d, symbol %d, " + ...
        "subcarrier %d. Select a standards-valid pdcch-ConfigSIB1/TDRA " + ...
        "combination; transmitter waveforms will not be superposed.", ...
        round(double(siAbsoluteSlot)), symbolOneBased - 1, ...
        subcarrierOneBased - 1);
end
end

function carrierGrid = localSSBGridInCarrierNumerology( ...
        ssbWaveInfo, ssbInfo, carrier)
% Map the exact Toolbox SS/PBCH grid onto the common carrier grid.  The
% mapping is exact for equal numerologies and uses the Point-A offsets
% already validated by SSBGridValidator. Mixed numerologies use an ownership
% mask on exact physical time intervals, never a fabricated complex grid.
ssbGrid = sixgr.util.structGet(ssbWaveInfo, ...
    "ResourceGridSSBurst.ResourceGrid", []);
if isempty(ssbGrid)
    error("sixgr:phy:broadcast:MissingSSBResourceGrid", ...
        "Strict SIB1 composition requires the exact SS/PBCH resource " + ...
        "grid returned by SSB_Tx.");
end
ssbSCSKHz = double(sixgr.util.structGet( ...
    ssbInfo, "SSBTiming.SSBSubcarrierSpacingKHz", NaN));
carrierSCSKHz = double(carrier.SubcarrierSpacing);
validateattributes(ssbSCSKHz,{'numeric'},{'scalar','finite','positive'});
if abs(ssbSCSKHz-carrierSCSKHz)>1e-12
    carrierGrid=sixgr.phy.broadcast.mixedSSBGridOccupancy(ssbGrid,ssbInfo,carrier);
    return;
end
validation = sixgr.util.structGet(ssbInfo, "SSBGridValidation", struct());
ssbLowHz = double(sixgr.util.structGet( ...
    validation, "SSBLowOffsetFromPointAHz", NaN));
carrierLowHz = double(sixgr.util.structGet( ...
    validation, "CarrierLowOffsetFromPointAHz", NaN));
spacingHz = carrierSCSKHz * 1e3;
startZeroBased = (ssbLowHz - carrierLowHz) / spacingHz;
if ~(isscalar(startZeroBased) && isfinite(startZeroBased) && ...
        startZeroBased >= 0 && ...
        abs(startZeroBased - round(startZeroBased)) < 1e-9)
    error("sixgr:phy:broadcast:SSBGridAlignmentMismatch", ...
        "The validated SS/PBCH low edge cannot be represented on the " + ...
        "initial-BWP subcarrier grid.");
end
startOneBased = round(startZeroBased) + 1;
stopOneBased = startOneBased + size(ssbGrid, 1) - 1;
numCarrierSubcarriers = 12 * double(carrier.NSizeGrid);
if stopOneBased > numCarrierSubcarriers
    error("sixgr:phy:broadcast:SSBGridOutsideCarrier", ...
        "The exact SS/PBCH grid exceeds the resolved initial DL BWP.");
end
carrierGrid = complex(zeros(numCarrierSubcarriers, size(ssbGrid, 2), ...
    size(ssbGrid, 3), "like", ssbGrid));
carrierGrid(startOneBased:stopOneBased, :, :) = ssbGrid;
end

function startSample = localAbsoluteSlotStartSample( ...
        absoluteSlot, carrier, sampleRate)
% Use the same exact CP-OFDM boundary authority as the received crop.
startSample=sixgr.phy.frame.slotStartSample(carrier,absoluteSlot,sampleRate);
end

function n = localSSBObservationSubframes(cfg)
n = double(sixgr.util.structGet(cfg, "phy.sib1.ssbObservationSubframes", ...
    sixgr.util.structGet(cfg, "phy.ssb.pbchObservationSubframes", 5)));
n = max(1, round(n));
end

function [y, provenance] = localApplyAWGN(x, carrier, snrDB)
y = x;
snrDB = double(snrDB);
provenance = struct( ...
    "Applied", false, ...
    "RequestedEsN0_dB", snrDB, ...
    "SNRDefinition", ...
        "Es/N0 for a unit-energy occupied resource-grid RE", ...
    "SignalEnergyPerOccupiedRE", 1, ...
    "GridNoiseVariance", NaN, ...
    "SampleNoiseVariance", NaN, ...
    "WaveformPowerUsed", false, ...
    "Status", "disabled_infinite_snr");
if ~isfinite(snrDB)
    return;
end
[y, exact] = sixgr.phy.waveform.addOccupiedREAWGN( ...
    x, carrier, snrDB, "SignalEnergyPerOccupiedRE", 1);
provenance = exact;
provenance.Applied = true;
provenance.Status = "applied_occupied_re_esn0";
provenance.BroadcastReferencePlane = ...
    "unit_energy_occupied_resource_grid_RE_before_receiver_equalization";
end
