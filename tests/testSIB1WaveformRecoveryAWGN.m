function ok = testSIB1WaveformRecoveryAWGN()
%TESTSIB1WAVEFORMRECOVERYAWGN Positive waveform SIB1 path must pass.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
cfg = localCfg();
[supported, reason] = sixgr.phy.broadcast.siRNTIWaveformSupported();
assert(logical(supported), "SI-RNTI Type0 CSS waveform support must be available: %s", char(string(reason)));
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg);
assert(logical(rx.StrictOk), "Strict SIB1 waveform recovery must pass at high SNR.");
assert(rx.PBCHResidualFrequencyAvailable && isfinite(rx.PBCHResidualCommonFrequency_Hz) && ...
    ~rx.PBCHResidualFrequencyIndependentCapture, ...
    'Real BCH recovery must publish the distinct post-correction received DM-RS measurement.');
assert(rx.CFOCorrectionApplied && rx.CFOCorrectionApplied_Hz==rx.FrequencyOffsetHz && ...
    rx.CFOCorrectionSampleOrigin==0 && ...
    rx.CFOCorrectionSource=="received_PSS_CP_estimate_capture_local_sample_clock");
assert(logical(rx.StrictReceiverEvidenceOk), ...
    "Strict SIB1 recovery must include measured PBCH and SI-RNTI PDSCH receiver evidence.");
assert(isfinite(double(rx.ReceiverHestSINR_dB)) && ...
    strcmp(string(rx.ReceiverHestSINRSource), ...
        "pbch_dmrs_hest_power_over_nrChannelEstimate_noise_variance"), ...
    "PBCH recovery must export finite receiver-Hest SINR from PBCH DMRS/channel-estimate evidence.");
assert(logical(rx.PostEqSINRAvailable) && isfinite(double(rx.PostEqSINR_dB)) && ...
    strcmp(string(rx.PostEqSINRValueStatus), "OK"), ...
    "PBCH recovery must export an available finite post-equalization SINR when its required evidence exists.");
assert(logical(rx.ChannelEstimateAvailable) && logical(rx.EqualizationAvailable), ...
    "PBCH recovery must export channel-estimation and equalization evidence.");
assert(isfinite(double(rx.SIB1PDSCHReceiverHestSINR_dB)) && ...
    logical(rx.SIB1PDSCHStrictReceiverEvidenceOk), ...
    "SIB1 SI-RNTI PDSCH recovery must export receiver evidence from the actual PDSCH receiver.");
assert(logical(rx.DCIBlindDecodeSuccess) && double(rx.DCIRNTI) == 65535, "SI-RNTI DCI must decode.");
[treeEqual, compareEvidence] = sixgr.rrc.asn1.compareSIB1Trees( ...
    tx.TxTree, rx.SIB1RxTree);
assert(logical(treeEqual) && ...
    string(compareEvidence.TxTreeHash) == string(compareEvidence.RxTreeHash), ...
    "Test-side decoded SIB1 tree must equal transmitted tree.");
assert(isempty(rx.UsedOracleFields), "Receiver must not consume transmitter oracle fields before decode.");
paired=sixgr.phy.broadcast.pairPBCHReceivedSymbols(rx,tx);
assert(~isempty(paired) && numel(paired.SampleIndex)==432 && ...
    ~paired.ReceiverUsesScoringReference && ~paired.GainOrPhaseFitted);
measured=complex(paired.MeasuredReal,paired.MeasuredImag);
reference=complex(paired.ReferenceReal,paired.ReferenceImag);
assert(isequal(measured,rx.PBCHEqualizedSymbols(:)) && ...
    sqrt(sum(abs(measured-reference).^2)/sum(abs(reference).^2))<.1);
poison=tx; poison.SSBWaveInfo.ResourceGridSSBurst.ResourceGrid= ...
    -poison.SSBWaveInfo.ResourceGridSSBurst.ResourceGrid;
wrong=sixgr.phy.broadcast.pairPBCHReceivedSymbols(rx,poison);
assert(isequal(wrong.MeasuredReal,paired.MeasuredReal) && ...
    isequal(wrong.MeasuredImag,paired.MeasuredImag) && ...
    isequal(wrong.ReferenceReal,-paired.ReferenceReal), ...
    'Changing scoring reference must not change decoded or equalized receiver outputs.');
trial=table("DL",1,17,1,1,35,string(jsonencode(paired)), ...
    'VariableNames',{'Direction','UEIndex','CellID','Slot','SweepPointIndex','ConfiguredSNR_dB','ControlEVMSamplesJSON'});
exportRoot=tempname; mkdir(exportRoot);
path=sixgr.report.exportControlEVMSamples(fullfile(exportRoot,'pbch_trials.csv'),trial);
saved=readtable(path,'TextType','string');
assert(height(saved)==432 && all(saved.ConfiguredSNR_dB==35) && ...
    all(saved.SweepPointIndex==1) && all(saved.SignalName=="PBCH"));
localPublicationGuards(exportRoot,trial,paired,path);

