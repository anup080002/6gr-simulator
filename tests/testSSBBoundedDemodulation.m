function ok = testSSBBoundedDemodulation()
% Bound FFT work, not the blind search or the received observation.
% H4 4-GHz/100-MHz waveform component; not end-to-end scenario acceptance.
setup6GRSimToolkit('Verbose',false);
scenario = sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_adaptive.yaml');
cfg = sixgr.lls6g.buildInternalConfig(scenario,tempname);
[burst,~,tx] = sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',1);
fs = tx.SampleRate_Hz;
assert(fs==122.88e6 && size(burst,2)==64 && cfg.phy.fc_Hz==4e9);
% Do not let the configured PCI supply the detected cell identity.
rxCfg = cfg;
rxCfg.phy.carrier.NCellID = mod(double(tx.NCellID)+137,1008);
rxCfg.phy.NCellID = rxCfg.phy.carrier.NCellID;
maximumError = 0;
for ssbIndex = 0:3
    % The long observation includes a nonempty unrelated tail. Cropping
    % only the FFT input must leave all blind search decisions unchanged.
    wave = [burst(:,1:4); repmat(burst(:,1:4),6,1)];
    wave = [zeros(7,4,'like',wave); wave];
    [grid,sync] = sixgr.phy.dl.SSB_Rx(wave,rxCfg, ...
        'SampleRate_Hz',fs,'CandidateSSBIndex',ssbIndex);
    reference = legacyFullTailGrid(wave,sync);
    relativeError = norm(grid(:)-reference(:))/norm(reference(:));
    maximumError = max(maximumError,relativeError);
    assert(relativeError<1e-12 && sync.NCellID==tx.NCellID && ...
        ~sync.ConfiguredCellIDUsed && sync.PSSDetected && sync.SSSDetected);
    assert(sync.SSBDemodulationSampleCount<fs*1e-3 && ...
        sync.SSBDemodulationSymbolCount==sync.SSBSymbolColumnsOneBased(end));
    [pbch,~] = sixgr.phy.dl.PBCH_Recovery(grid,sync,rxCfg);
    assert(pbch.Ok,'Bounding unused FFT symbols must preserve PBCH decoding.');
end

% The TX power-measurement caller has 64 physical branches, not four UE
% branches. Compare its complete output with native full-tail demodulation.
[grid,sync] = sixgr.phy.dl.SSB_Rx(burst,rxCfg, ...
    'SampleRate_Hz',fs,'CandidateSSBIndex',3);
reference = legacyFullTailGrid(burst,sync);
relativeError = norm(grid(:)-reference(:))/norm(reference(:));
assert(size(grid,3)==64 && relativeError<1e-12);
maximumError = max(maximumError,relativeError);

% Keep the independent fine-CFO calculation and actual sample clock.
rxCfg.phy.sync.fineCFOEnabled = true;
received = burst(:,1:4).*exp(2i*pi*400*(0:size(burst,1)-1)'/fs);
[grid,sync] = sixgr.phy.dl.SSB_Rx(received,rxCfg, ...
    'SampleRate_Hz',fs,'CandidateSSBIndex',0);
reference = legacyFullTailGrid(received,sync);
assert(norm(grid(:)-reference(:))/norm(reference(:))<1e-12 && ...
    abs(sync.FreqOffset_Hz-400)<1e-6);

% An incomplete block cannot be made complete by padding future samples.
rxCfg.phy.sync.fineCFOEnabled = false;
first = round(sync.TimingOffset)+1;
within = mod(sync.SelectedCandidateStartSymbol,14);
last = first + sum(sync.Nfft+sync.CyclicPrefixLengthsPerSlot(within+(1:2)))-1;
rejected = false;
try
    sixgr.phy.dl.SSB_Rx(burst(1:last,1:4),rxCfg, ...
        'SampleRate_Hz',fs,'CandidateSSBIndex',0);
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:ia:SSBNotDetected'), ...
        'Unexpected truncated-block exception: %s',cause.identifier);
    rejected = true;
end
assert(rejected,'Truncated four-symbol evidence must remain rejected.');
fprintf('SSB_BOUNDED_DEMODULATION_PASS long_4rx=4 short_64port=1 fine_cfo=1 max_relative_error=%.3g\n',maximumError);
ok = true;
end

function grid = legacyFullTailGrid(wave,sync)
% Independent native-Toolbox reference for the pre-repair full-tail path.
fs = double(sync.SampleRate_Hz);
n = (0:size(wave,1)-1)';
corrected = wave.*exp(-2i*pi*(double(sync.SSBCenterFrequencyOffsetHz)/fs)*n);
corrected = corrected.*exp(-2i*pi*(double(sync.FreqOffset_Hz)/fs)*n);
within = mod(double(sync.SelectedCandidateStartSymbol),14);
prefix = sum(double(sync.CyclicPrefixLengthsPerSlot(1:within))+sync.Nfft);
first = 1+max(0,round(sync.TimingOffset))-prefix;
if first>=1
    aligned = corrected(first:end,:);
else
    aligned = [zeros(1-first,size(corrected,2),'like',corrected);corrected];
end
carrier = nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',sync.SCS_SSB_kHz, ...
    'NSlot',sync.DemodulationSlot);
full = nrOFDMDemodulate(carrier,aligned,'Nfft',sync.Nfft,'SampleRate',fs, ...
    'CarrierFrequency',sync.SymbolPhaseCompensationCarrierFrequencyHz, ...
    'CyclicPrefixFraction',0.5);
grid = full(:,sync.SSBSymbolColumnsOneBased,:);
end
