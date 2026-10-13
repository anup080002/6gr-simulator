function [freqHz, info] = estimateCFOFromReferenceSymbols(rxGrid, refInd, refSym, carrier, sampleRateHz, options)
%estimateCFOFromReferenceSymbols Estimate common frequency offset from RS phase drift.
%
% The estimate is derived from received reference-symbol phase versus OFDM
% symbol time. It is only available when the reference mapping spans at
% least two distinct OFDM symbols with matching frequency/port references.
% Independent phase wraps are resolved within the shortest observed pair's
% ambiguity interval; no injected frequency or channel coefficients are used.
% ReferenceGroupIDs separates installed resources/precoders whose unknown
% effective channels must not be correlated. The default is one fixed grant.
arguments
    rxGrid
    refInd
    refSym
    carrier
    sampleRateHz
    options.ReferenceGroupIDs = []
end

info = struct( ...
    "EstimateAvailable", false, ...
    "EstimatedCFO_Hz", NaN, ...
    "Status", "not_computed", ...
    "Source", "reference_symbol_phase_slope", ...
    "NumReferenceRE", 0, ...
    "NumSymbolsUsed", 0, ...
    "SymbolIndices", zeros(0, 1), ...
    "SampleRate_Hz", NaN);
freqHz = NaN;

if isempty(rxGrid) || isempty(refInd) || isempty(refSym)
    info.Status = "empty_reference_or_grid";
    return;
end
if ~isnumeric(rxGrid) || ~isnumeric(refInd) || ~isnumeric(refSym)
    info.Status = "non_numeric_reference_or_grid";
    return;
end

sampleRateHz = double(sampleRateHz);
if ~(isscalar(sampleRateHz) && isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = localCarrierSampleRate(carrier);
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    info.Status = "sample_rate_unavailable";
    return;
end

dims = size(rxGrid);
if numel(dims) < 2 || dims(1) < 1 || dims(2) < 1
    info.Status = "rx_grid_not_resource_grid";
    return;
end
K = double(dims(1));
L = double(dims(2));
refInd = double(refInd(:));
refSym = refSym(:);
assert(numel(refInd)==numel(refSym), ...
    'sixgr:phy:rx:ReferenceCFOShapeMismatch', ...
    'Every installed reference index requires exactly one reference symbol.');
assert(isreal(refInd) && all(isfinite(refInd) & refInd>=1 & refInd==fix(refInd)), ...
    'sixgr:phy:rx:ReferenceCFOInvalidIndex', ...
    'Reference indices must be positive finite one-based integers.');
assert(all(isfinite(real(refSym)) & isfinite(imag(refSym))), ...
    'sixgr:phy:rx:ReferenceCFOInvalidSymbol', ...
    'Installed references must be finite; do not drop an unknown port from its pilot mixture.');
% Native codebook DM-RS is expressed on physical ports. Precoding may
% produce a known zero on an inactive port even though the resource has
% nonzero pilot energy on another port. Retain every such zero in the
% complete mixture. It is neither missing evidence nor an observation of
% that port's channel. Entirely zero mixtures cannot identify frequency.
assert(numel(unique(refInd))==numel(refInd), ...
    'sixgr:phy:rx:ReferenceCFODuplicateIndex', ...
    'A logical reference RE cannot have multiple reference symbols.');
groups=options.ReferenceGroupIDs;
if isempty(groups)
    groups=zeros(size(refInd));
end
assert(isnumeric(groups) && isreal(groups) && numel(groups)==numel(refInd) && ...
    all(isfinite(groups(:)) & groups(:)>=0 & groups(:)==fix(groups(:))), ...
    'sixgr:phy:rx:ReferenceCFOInvalidGroups', ...
    'ReferenceGroupIDs must identify one installed nonnegative integer group per reference.');
[~,~,groups]=unique(double(groups(:)));
physicalRE=mod(refInd-1,K*L)+1;
[~,~,physicalGroup]=unique(physicalRE);
assert(all(accumarray(physicalGroup,groups,[],@min)== ...
    accumarray(physicalGroup,groups,[],@max)), ...
    'sixgr:phy:rx:ReferenceCFOOverlappingGroups', ...
    'Distinct channel/beam resources cannot be treated as isolated mixtures on the same physical RE.');

numRefPorts = max(1, ceil(max(refInd) / max(K * L, 1)));
[kSub, lSub, pSub] = ind2sub([K, L, numRefPorts], refInd);
valid = kSub >= 1 & kSub <= K & lSub >= 1 & lSub <= L;
kSub = kSub(valid);
lSub = lSub(valid);
pSub = pSub(valid);
refSym = refSym(valid);
groups = groups(valid);
if isempty(kSub)
    info.Status = "reference_indices_outside_grid";
    return;
end

% A common received amplitude scale contains no timing/frequency authority.
% Remove it before products so absolute RX power cannot underflow a valid
% correlation or hit an arbitrary dimensionful epsilon gate.
finiteGrid=isfinite(real(rxGrid)) & isfinite(imag(rxGrid));
amplitude=max(abs(rxGrid(finiteGrid)),[],'all');
if isempty(amplitude) || amplitude==0
    info.Status="no_received_reference_energy";
    return;
end
rxGrid=rxGrid/amplitude;

symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz, L);
if numel(symbolTimes) < L
    info.Status = "symbol_times_unavailable";
    return;
