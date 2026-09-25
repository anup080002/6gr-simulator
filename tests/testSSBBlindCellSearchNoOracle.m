function ok = testSSBBlindCellSearchNoOracle()
%TESTSSBBLINDCELLSEARCHNOORACLE PCI must come from received PSS/SSS, not cfg.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end

cfgTx = sixgr.config.defaultConfig();
cfgTx.phy.carrier.NCellID = 17;
cfgTx.phy.carrier.SubcarrierSpacing = 30;
cfgTx.phy.carrier.SubcarrierSpacing_kHz = 30;
cfgTx.phy.carrier.NSizeGrid = 273;

[txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfgTx, "NumSubframes", 2);

cfgRx = cfgTx;
cfgRx.phy.carrier.NCellID = 999;
cfgRx.phy.NCellID = 999;

[rxSSBGrid, sync] = sixgr.phy.dl.SSB_Rx(txWave, cfgRx, ...
    "SampleRate_Hz", txInfo.SampleRate_Hz);
assert(double(sync.NID2) == 2, "PSS search must recover NID2=2 for transmitted PCI 17.");
assert(double(sync.NID1) == 5, "SSS search must recover NID1=5 for transmitted PCI 17.");
assert(double(sync.NCellID) == 17, ...
    "SSB_Rx must recover physical cell ID from waveform, not cfg.phy.carrier.NCellID.");
assert(~logical(sync.ConfiguredCellIDUsed), "SSB_Rx must not consume configured cell ID.");
assert(string(sync.NCellIDSource) == "blind_pss_sss_correlation", ...
    "SSB_Rx must report blind PSS/SSS PCI recovery as the cell-ID source.");
assert(sync.PSSDetectionDecision.Detected && sync.SSSDetectionDecision.Detected);
assert(sync.PSSDetectionDecision.NormalizedMetric>sync.PSSDetectionDecision.Threshold);
assert(sync.SSSDetectionDecision.NormalizedMetric>sync.SSSDetectionDecision.Threshold);
assert(sync.SSSDetectionDecision.HypothesisCount==336*sync.PSSDetectionDecision.HypothesisCount);

[pbch, ~] = sixgr.phy.dl.PBCH_Recovery(rxSSBGrid, sync, cfgRx);
assert(logical(pbch.Ok), "PBCH decode must pass using the blind recovered PCI.");
assert(double(pbch.NCellID) == 17, "PBCH recovery must use the blind recovered PCI.");
% Strong, genuinely transmitted PSS with absent SSS must pass the first
% gate and fail the SSS gate; a PSS-only test cannot qualify cell detection.
first=round(sync.TimingOffset)+1;
symbolWithinSlot=mod(sync.SelectedCandidateStartSymbol,14);
count=sync.Nfft+sync.CyclicPrefixLengthsPerSlot(symbolWithinSlot+1);
last=first+count-1;
assert(first>=1 && last<=size(txWave,1));
pssOnly=zeros(size(txWave),'like',txWave);
pssOnly(first:last,:)=txWave(first:last,:);
power=mean(abs(pssOnly(first:last,:)).^2,'all');
stream=RandStream('mt19937ar','Seed',382171);
noise=sqrt(power/2000)*complex(randn(stream,size(pssOnly)),randn(stream,size(pssOnly)));
rejected=false;
try
    sixgr.phy.dl.SSB_Rx(pssOnly+noise,cfgRx,'SampleRate_Hz',txInfo.SampleRate_Hz);
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:ia:SSBNotDetected') && ...
        contains(cause.message,'SSS normalized correlation'), ...
        'Expected the independent SSS gate, got %s: %s',cause.identifier,cause.message);
    rejected=true;
end
assert(rejected,'PSS alone must not become a detected cell.');
result=sixgr.phy.broadcast.recoverSIB1FromWaveform(pssOnly+noise,cfgRx,'RecoveryScope','SSB_MIB');
assert(result.PSSDetected && ~result.SSSDetected && ~result.DecodeAttempted && ~result.Crash);
assert(result.PSSDetectionDecisionAvailable && result.SSSDetectionDecisionAvailable);
assert(result.PSSNormalizedMetric>result.PSSDetectionThreshold && ...
    result.SSSNormalizedMetric<=result.SSSDetectionThreshold);
assert(result.DetectionStage=="SSS" && result.DetectionMetric==result.SSSNormalizedMetric);
fprintf('SSB_BLIND_DETECTION_PASS signal_present_PBCH=1 PSS_only_SSS_rejected=1\n');
ok = true;
end
