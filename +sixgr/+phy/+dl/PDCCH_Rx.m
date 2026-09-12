function [rx, info] = PDCCH_Rx(rxWaveform, cfg, varargin)
%PDCCH_Rx Recover a basic PDCCH (DCI) transmission.
%
%   [RX,INFO] = sixgr.phy.dl.PDCCH_Rx(RXWAVEFORM, CFG) attempts to recover a
%   single-slot PDCCH from RXWAVEFORM using DMRS-aided timing, channel
%   estimation, MMSE equalization, and polar list decoding of DCI.
%
%   Connected configuration without explicit K uses receiver-installed
%   contexts and blind candidate/format/size search. Explicit K retains the
%   separately identified codec-calibration path. Legacy configurations may
%   use known-location reception or cfg.phy.pdcch.blindSearch=true.
%
%   Name-Value options:
%     "Carrier"        : nrCarrierConfig override
%     "PDCCH"          : nrPDCCHConfig override
%     "K"              : DCI payload length in bits (default 64)
%     "ListLength"     : polar list length for DCI decoding (default 8)
%     "RNTI"           : DCI CRC-mask RNTI override
%     "PDCCHScramblingRNTI" : physical PDCCH scrambling RNTI override
%     "NoiseVar"       : override noise variance (else estimate)
%     "ExpectedDCIBits": optional finalized-grant DCI bits for causal match
%     "SampleRate_Hz"  : sample rate (only needed for some timing APIs)
%
%   Outputs:
%     RX.DCIBits        : recovered DCI payload bits
%     RX.ErrFlag        : 0 if CRC passes, 1 otherwise (when available)
%     RX.Ok             : CRC pass and, for connected monitoring, valid context parse
%     RX.CausalGrantDecodeOk : true when CRC passes and ExpectedDCIBits match
%     RX.TimingOffset   : raw sample timing estimate
%     RX.AppliedTimingCorrection_samples : applied waveform correction
%     RX.NoiseVar       : noise variance used

sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.dl.PDCCH_Rx", ...
    "PDCCH", "DL", struct("Stage","RX"));

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDCCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('K', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('ListLength', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('RNTI', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('PDCCHScramblingRNTI', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('ExpectedDCIBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x));
ip.addParameter('NoiseOnlyWaveform', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('SampleRate_Hz', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('InputTimingAlignment',struct(),@(x)isstruct(x)&&isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;
hasConnectedPolicy=isfield(sixgr.util.structGet(cfg,'phy.pdcch.operatorControl',struct()),'connected_dci');
connectedMonitoring=isempty(opt.K) && hasConnectedPolicy;
contexts={}; payloadSizes=[];
if connectedMonitoring
    assert(isempty(opt.PDCCH) && isempty(opt.Carrier), ...
        'sixgr:phy:pdcch:TransmitterMonitoringOverride', ...
        'Connected blind monitoring constructs carrier and PDCCH from receiver configuration, not TX objects.');
    formats=string(cfg.phy.pdcch.operatorControl.dci_formats);
    for h=1:numel(formats)
        contexts{h}=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,formats(h)); %#ok<AGROW>
        a=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(contexts{h});
        payloadSizes(h)=a.Selected.AlignedBits; %#ok<AGROW>
    end
end
configuredPDCCH = logical(sixgr.util.structGet(cfg, "phy.pdcch.enable", false));
configuredDMRS = logical(sixgr.util.structGet(cfg, "phy.pdcch.dmrs.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "pdcch", configuredPDCCH, ...
    "PDCCH_Rx");
sixgr.config.assertRuntimeFeatureUse(cfg, "pdcch_dmrs", configuredDMRS, ...
    "PDCCH_Rx.DMRS");
if ~(configuredPDCCH && configuredDMRS)
    error("sixgr:phy:pdcch:DisabledByYAML", ...
        "PDCCH Rx cannot execute when PDCCH or its DM-RS is disabled by YAML.");
end

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

nCellID = double(sixgr.util.structGet(cfg, 'phy.carrier.NCellID', ...
    sixgr.util.structGet(cfg, 'scenario.NCellID', 1)));
if isempty(opt.RNTI)
    if connectedMonitoring
        rnti=contexts{1}.Data.RNTIValue;
    else
    rnti = double(sixgr.util.structGet(cfg, 'phy.pdcch.rnti', 4660));
    end
else
    rnti = double(opt.RNTI);
end
pdcchScramblingRNTI = localResolvePDCCHScramblingRNTI(cfg, rnti, opt.PDCCHScramblingRNTI);
if connectedMonitoring
    assert(rnti==contexts{1}.Data.RNTIValue && pdcchScramblingRNTI==rnti, ...
        'sixgr:phy:pdcch:ConnectedMonitoringIdentityMismatch','Receiver C-RNTI must match its installed context.');
end
if hasConnectedPolicy
    nCellID=double(cfg.phy.pdcch.operatorControl.connected_monitoring.dmrs_scrambling_id);
end

% PDCCH config
if isempty(opt.PDCCH)
    if hasConnectedPolicy
        [pdcch,candidateResolution]=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build( ...
            cfg,carrier,rnti,logical(sixgr.util.structGet(cfg,'phy.pdcch.blindSearch',false)));
    else
    [pdcch, candidateResolution] = localDefaultPDCCH( ...
        cfg, carrier, nCellID, ...
        localPDCCHConfigRNTI(rnti, pdcchScramblingRNTI));
    end
else
    pdcch = opt.PDCCH;
    candidateResolution = struct();
end

K = opt.K;
expectedDCIBits = localNormalizeDCIBits(opt.ExpectedDCIBits);
if isempty(K) && ~connectedMonitoring
    if ~isempty(expectedDCIBits)
        K = numel(expectedDCIBits);
    else
        K = double(sixgr.util.structGet(cfg, 'phy.pdcch.dciPayloadBits', 64));
    end
end
if ~connectedMonitoring, payloadSizes=K; contexts={[]}; end

listLen = opt.ListLength;
if isempty(listLen)
    listLen = double(sixgr.util.structGet(cfg, 'phy.pdcch.listLength', 8));
end

blind = logical(sixgr.util.structGet(cfg, 'phy.pdcch.blindSearch', false));
assert(~connectedMonitoring || blind,'sixgr:phy:pdcch:ConnectedBlindSearchRequired', ...
    'Connected monitoring requires the configured blind candidate search.');
sixgr.config.assertRuntimeFeatureUse(cfg, "pdcch_blind_search", blind, ...
    "PDCCH_Rx.blindSearch");

% ---------------------- Candidate resources ----------------------
% Known mapping (single candidate) or blind candidates
candSymInd = {};
candDMRSInd = {};
candDMRSSym = {};
candAggregationLevel = [];
candWithinAggregation = [];

if blind
    % This returns candidates for the configured search space.
    [allSymInd, allDMRSSym, allDMRSInd] = nrPDCCHSpace(carrier, pdcch);
    [candSymInd, candDMRSInd, candDMRSSym, candAggregationLevel, candWithinAggregation] = ...
        localCollectPDCCHCandidates(allSymInd, allDMRSInd, allDMRSSym);
    if isempty(candSymInd)
        error("sixgr:phy:pdcch:invalid_candidate_count", ...
            "Blind PDCCH monitoring resolved no legal candidates; known-location fallback is forbidden.");
    end
else
    [pdcchInd, dmrsSym, dmrsInd] = nrPDCCHResources(carrier, pdcch);
    candSymInd  = {pdcchInd};
    candDMRSInd = {dmrsInd};
    candDMRSSym = {dmrsSym};
    candAggregationLevel = double(localPDCCHProperty(pdcch, 'AggregationLevel', NaN));
    candWithinAggregation = double(localPDCCHProperty(pdcch, 'AllocatedCandidate', 1)) - 1;
end

% ---------------------- Timing estimation ----------------------
% Known-location PDCCH can use its configured DM-RS for timing.  In blind
% search, however, the first monitored candidate is not guaranteed to be the
% transmitted candidate.  Applying timing from an arbitrary absent candidate
% corrupts the whole slot before the real candidate is decoded, especially
% for AL2/AL4 searches.  Blind mode therefore requires timing from an
% external synchronization/tracking block unless explicitly enabled.
rxWave = rxWaveform;

sampleRateHz = opt.SampleRate_Hz;
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, 'phy.sampleRate_Hz', []);
end

allowBlindCandidateTiming = logical(sixgr.util.structGet(cfg, ...
    'phy.pdcch.allowBlindCandidateTimingEstimate', ...
    sixgr.util.structGet(cfg, 'phy.pdcch.blindTimingFromCandidateDMRS', false)));
skipTimingEstimate = logical(blind) && ~allowBlindCandidateTiming;
timingOffset = NaN;
timingSource = "nrTimingEstimate_pdcch_dmrs";
inputAligned=~isempty(fieldnames(opt.InputTimingAlignment));
if inputAligned
    alignment=opt.InputTimingAlignment;
    expected=sixgr.phy.frame.pdcchReceivedClockAlignment(alignment.Reference, ...
        carrier,alignment.NominalStartSample,sampleRateHz, ...
        alignment.Reference.ImplementationFilterDelay_samples);
    assert(isequaln(alignment,expected),'sixgr:phy:pdcch:InvalidInputTimingAlignment', ...
        'Input alignment must come from the causally available received SS/PBCH clock.');
    timingSource=alignment.Source;
elseif ~skipTimingEstimate
    try
        if isempty(sampleRateHz)
            timingOffset = nrTimingEstimate(carrier, rxWave, candDMRSInd{1}, candDMRSSym{1});
        else
            timingOffset = nrTimingEstimate(carrier, rxWave, candDMRSInd{1}, candDMRSSym{1}, 'SampleRate', sampleRateHz);
        end
    catch cause
        failure=MException('sixgr:phy:pdcch:TimingEstimationFailed', ...
            'Requested PDCCH timing estimation failed; decoding without synchronization is not a substitute.');
        throw(addCause(failure,cause));
    end
else
    timingSource = "external_sync_required_for_blind_pdcch_no_candidate_timing";
end
timingResolution = sixgr.phy.sync.resolveTimingApplication(timingOffset, ...
    "EstimateUsed", isfinite(double(timingOffset)) && ~skipTimingEstimate, ...
    "ApplicationMode", "signed_waveform_shift", ...
    "SkipRequested", skipTimingEstimate, ...
    "Source", timingSource);
if inputAligned
    % The observation origin already applies this measured shift. Applying
    % it a second time inside the receiver would corrupt the control grid.
    timingResolution.RawEstimate_samples=alignment.AppliedObservationShiftSamples;
    timingResolution.AppliedCorrection_samples=0;
    timingResolution.EstimateAvailable=true;
    timingResolution.EstimateUsed=true;
    timingResolution.WasClipped=false;
    timingResolution.ApplicationPolicy='received_clock_shift_applied_by_observation_owner_no_second_shift';
    timingResolution.Status='available_applied_at_observation_origin';
end
rxWave = localApplyTimingCorrection(rxWave, timingResolution.AppliedCorrection_samples);

% Decode when the monitored control symbols have actually arrived. The
% unreceived remainder of a slot is neither silence nor receiver evidence.
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
expectedSamples = double(sampling.CurrentSlotSamples);
extent=sixgr.phy.dl.pdcchObservationExtent(carrier, ...
    {candSymInd,candDMRSInd},sampling.ToolboxOFDMInfo);
if size(rxWave,1)<extent.MinimumReceiveSamples
    error('sixgr:phy:pdcch:IncompleteReceivedControlSymbols', ...
        'Actual received samples do not cover every monitored PDCCH/DM-RS symbol after timing alignment.');
end
if size(rxWave, 1) > expectedSamples
    rxWave = rxWave(1:expectedSamples, :);
end

% ---------------------- OFDM demod ----------------------
rxGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWave);

if size(rxGrid,2)<=extent.LastMonitoredSymbol0Based
    error('sixgr:phy:pdcch:IncompleteReceivedControlSymbols', ...
        'OFDM demodulation did not produce all actual monitored symbols.');
end

noiseGrid = [];
if ~isempty(opt.NoiseOnlyWaveform)
    noiseWave = localApplyTimingCorrection(opt.NoiseOnlyWaveform, timingResolution.AppliedCorrection_samples);
    if size(noiseWave,1)<size(rxWave,1)
        error('sixgr:phy:pdcch:IncompleteNoiseObservation', ...
            'An independent noise observation must cover the same received interval; zero padding is forbidden.');
    end
    if size(noiseWave, 1) > expectedSamples
        noiseWave = noiseWave(1:expectedSamples, :);
    end
    noiseGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, noiseWave);
    if size(noiseGrid,2)<size(rxGrid,2)
        error('sixgr:phy:pdcch:IncompleteNoiseObservation', ...
            'An independent noise grid must cover every actual received control symbol.');
    end
end

% ---------------------- Try candidates ----------------------
noiseVarUsed = opt.NoiseVar;
if isempty(noiseVarUsed)
    noiseVarUsed = NaN;
end

rx = struct();
rx.DCIBits = int8([]);
rx.ExpectedDCIBits = expectedDCIBits;
rx.DCIBitsCompared = 0;
rx.DCIBitErrors = NaN;
rx.DCIPayloadMatch = isempty(expectedDCIBits);
rx.CausalGrantDecodeOk = false;
rx.FalseAlarm = false;
rx.MissedDetection = ~isempty(expectedDCIBits);
rx.ErrFlag = 1;
rx.Ok = false;
rx.CandidateIndex = 0;
rx.CandidateFlatIndex = 0;
rx.CandidateAggregationLevel = NaN;
rx.CandidateIndexWithinAggregation = NaN;
rx.TimingOffset = double(timingResolution.RawEstimate_samples);
rx.RawTimingEstimate_samples = double(timingResolution.RawEstimate_samples);
rx.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
rx.TimingEstimateStatus = char(string(timingResolution.Status));
rx.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
rx.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
rx.ReceiverHestSINR_dB = NaN;
rx.ReceiverHestSINRSource = "pdcch_candidate_dmrs_unavailable";
rx.ReceiverHestSINRValueRole = "unavailable";
rx.ReceiverHestSINRValueStatus = "unavailable";
rx.ReceiverHestSINRNAReason = "no_candidate_channel_estimate_attempted";
rx.EVM_rms = NaN;
rx.NoiseVar = NaN;
rx.NoiseVarStatus = "unavailable";
rx.NoiseVarSource = "pdcch_receiver_not_attempted";
rx.NoiseVarReason = "no_candidate_channel_estimate_attempted";
rx.ChannelEstimate = [];
rx.RxGrid = rxGrid;
rx.EqualizedSymbols = complex([]);
candidateRows = repmat(localEmptyCandidateRow(), 0, 1);
passingRx = cell(0, 1);
crcPassingRx=cell(0,1);

for c = 1:numel(candSymInd)
    symInd  = candSymInd{c};
    dmrsInd = candDMRSInd{c};
    dmrsSym = candDMRSSym{c};

    % Channel estimate
    if size(rxGrid,2)==double(carrier.SymbolsPerSlot)
        [hEst, nVarEst] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym);
    else
        % The index/symbol Toolbox signature requires a whole slot.
        % Its reference-grid signature supports the actual received
        % prefix. Zeros here mean non-reference REs, never RX samples.
        kSub=size(rxGrid,1); nSymbols=size(rxGrid,2);
        slotREs=kSub*double(carrier.SymbolsPerSlot);
        refs=double(dmrsInd(:))-1;
        refSymbols=floor(mod(refs,slotREs)/kSub);
        if any(refSymbols>=nSymbols)
            error('sixgr:phy:pdcch:UnreceivedReferenceSymbols', ...
                'Channel estimation cannot use DM-RS symbols that have not arrived.');
        end
        refPorts=floor(refs/slotREs);
        referenceGrid=complex(zeros(kSub,nSymbols,max(refPorts)+1,'like',rxGrid));
        prefixIndices=mod(refs,kSub)+1+kSub*refSymbols+kSub*nSymbols*refPorts;
        referenceGrid(prefixIndices)=dmrsSym(:);
        [hEst,nVarEst]=nrChannelEstimate(carrier,rxGrid,referenceGrid);
    end

    if isnan(noiseVarUsed)
        nVar = double(nVarEst);
    else
        nVar = double(noiseVarUsed);
    end
    noiseGridNVar = localPDCCHNoiseGridVariance(noiseGrid, dmrsInd);
    [nVar, nVarStatus, nVarSource, nVarReason] = localResolvePDCCHNoiseVariance( ...
        nVar, nVarEst, noiseGridNVar, hEst, dmrsInd, dmrsSym, rxGrid);

    % Extract + equalize
    [rxSym, hSym] = nrExtractResources(symInd, rxGrid, hEst);
    [eqSym, csi] = nrEqualizeMMSE(rxSym, hSym, nVar);
    [candidateSINR_dB, candidateSINRStatus, candidateSINRReason] = localPDCCHReferenceSINR(hEst, nVar, dmrsInd, dmrsSym, rxGrid);

    % PDCCH decode -> soft bits
    rxCW = nrPDCCHDecode(eqSym, nCellID, pdcchScramblingRNTI, nVar);
    rxCW = localApplyPDCCHCSIWeighting(rxCW, csi);

    % Reuse received REs/Hest/LLRs across independently configured payload
    % hypotheses. ExpectedDCIBits never selects a size, format or candidate.
    for h=1:numel(payloadSizes)
    K=payloadSizes(h);
    [dciBits, errFlag] = nrDCIDecode(rxCW, K, listLen, rnti);
    decoded=struct(); parseOK=~connectedMonitoring; parseFailure="";
    if connectedMonitoring && errFlag==0
        try
            decoded=sixgr.phy.pdcch.DCIParser.parse(dciBits,contexts{h});
            parseOK=true;
        catch cause
            % Invalid/reserved received fields are a rejected hypothesis;
            % unrelated programming failures must not become radio errors.
            if ~ismember(string(cause.identifier),[ ...
                    "sixgr:phy:pdcch:field_out_of_range", ...
                    "sixgr:phy:pdcch:dci_size_alignment_failure", ...
                    "sixgr:phy:pdcch:ReservedULPrecodingCodepoint", ...
                    "sixgr:phy:pdcch:ReservedULDMRSCodepoint", ...
                    "sixgr:phy:pdcch:ReservedDLDMRSCodepoint"])
                rethrow(cause);
            end
            parseFailure=string(cause.identifier);
        end
    end

    rx.DCIBits = int8(dciBits(:));
    rx.ErrFlag = double(errFlag);
    rx.Ok = (rx.ErrFlag == 0) && parseOK;
    rx.DecodedDCI=decoded;
    rx.DCIPayloadLength=K;
    rx.DCIContextDigest=""; rx.DCIFormat="";
    rx.DCISelectionSource="explicit_or_legacy_payload_length";
    if connectedMonitoring
        rx.DCIContextDigest=contexts{h}.Digest;
        rx.DCIFormat=contexts{h}.Data.DCIFormat;
        rx.DCISelectionSource="receiver_installed_context_crc_and_semantic_parse";
    end
    [dciBitErrors, dciBitsCompared, dciPayloadMatch] = localCompareDCIBits(expectedDCIBits, rx.DCIBits);
    rx.DCIBitsCompared = double(dciBitsCompared);
    rx.DCIBitErrors = double(dciBitErrors);
    rx.DCIPayloadMatch = logical(dciPayloadMatch);
    rx.CausalGrantDecodeOk = logical(rx.Ok && dciPayloadMatch);
    rx.FalseAlarm = logical(rx.Ok && ~dciPayloadMatch && ~isempty(expectedDCIBits));
    rx.MissedDetection = logical(~rx.Ok && ~isempty(expectedDCIBits));
    rx.CandidateIndex = c;
    rx.CandidateFlatIndex = c;
    rx.CandidateAggregationLevel = double(candAggregationLevel(c));
    rx.CandidateIndexWithinAggregation = double(candWithinAggregation(c));
    rx.NoiseVar = nVar;
    rx.NoiseVarStatus = char(string(nVarStatus));
    rx.NoiseVarSource = char(string(nVarSource));
    rx.NoiseVarReason = char(string(nVarReason));
    rx.ChannelEstimate = hEst;
    rx.EqualizedSymbols = eqSym;
    rx.ReceiverHestSINR_dB = double(candidateSINR_dB);
    rx.ReceiverHestSINRSource = "pdcch_dmrs_hest_noise_variance";
    rx.ReceiverHestSINRValueRole = "estimated";
    rx.ReceiverHestSINRValueStatus = char(string(candidateSINRStatus));
    rx.ReceiverHestSINRNAReason = char(string(candidateSINRReason));
    rx.EVM_rms = localPDCCHSymbolEVM(eqSym);

    row = localEmptyCandidateRow();
    row.CandidateIndex = double(c);
    row.CandidateFlatIndex = double(c);
    row.AggregationLevel = double(candAggregationLevel(c));
    row.CandidateIndexWithinAggregation = double(candWithinAggregation(c));
    row.DecodeAttempted = true;
    row.DCIPayloadLength=K;
    row.DCIFormat=rx.DCIFormat;
    row.DCIContextDigest=rx.DCIContextDigest;
    row.CRCOK=(errFlag==0);
    row.ContextParseOK=parseOK;
    row.ContextParseFailure=parseFailure;
    row.DecodeOK = logical(rx.Ok);
    row.ErrFlag = double(errFlag);
    row.DCIBitsCompared = double(dciBitsCompared);
    row.DCIBitErrors = double(dciBitErrors);
    row.DCIPayloadMatch = logical(dciPayloadMatch);
    row.CausalGrantDecodeOk = logical(rx.CausalGrantDecodeOk);
    row.FalseAlarm = logical(rx.FalseAlarm);
    row.MissedDetection = logical(rx.MissedDetection);
    row.NoiseVariance = double(nVar);
    row.NoiseVarStatus = string(nVarStatus);
    row.NoiseVarSource = string(nVarSource);
    row.NoiseVarReason = string(nVarReason);
    row.ReceiverHestSINR_dB = double(candidateSINR_dB);
    row.ReceiverHestSINRValueStatus = string(candidateSINRStatus);
    row.ReceiverHestSINRNAReason = string(candidateSINRReason);
    row.EVM_rms = double(rx.EVM_rms);
    row.PDCCHRECount = double(numel(symInd));
    row.DMRSRECount = double(numel(dmrsInd));
    candidateRows(end+1, 1) = row; %#ok<AGROW>
    if errFlag==0
        crcPassingRx{end+1,1}=rx; %#ok<AGROW>
    end
    if rx.Ok
        passingRx{end+1,1} = rx; %#ok<AGROW>
    end
    end
end

[selectedPassingIndex, hypothesisClass] = ...
    sixgr.phy.pdcch.reduceBlindHypotheses(passingRx);
validHypothesisCount = numel(passingRx);
if selectedPassingIndex > 0
    rx = passingRx{selectedPassingIndex};
end
rx.ValidHypothesisCount = validHypothesisCount;
rx.HypothesisReductionClass = char(hypothesisClass);
rx.MultipleEquivalentValidHypotheses = hypothesisClass == "equivalent";
rx.EquivalentValidHypothesisCount = double((hypothesisClass == "equivalent") * validHypothesisCount);
rx.AmbiguousValidHypotheses = hypothesisClass == "ambiguous";
rx.AmbiguousHypothesisCount = double((hypothesisClass == "ambiguous") * validHypothesisCount);
if rx.AmbiguousValidHypotheses
    % Multiple CRC-valid hypotheses with different decoded payloads cannot
    % be reduced without an oracle. Fail closed. Multiple hypotheses that
    % decode to the same payload are one semantic DCI observation and are
    % accepted by reduceBlindHypotheses without consulting ExpectedDCIBits.
    rx.Ok = false;
    rx.CausalGrantDecodeOk = false;
    rx.MissedDetection=~isempty(expectedDCIBits);
    rx.DecodedDCI=struct();
end

info = struct();
info.ReceiveExtent = extent;
info.DemodulatedReceiveSamples = size(rxWave,1);
info.DemodulatedSymbols = size(rxGrid,2);
info.ReceivePaddingApplied = false;
info.CarrierInfo = cinfo;
info.NCellID = double(carrier.NCellID);
info.PDCCHScramblingID = nCellID;
info.RNTI = rnti;
info.DCICrcRNTI = rnti;
info.PDCCHScramblingRNTI = pdcchScramblingRNTI;
info.K = rx.DCIPayloadLength;
info.MonitoredPayloadSizes=payloadSizes;
info.DCISelectionSource=rx.DCISelectionSource;
info.ReceiverConfiguredMonitoring=connectedMonitoring;
info.ReceiverAbsoluteSlotIndex0=double(sixgr.util.structGet(cfg,'lls6g.runtime.AbsoluteSlotIndex0',NaN));
info.ExpectedDCIBits = expectedDCIBits;
info.DCIBitsCompared = double(rx.DCIBitsCompared);
info.DCIBitErrors = double(rx.DCIBitErrors);
info.DCIPayloadMatch = logical(rx.DCIPayloadMatch);
info.CausalGrantDecodeOk = logical(rx.CausalGrantDecodeOk);
info.FalseAlarm = logical(rx.FalseAlarm);
info.MissedDetection = logical(rx.MissedDetection);
info.ListLength = listLen;
info.BlindSearch = blind;
info.NumCandidatesAvailable = numel(candSymInd);
info.NumCandidatesTried = numel(candSymInd);
info.NumDecodeHypothesesTried=numel(candidateRows);
if ~isempty(fieldnames(candidateResolution))
    info.ConfiguredSearchSpaceNumCandidates = ...
        candidateResolution.ConfiguredCandidates;
    info.ResolvedSearchSpaceNumCandidates = ...
        candidateResolution.ResolvedCandidates;
    info.SearchSpaceCandidateCapacity = ...
        candidateResolution.MaximumCandidates;
    info.SearchSpaceNCCE = candidateResolution.NCCE;
    info.SearchSpaceCandidateResolutionSource = ...
        char(candidateResolution.Source);
end
info.ValidHypothesisCount = numel(passingRx);
% Preserve measured CRC-valid observations for a composite-slot consumer.
% The scalar RX contract still rejects ambiguous single-DCI selection; do
% not choose a payload using ExpectedDCIBits or discard other valid DCIs.
% These are raw hypotheses, not yet independently validated scheduler grants.
info.CRCValidHypotheses = crcPassingRx;
info.ContextValidHypotheses=passingRx;
info.CRCValidHypothesisCount=numel(crcPassingRx);
info.HypothesisReductionClass = char(hypothesisClass);
info.MultipleEquivalentValidHypotheses = logical(rx.MultipleEquivalentValidHypotheses);
info.EquivalentValidHypothesisCount = double(rx.EquivalentValidHypothesisCount);
info.AmbiguousValidHypotheses = logical(rx.AmbiguousValidHypotheses);
info.AmbiguousHypothesisCount = double(rx.AmbiguousHypothesisCount);
info.TimingEstimate = timingResolution;
if ~isempty(candidateRows)
    info.CandidateResults = struct2table(candidateRows, "AsArray", true);
end
info.ReceiverHestSINR_dB = double(rx.ReceiverHestSINR_dB);
info.ReceiverHestSINRSource = char(string(rx.ReceiverHestSINRSource));
info.ReceiverHestSINRValueStatus = char(string(rx.ReceiverHestSINRValueStatus));
info.ReceiverHestSINRNAReason = char(string(rx.ReceiverHestSINRNAReason));
info.EVM_rms = double(rx.EVM_rms);

end

function row = localEmptyCandidateRow()
row = struct( ...
    "DCIPayloadLength",NaN,"DCIFormat","","DCIContextDigest","", ...
    "CRCOK",false,"ContextParseOK",false,"ContextParseFailure","", ...
    "CandidateIndex", NaN, ...
    "CandidateFlatIndex", NaN, ...
    "AggregationLevel", NaN, ...
    "CandidateIndexWithinAggregation", NaN, ...
    "DecodeAttempted", false, ...
    "DecodeOK", false, ...
    "ErrFlag", NaN, ...
    "DCIBitsCompared", 0, ...
    "DCIBitErrors", NaN, ...
    "DCIPayloadMatch", false, ...
    "CausalGrantDecodeOk", false, ...
    "FalseAlarm", false, ...
    "MissedDetection", false, ...
    "NoiseVariance", NaN, ...
    "NoiseVarStatus", "", ...
    "NoiseVarSource", "", ...
    "NoiseVarReason", "", ...
    "ReceiverHestSINR_dB", NaN, ...
    "ReceiverHestSINRValueStatus", "", ...
    "ReceiverHestSINRNAReason", "", ...
    "EVM_rms", NaN, ...
    "PDCCHRECount", NaN, ...
    "DMRSRECount", NaN);
end

function bits = localNormalizeDCIBits(rawBits)
bits = int8([]);
if isempty(rawBits)
    return;
end
vals = double(rawBits(:));
if isempty(vals)
    return;
end
bits = int8(vals ~= 0);
end

function [bitErrors, bitsCompared, payloadMatch] = localCompareDCIBits(expectedBits, decodedBits)
if isempty(expectedBits)
    bitErrors = NaN;
    bitsCompared = 0;
    payloadMatch = true;
    return;
end
expectedBits = localNormalizeDCIBits(expectedBits);
decodedBits = localNormalizeDCIBits(decodedBits);
bitsCompared = min(numel(expectedBits), numel(decodedBits));
if bitsCompared > 0
    bitErrors = sum(expectedBits(1:bitsCompared) ~= decodedBits(1:bitsCompared));
else
    bitErrors = 0;
end
bitErrors = bitErrors + abs(numel(expectedBits) - numel(decodedBits));
payloadMatch = (bitErrors == 0) && (numel(decodedBits) == numel(expectedBits));
end

function [nVar, status, source, reason] = localResolvePDCCHNoiseVariance(nVar, nVarEst, noiseGridNVar, hEst, dmrsInd, dmrsSym, rxGrid)
status = "unavailable";
source = "pdcch_noise_variance_unresolved";
reason = "missing_positive_noise_variance";
overrideNVar = double(nVar);
noiseGridNVar = double(noiseGridNVar);
if isscalar(noiseGridNVar) && isfinite(noiseGridNVar) && noiseGridNVar > 0
    nVar = noiseGridNVar;
    status = "OK";
    source = "noise_only_waveform_ofdm_grid_variance";
    reason = "";
    return;
end

nVarEst = double(nVarEst);
if isscalar(nVarEst) && isfinite(nVarEst) && nVarEst > 0
    nVar = nVarEst;
    status = "OK";
    source = "nrChannelEstimate_grid_noise_variance";
    reason = "";
    return;
end

if isscalar(overrideNVar) && isfinite(overrideNVar) && overrideNVar > 0
    nVar = overrideNVar;
    status = "OK";
    source = "pdcch_receiver_noise_variance_override_waveform_domain";
    reason = "grid_domain_noise_estimate_unavailable";
    return;
end

[residualVar, residualOk] = localPDCCHDMRSResidualVariance(hEst, dmrsInd, dmrsSym, rxGrid);
if residualOk && isfinite(residualVar) && residualVar > 0
    nVar = residualVar;
    status = "OK";
    source = "pdcch_dmrs_residual_noise_variance";
    reason = "";
    return;
end

rxPower = mean(abs(double(rxGrid(:))).^2, "omitnan");
if ~(isfinite(rxPower) && rxPower > 0)
    rxPower = 1;
end
nVar = max(eps(rxPower), realmin("double"));
status = "REVIEW_REQUIRED";
source = "positive_numeric_floor_from_rx_grid_power";
reason = "pdcch_noise_variance_estimate_missing_or_zero";
end

function nVar = localPDCCHNoiseGridVariance(noiseGrid, refInd)
nVar = NaN;
if isempty(noiseGrid) || isempty(refInd)
    return;
end
try
    noiseRef = nrExtractResources(refInd, noiseGrid);
catch
    try
        noiseRef = noiseGrid(refInd);
    catch
        return;
    end
end
if isempty(noiseRef)
    return;
end
v = mean(abs(double(noiseRef(:))).^2, "omitnan");
if isfinite(v) && v > 0
    nVar = double(v);
end
end

function [residualVar, ok] = localPDCCHDMRSResidualVariance(hEst, dmrsInd, dmrsSym, rxGrid)
residualVar = NaN;
ok = false;
if isempty(hEst) || isempty(dmrsInd) || isempty(dmrsSym) || isempty(rxGrid)
    return;
end
try
    [rxRef, hRef] = nrExtractResources(dmrsInd, rxGrid, hEst);
catch
    return;
end
refSym = double(dmrsSym(:));
numRE = min([size(rxRef, 1), size(hRef, 1), numel(refSym)]);
if numRE < 1
    return;
end
rxRef = double(rxRef(1:numRE, :, :, :));
hRef = double(hRef(1:numRE, :, :, :));
refSym = reshape(refSym(1:numRE), [], 1, 1, 1);
valid = abs(refSym) > sqrt(eps);
if ~any(valid(:))
    return;
end
validVec = reshape(valid, [], 1);
recon = hRef(validVec, :, :, :) .* reshape(refSym(validVec), [], 1, 1, 1);
residual = rxRef(validVec, :, :, :) - recon;
residualVar = mean(abs(residual(:)).^2, "omitnan");
ok = isfinite(residualVar) && residualVar > 0;
end

function [sinr_dB, status, reason] = localPDCCHReferenceSINR(hEst, nVar, dmrsInd, dmrsSym, rxGrid)
sinr_dB = NaN;
status = "unavailable";
reason = "missing_dmrs_reference_measurement";
if isempty(hEst) || isempty(dmrsInd) || isempty(dmrsSym) || isempty(rxGrid)
    return;
end
try
    [rxRef, hRef] = nrExtractResources(dmrsInd, rxGrid, hEst);
catch
    reason = "dmrs_resource_extraction_failed";
    return;
end
refSym = double(dmrsSym(:));
numRE = min([size(rxRef, 1), size(hRef, 1), numel(refSym)]);
if numRE < 1
    return;
end
rxRef = double(rxRef(1:numRE, :, :, :));
hRef = double(hRef(1:numRE, :, :, :));
refSym = reshape(refSym(1:numRE), [], 1, 1, 1);
valid = abs(refSym) > sqrt(eps);
if ~any(valid(:))
    reason = "zero_dmrs_reference_symbols";
    return;
end
validVec = reshape(valid, [], 1);
recon = hRef(validVec, :, :, :) .* reshape(refSym(validVec), [], 1, 1, 1);
signalPow = mean(abs(recon(:)).^2, "omitnan");
nVar = double(nVar);
if ~(isscalar(nVar) && isfinite(nVar) && nVar > 0)
    residual = rxRef(validVec, :, :, :) - recon;
    nVar = mean(abs(residual(:)).^2, "omitnan");
end
if isfinite(signalPow) && signalPow > 0 && isfinite(nVar) && nVar > 0
    sinr_dB = 10 * log10(signalPow / nVar);
    status = "OK";
    reason = "";
else
    reason = "nonfinite_signal_or_noise_power";
end
end

function evm = localPDCCHSymbolEVM(eqSym)
evm = NaN;
if isempty(eqSym)
    return;
end
x = double(eqSym(:));
x = x(isfinite(real(x)) & isfinite(imag(x)));
if isempty(x)
    return;
end
ref = sign(real(x)) + 1i * sign(imag(x));
zeroMask = real(ref) == 0;
ref(zeroMask) = ref(zeroMask) + 1;
zeroMask = imag(ref) == 0;
ref(zeroMask) = ref(zeroMask) + 1i;
ref = ref ./ sqrt(2);
evm = sqrt(mean(abs(x - ref).^2, "omitnan") / max(mean(abs(ref).^2, "omitnan"), eps));
end

function rxCW = localApplyPDCCHCSIWeighting(rxCW, csi)
% Apply symbol reliability to PDCCH soft bits after demodulation.
%
% The 5G Toolbox PDCCH receiver examples weight the decoded codeword LLRs,
% not the equalized QPSK symbols. Weighting the constellation directly
% changes the decision geometry and can turn a high-SINR control channel
% into random-looking DCI bits.
if isempty(rxCW) || isempty(csi)
    return;
end
llr = double(rxCW(:));
rel = double(real(csi(:)));
rel = rel(isfinite(rel));
if isempty(rel)
    return;
end
rel = max(rel, 0);
meanRel = mean(rel, "omitnan");
if ~(isfinite(meanRel) && meanRel > 0)
    return;
end
rel = rel ./ meanRel;
rel = min(max(rel, 0), 10);
if numel(llr) == 2 * numel(rel)
    w = repelem(rel, 2);
elseif numel(llr) == numel(rel)
    w = rel;
else
    return;
end
rxCW = reshape(llr .* double(w(:)), size(rxCW));
end

function y = localApplyTimingCorrection(x, timingOffset)
timingOffset = round(double(timingOffset));
if ~isfinite(timingOffset) || timingOffset == 0
    y = x;
elseif timingOffset > 0
    if timingOffset < size(x, 1)
        y = x(1+timingOffset:end, :);
    else
        error('sixgr:phy:pdcch:IncompleteTimingObservation', ...
            'The timing estimate consumes the received observation.');
    end
else
    error('sixgr:phy:pdcch:MissingTimingPrehistory', ...
        'Negative timing alignment requires actual earlier received samples, not a fabricated zero prefix.');
end
end

function [candSymInd, candDMRSInd, candDMRSSym, candAggregationLevel, candWithinAggregation] = localCollectPDCCHCandidates(allSymInd, allDMRSInd, allDMRSSym)
candSymInd = {};
candDMRSInd = {};
candDMRSSym = {};
candAggregationLevel = [];
candWithinAggregation = [];
if ~iscell(allSymInd)
    return;
end
aggregationLevels = [1 2 4 8 16];
for i = 1:numel(allSymInd)
    s = allSymInd{i};
    dIdx = allDMRSInd{i};
    dSym = allDMRSSym{i};
    if isempty(s) || isempty(dIdx) || isempty(dSym)
        continue;
    end
    [sList, dIdxList, dSymList] = localSplitPDCCHSpaceCandidates(s, dIdx, dSym);
    for j = 1:numel(sList)
        if ~isempty(sList{j}) && ~isempty(dIdxList{j}) && ~isempty(dSymList{j})
            candSymInd{end+1,1} = sList{j}; %#ok<AGROW>
            candDMRSInd{end+1,1} = dIdxList{j}; %#ok<AGROW>
            candDMRSSym{end+1,1} = dSymList{j}; %#ok<AGROW>
            if i <= numel(aggregationLevels)
                candAggregationLevel(end+1,1) = aggregationLevels(i); %#ok<AGROW>
            else
                candAggregationLevel(end+1,1) = NaN; %#ok<AGROW>
            end
            % Toolbox candidate numbering is exposed as a zero-based
            % index within each aggregation level, matching 38.213-style
            % candidate notation. CandidateIndex above remains the legacy
            % one-based flat attempt ordinal for compatibility.
            candWithinAggregation(end+1,1) = j - 1; %#ok<AGROW>
        end
    end
end
end

function [sList, dIdxList, dSymList] = localSplitPDCCHSpaceCandidates(s, dIdx, dSym)
% nrPDCCHSpace returns one cell per aggregation level. Within each cell, the
% second dimension enumerates candidates. Treating the full matrix as one
% candidate causes the receiver to combine unrelated CCEs and makes the DCI
% bits random even at high SINR.
sList = {};
dIdxList = {};
dSymList = {};
try
    nCand = max([size(s, 2), size(dIdx, 2), size(dSym, 2)]);
catch
    nCand = 1;
end
if nCand <= 1
    sList = {s(:)};
    dIdxList = {dIdx(:)};
    dSymList = {dSym(:)};
    return;
end
for c = 1:nCand
    sCol = localCandidateColumn(s, c);
    dIdxCol = localCandidateColumn(dIdx, c);
    dSymCol = localCandidateColumn(dSym, c);
    if isempty(sCol) || isempty(dIdxCol) || isempty(dSymCol)
        continue;
    end
    sList{end+1,1} = sCol(:); %#ok<AGROW>
    dIdxList{end+1,1} = dIdxCol(:); %#ok<AGROW>
    dSymList{end+1,1} = dSymCol(:); %#ok<AGROW>
end
end

function col = localCandidateColumn(x, c)
col = [];
if isempty(x)
    return;
end
if isvector(x)
    if c == 1
        col = x(:);
    end
    return;
end
if c <= size(x, 2)
    col = x(:, c);
end
end

% ---------------------- Local helper ----------------------
function scramblingRNTI = localResolvePDCCHScramblingRNTI(cfg, dciRNTI, optScramblingRNTI)
if ~isempty(optScramblingRNTI)
    scramblingRNTI = double(optScramblingRNTI);
    return;
end
configured = sixgr.util.structGet(cfg, 'phy.pdcch.scramblingRNTI', []);
if ~isempty(configured)
    scramblingRNTI = double(configured);
    return;
end
if double(dciRNTI) == 65535
    scramblingRNTI = 0;
else
    scramblingRNTI = double(dciRNTI);
end
end

function configRNTI = localPDCCHConfigRNTI(dciRNTI, scramblingRNTI)
% nrPDCCHConfig validators reject SI-RNTI. Resource generation only needs a
% valid object RNTI, while DCI CRC validation still uses the requested RNTI.
if double(dciRNTI) == 65535
    configRNTI = double(scramblingRNTI);
else
    configRNTI = double(dciRNTI);
end
end

function value = localPDCCHProperty(obj, propertyName, defaultValue)
value = defaultValue;
if isprop(obj, propertyName)
    try
        value = obj.(propertyName);
    catch
        value = defaultValue;
    end
end
end

function [pdcch, candidateResolution] = localDefaultPDCCH( ...
        cfg, carrier, nCellID, rnti)
% Create a minimal, valid PDCCH configuration.

% CORESET
coreset = nrCORESETConfig;
coresetID = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.id', 0));
localSetPropIfPresent(coreset, {'CORESETID','ID'}, coresetID);
coreset.Duration = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.duration', 2));

fr = sixgr.util.structGet(cfg, 'phy.pdcch.coreset.frequencyResources', []);
if isempty(fr)
    % Default: enable all 6 REG-bundle groups (common in examples)
    fr = ones(1, 6);
end
coreset.FrequencyResources = double(fr(:).');

% Search space
ss = nrSearchSpaceConfig;
searchSpaceID = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.id', 1));
localSetPropIfPresent(ss, {'SearchSpaceID','ID'}, searchSpaceID);
ss.CORESETID = localGetFirstProp(coreset, {'CORESETID','ID'}, 0);
ss.StartSymbolWithinSlot = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.startSymbol', 0));
ss.SlotPeriodAndOffset = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.slotPeriodAndOffset', [1 0]));
ss.Duration = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.duration', 1));

aggr = double(sixgr.util.structGet(cfg, 'phy.pdcch.aggregationLevel', 4));
if ~ismember(aggr, [1 2 4 8 16])
    aggr = 4;
end
idxAgg = find([1 2 4 8 16] == aggr, 1, 'first');
numCand = sixgr.util.structGet(cfg, ...
    'phy.pdcch.searchSpace.configuredNumCandidates', ...
    sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.numCandidates', []));
numCand = double(numCand(:).');
if isempty(numCand)
    numCand = zeros(1,5);
    numCand(idxAgg) = 1;
end
if numel(numCand) < 5
    numCand(numel(numCand)+1:5) = 0;
end
numCand = numCand(1:5);
enabledLevels = double(sixgr.util.structGet(cfg, ...
    'phy.pdcch.aggregationLevels', aggr));
[numCand, candidateResolution] = ...
    sixgr.phy.pdcch.resolveSearchSpaceCandidates( ...
    numCand, coreset.FrequencyResources, coreset.Duration, enabledLevels);
if numCand(idxAgg) < 1
    error("sixgr:phy:pdcch:selected_aggregation_level_unavailable", ...
        ['Selected aggregation level %d has no legal candidate in the ' ...
         '%d-CCE CORESET after resolving configured candidates [%s].'], ...
        aggr, candidateResolution.NCCE, ...
        strjoin(string(candidateResolution.ConfiguredCandidates), ','));
end
ss.NumCandidates = double(numCand(:).');

% PDCCH config
pdcch = nrPDCCHConfig;
localSetPropIfPresent(pdcch, {'NCellID','DMRSScramblingID'}, double(nCellID));
pdcch.RNTI = double(rnti);
pdcch.CORESET = coreset;
pdcch.SearchSpace = ss;

pdcch.AggregationLevel = aggr;

% Some configurations require setting the NStartBWP/NSizeBWP. If present in
% your MATLAB version, set from carrier grid.
try
    pdcch.NStartBWP = double(sixgr.util.structGet(cfg, 'phy.pdcch.nStartBWP', carrier.NStartGrid));
    pdcch.NSizeBWP  = double(sixgr.util.structGet(cfg, 'phy.pdcch.nSizeBWP', carrier.NSizeGrid));
catch
    % Ignore if properties do not exist.
end

function tf = localSetPropIfPresent(obj, propNames, value)
tf = false;
for i = 1:numel(propNames)
    p = char(string(propNames{i}));
    if isprop(obj, p)
        try
            obj.(p) = value;
            tf = true;
            return;
        catch
        end
    end
end
end

function v = localGetFirstProp(obj, propNames, defaultVal)
v = defaultVal;
for i = 1:numel(propNames)
    p = char(string(propNames{i}));
    if isprop(obj, p)
        try
            v = obj.(p);
            return;
        catch
        end
    end
end
end

end