end

uniqueSymbols = unique(lSub(:));
[pairFreqHz, pairInfo] = localPairwiseCommonREEstimate(rxGrid, refSym, kSub, lSub, pSub, groups, uniqueSymbols, symbolTimes);
if logical(pairInfo.EstimateAvailable)
    info.EstimateAvailable = true;
    info.EstimatedCFO_Hz = double(pairFreqHz);
    info.Status = "OK";
    info.Source = "reference_symbol_common_re_phase_slope";
    info.NumReferenceRE = double(numel(refInd));
    info.NumSymbolsUsed = double(pairInfo.NumSymbolsUsed);
    info.SymbolIndices = double(pairInfo.SymbolIndices(:));
    info.SampleRate_Hz = double(sampleRateHz);
    info.NumSymbolPairsUsed = double(pairInfo.NumSymbolPairsUsed);
    info.NumCommonRESamplesUsed = double(pairInfo.NumCommonRESamplesUsed);
    info.AcquisitionInterval_Hz = pairInfo.AcquisitionInterval_Hz;
    info.PairPhaseWrapIntegers = pairInfo.PairPhaseWrapIntegers;
    info.PairTimeSeparations_s = pairInfo.PairTimeSeparations_s;
    info.PairPhaseFitResidual_rad = pairInfo.PairPhaseFitResidual_rad;
    info.NumReferenceGroups = double(numel(unique(groups)));
    info.NumRejectedPilotMixtures = pairInfo.NumRejectedPilotMixtures;
    info.PilotPairAuthority = "same_installed_resource_and_proportional_complete_port_vector";
    info.FrequencyEvidenceRole = "common_frequency_includes_channel_phase_evolution";
    freqHz = double(pairFreqHz);
    return;
end

% Different frequency/port supports have different unknown channel phases.
% Their separate complex means cannot identify a common-frequency slope.
% Do not rescue a missing matched-pilot observation with that assumption.
info.NumReferenceRE = double(numel(refInd));
info.NumSymbolsUsed = double(numel(uniqueSymbols));
info.SymbolIndices = double(uniqueSymbols(:) - 1);
info.SampleRate_Hz = double(sampleRateHz);
info.NumReferenceGroups = double(numel(unique(groups)));
info.NumRejectedPilotMixtures = pairInfo.NumRejectedPilotMixtures;
info.Status = "no_usable_matched_reference_pairs";
if numel(uniqueSymbols)<2
    info.Status = "fewer_than_two_reference_symbol_times";
end
end

function [freqHz, info] = localPairwiseCommonREEstimate(rxGrid, refSym, kSub, lSub, pSub, groups, uniqueSymbols, symbolTimes)
freqHz = NaN;
info = struct( ...
    "EstimateAvailable", false, ...
    "NumSymbolPairsUsed", 0, ...
    "NumCommonRESamplesUsed", 0, ...
    "NumSymbolsUsed", 0, ...
    "SymbolIndices", zeros(0, 1), ...
    "NumRejectedPilotMixtures", 0);
if numel(uniqueSymbols) < 2
    return;
end
K = size(rxGrid, 1);
L = size(rxGrid, 2);
received=reshape(rxGrid,K*L,[]);
% Each physical RE is one received mixture, not one independent observation
% per logical port. Build the complete known pilot vector before matching.
keys=double(kSub)+double(K)*(double(groups)-1);
referenceRows=cell(numel(uniqueSymbols),1);
referenceMatrices=cell(numel(uniqueSymbols),1);
for n=1:numel(uniqueSymbols)
    mask=lSub==uniqueSymbols(n);
    referenceRows{n}=unique(keys(mask));
    referenceMatrices{n}=sparse(keys(mask),double(pSub(mask)),double(refSym(mask)), ...
        K*max(groups),max(pSub));