cfgRank2 = cfg;
cfgRank2.phy.pdsch.numLayers = 2;
cfgRank2.phy.pdsch.nLayers = 2;
cfgRank2.phy.pdsch.numPorts = 8;
cfgRank2.phy.pdsch.nPorts = 8;
cfgRank2.phy.pdsch.enablePTRS = true;
cfgRank2.phy.pdsch.ptrs.enable = true;
cfgRank2.pdsch6gr.enable_ptrs = true;
cfgRank2.phy.pdsch.dmrs.portSet = [0 1];
cfgRank2.pdsch6gr.DMRSPortSet = [0 1];
cfgRank2.phy.pdsch.precoding.matrix = localRank2Precoder(8);
txRank2 = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfgRank2, "SNRdB", 35, "Seed", 1502);
rxRank2 = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    txRank2.Waveform, cfgRank2);
assert(logical(rxRank2.StrictOk), ...
    "SIB1 broadcast PDSCH must not inherit incompatible rank-2 UE-data precoding.");
assert(logical(rxRank2.StrictReceiverEvidenceOk) && isfinite(double(rxRank2.ReceiverHestSINR_dB)), ...
    "Rank-2 scenario precoding isolation must still preserve measured PBCH/SIB1 receiver evidence.");
assert(~logical(txRank2.PDSCH.EnablePTRS), ...
    "SIB1 common PDSCH must obey its own PT-RS authority, not connected-data PT-RS.");
assert(isequal(double(txRank2.PDSCH.DMRS.DMRSPortSet(:).'), 0), ...
    "SIB1 common PDSCH must use the exact single-layer DM-RS port set.");
assert(logical(cfgRank2.phy.pdsch.enablePTRS) && ...
    isequal(double(cfgRank2.phy.pdsch.dmrs.portSet), [0 1]), ...
    "SIB1 generation must not mutate connected-data reference-signal configuration.");
ok = true;
end

function localPublicationGuards(folder,trial,paired,path)
trialPath=fullfile(folder,'pbch_trials.csv');
originalHash=sixgr.util.sha256File(path);
[~,rewritten]=sixgr.report.exportControlEVMSamples(trialPath,trial);
assert(~rewritten,'An unchanged physical sample set must not be repeatedly serialized.');
changed=trial; changed.ConfiguredSNR_dB=36;
[~,rewritten]=sixgr.report.exportControlEVMSamples(trialPath,changed);
assert(rewritten && sixgr.util.sha256File(path)~=originalHash, ...
    'Sweep identity must participate in publication invalidation.');
% A malformed reference cannot hide behind a previous successful cache.
bad=paired; bad.ReceiverUsesScoringReference=true;
changed.ControlEVMSamplesJSON=string(jsonencode(bad));
try
    sixgr.report.exportControlEVMSamples(trialPath,changed);
    error('test:ExpectedRejection','A receiver-oracle reference must be rejected.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:report:ControlEVMPairAuthority'));
end
sixgr.report.exportControlEVMSamples(trialPath,trial);
% Simulate a replacement destination, not loss of raw receiver evidence.
sixgr.util.csvWriteTable(path,table(1,'VariableNames',{'Corrupt'}));
[~,rewritten]=sixgr.report.exportControlEVMSamples(trialPath,trial);
assert(rewritten && sixgr.util.sha256File(path)==originalHash, ...
    'Byte-level destination mutation must be detected and exactly repaired.');
allPoints=repmat(trial,8,1);
allPoints.SweepPointIndex=(1:8).'; allPoints.ConfiguredSNR_dB=[40;30;20;10;0;-10;-20;-30];
sixgr.report.exportControlEVMSamples(trialPath,allPoints);
joint=readtable(path,'TextType','string');
assert(height(joint)==8*432 && numel(unique(joint.SweepPointIndex))==8 && ...
    isequal(sort(unique(joint.ConfiguredSNR_dB)),sort(allPoints.ConfiguredSNR_dB)), ...
    'The writer must retain all points of a joint sample table.');
fprintf('PBCH_EVM_PUBLICATION_GUARDS_PASS joint_csv=%s\n',path);
end

function cfg = localCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.phy.pdcch.enable = true;
cfg.phy.pdcch.blindSearch = true;
cfg.phy.pdcch.dmrs.enable = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;
cfg.initial_access.type0 = struct("monitoring_occasion_ordinal",3);
cfg.initial_access.sib1.pdsch = struct("prb_start",0, ...
    "num_prb",24,"symbol_start",2,"num_symbols",12,"mcs",0,"rv",0, ...
    "ptrs_enabled",false);
cfg.phy.sib1.coreset0Index = 0;
cfg.phy.sib1.searchSpaceZero = 0;
end

function W = localRank2Precoder(nPorts)
n = (0:nPorts-1).';
W = [exp(1j * 2 * pi * n / nPorts), exp(1j * 4 * pi * n / nPorts)];
W = W ./ sqrt(sum(abs(W).^2, 1));
end