end
pilotTolerance=64*double(eps(class(refSym)));
pairPhase = zeros(0, 1);
pairSeparation = zeros(0, 1);
pairWeight = zeros(0, 1);
symbolsUsed = false(numel(uniqueSymbols), 1);
for ia = 1:numel(uniqueSymbols)-1
    l1 = uniqueSymbols(ia);
    for ib = ia+1:numel(uniqueSymbols)
        l2 = uniqueSymbols(ib);
        dt = double(symbolTimes(l2) - symbolTimes(l1));
        if ~(isfinite(dt) && dt > 0)
            continue;
        end
        common=intersect(referenceRows{ia},referenceRows{ib});
        if isempty(common)
            continue;
        end
        a=referenceMatrices{ia}(common,:);
        b=referenceMatrices{ib}(common,:);
        [~,anchorPort]=max(abs(a),[],2);
        anchorIndex=sub2ind(size(a),(1:numel(common)).',full(anchorPort));
        r1=full(a(anchorIndex)); r2=full(b(anchorIndex));
        candidates=r1~=0 & r2~=0;
        match=false(size(common));
        if any(candidates)
            aa=spdiags(1./r1(candidates),0,nnz(candidates),nnz(candidates))*a(candidates,:);
            bb=spdiags(1./r2(candidates),0,nnz(candidates),nnz(candidates))*b(candidates,:);
            match(candidates)=full(sum(abs(aa-bb),2)) <= ...
                pilotTolerance*full(sum(abs(aa)+abs(bb),2));
        end
        info.NumRejectedPilotMixtures=info.NumRejectedPilotMixtures+nnz(~match);
        if ~any(match), continue; end
        subcarrier=mod(common(match)-1,K)+1;
        h1=received(subcarrier+K*(l1-1),:)./r1(match);
        h2=received(subcarrier+K*(l2-1),:)./r2(match);
        cross=h2.*conj(h1);
        cross=cross(isfinite(real(cross)) & isfinite(imag(cross)) & abs(cross)>0);
        sampleCount=numel(cross);
        corrSum=sum(cross,'all');
        if sampleCount < 1 || ~(isfinite(real(corrSum)) && isfinite(imag(corrSum))) || abs(corrSum) == 0
            continue;
        end
        pairPhase(end+1, 1) = angle(corrSum); %#ok<AGROW>
        pairSeparation(end+1, 1) = dt; %#ok<AGROW>
        pairWeight(end+1, 1) = abs(corrSum) * double(sampleCount); %#ok<AGROW>
        symbolsUsed(ia) = true;
        symbolsUsed(ib) = true;
        info.NumSymbolPairsUsed = double(info.NumSymbolPairsUsed) + 1;
        info.NumCommonRESamplesUsed = double(info.NumCommonRESamplesUsed) + double(sampleCount);
    end
end
validPair = isfinite(pairPhase) & isfinite(pairSeparation) & ...
    pairSeparation>0 & isfinite(pairWeight) & pairWeight>0;
if ~any(validPair)
    return;
end
pairPhase = pairPhase(validPair);
pairSeparation = pairSeparation(validPair);
pairWeight = pairWeight(validPair);
shortest = min(pairSeparation);
candidates = find(pairSeparation==shortest);
[~,best] = max(pairWeight(candidates));
anchor = candidates(best);
anchorHz = pairPhase(anchor)/(2*pi*shortest);
% Lift all pair phases to the same alias branch before a weighted phase-
% versus-time fit. An average of individually wrapped frequencies is wrong
% even for noiseless static channels. The interval is an acquisition
% assumption, not evidence that a larger unknown offset can be identified.
wraps = round(anchorHz*pairSeparation-pairPhase/(2*pi));
liftedPhase = pairPhase+2*pi*wraps;
pairWeight = pairWeight/max(pairWeight);
freqHz = sum(pairWeight.*pairSeparation.*liftedPhase)/ ...
    (2*pi*sum(pairWeight.*pairSeparation.^2));
halfWidth = .5/shortest;
if ~isfinite(freqHz) || abs(freqHz) >= halfWidth
    freqHz = NaN;
    return;
end
info.EstimateAvailable = true;
info.NumSymbolsUsed = double(sum(symbolsUsed));
info.SymbolIndices = double(uniqueSymbols(symbolsUsed) - 1);
info.AcquisitionInterval_Hz = [-halfWidth halfWidth];
info.PairPhaseWrapIntegers = wraps;
info.PairTimeSeparations_s = pairSeparation;
info.PairPhaseFitResidual_rad = liftedPhase-2*pi*freqHz*pairSeparation;
end

function sampleRate = localCarrierSampleRate(carrier)
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
sampleRate = double(sampling.SampleRateHz);
end

function symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz, symbolsPerSlot)
validateattributes(symbolsPerSlot, {'numeric'}, ...
    {'scalar','integer','positive','finite'});
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
if double(symbolsPerSlot) ~= double(sampling.SymbolsPerSlot)
    error("sixgr:phy:frame:InconsistentOFDMNumerology", ...
        "Reference grid has %d symbols, while the canonical carrier has %d.", ...
        symbolsPerSlot, sampling.SymbolsPerSlot);
end
symbolLengths = double(sampling.Nfft) + ...
    double(sampling.CyclicPrefixLengthsPerSlot(:));
if abs(double(sampleRateHz) - double(sampling.SampleRateHz)) > ...
        max(1e-9 * double(sampling.SampleRateHz), 1e-6)
    error("sixgr:phy:frame:InconsistentOFDMSampleRate", ...
        "Reference-symbol timing sample rate %.15g Hz differs from the " + ...
        "canonical carrier rate %.15g Hz.", ...
        sampleRateHz, sampling.SampleRateHz);
end
symbolTimes = (cumsum(symbolLengths) - 0.5 .* symbolLengths) ./ ...
    double(sampling.SampleRateHz);
end
