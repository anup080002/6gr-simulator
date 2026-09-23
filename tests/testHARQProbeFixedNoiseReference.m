function ok = testHARQProbeFixedNoiseReference()
% Isolated coded DL/UL probe: fixed noise reference must not follow rank.
% This does not stand in for a shared-control scenario or a BLER campaign.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
root = fullfile(pwd,'results','lls','harq_probe_fixed_noise_reference', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
fprintf('FIXED_REFERENCE_OUTPUT=%s\n',root);
old = rng; restore = onCleanup(@()rng(old)); %#ok<NASGU>
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveFigures = false;
cfg.channel.model = 'AWGN'; cfg.channel.awgnOnly = true;
cfg.channel.bandwidth_Hz = 5e6;
cfg.channel.awgnReferenceREEnergy = .25;
cfg.channel.snr_dB = 30;
cfg.phy.carrier.NSizeGrid = 25;
cfg.phy.carrier.SubcarrierSpacing = 15;
cfg.phy.carrier.SubcarrierSpacing_kHz = 15;
cfg.phy.duplex.tddCommon = struct('ReferenceSubcarrierSpacingKHz',15, ...
    'Pattern1',struct('PeriodicityMilliseconds',5,'NumDownlinkSlots',3, ...
    'NumDownlinkSymbols',0,'NumUplinkSlots',1,'NumUplinkSymbols',0));
cfg.phy.duplex.tddDedicated = struct([]);
cfg.phy.ssb.enable = false; % no access waveform in this component test
cfg.phy.csirs.enable = false; cfg.phy.csirs.enabled = false;
cfg.phy.harq.enable = true; cfg.phy.harq.validationMode = 'observation';
cfg.phy.nTxAnt = 2; cfg.phy.nRxAnt = 2;
cfg.channel.nTxAnt = 2; cfg.channel.nRxAnt = 2;
cfg.scenario.bs.nTxAnt = 2; cfg.scenario.bs.nRxAnt = 2;
cfg.scenario.ue.nTxAnt = 2; cfg.scenario.ue.nRxAnt = 2;
cfg.run.interferenceExecutionMode = 'none';
cfg.run.noiseOperatingMode = 'standalone_awgn_snr_argument';
cfg.phy.linkAdaptation.mode = 'fixed';
for direction = ["DL", "UL"]
    if direction == "DL", key = 'pdsch'; else, key = 'pusch'; end
    cfg.phy.(key).executionProfile = 'phy_calibration';
    cfg.phy.(key).enable = true;
    cfg.phy.(key).modulation = 'QPSK';
    cfg.phy.(key).codeRate = 308/1024;
    cfg.phy.(key).mcsIndex = 4; cfg.phy.(key).mcsTable = 'qam64_table1';
    cfg.phy.(key).prbSet = 0:5;
    cfg.phy.(key).symbolAllocation = [0 10];
    cfg.phy.(key).mappingType = 'A';
    cfg.phy.(key).numPorts = 2; cfg.phy.(key).nPorts = 2;
    cfg.phy.(key).NumAntennaPorts = 2;
    cfg.phy.(key).dmrs.numCDMGroupsWithoutData = 2;
    cfg.phy.(key).transmissionScheme = 'codebook';
    cfg.phy.(key).TPMI = 0; cfg.phy.(key).PMI = 0;
    cfg.phy.(key).transformPrecoding = false;
    cfg.phy.(key).codebookType = 'codebook1_ng1n4n1';
    for rank = [1 2]
        cfg.phy.(key).numLayers = rank; cfg.phy.(key).nLayers = rank;
        cfg.phy.(key).dmrs.portSet = 0:rank-1;
        cfg.phy.(key).dmrs.DMRSPortSet = 0:rank-1;
        opt = struct('LinkSNR_dB',30,'LinkSNRGrid_dB',30, ...
            'HARQLivePreview',true,'HARQProbePackets',1, ...
            'HARQProbeDirections',direction);
        rng(220930,'twister');
        artifacts = sixgr.truth.exportLLSHARQDiagnostics(cfg, ...
            fullfile(root,sprintf('%s_rank%d',direction,rank),'air_interface'),opt);
        T = artifacts.PacketTable;
        disp(T(:,["Direction","Attempt","CurrentDecodeOK","CombinedDecodeOK", ...
            "BitErrors","BitsCompared","MeasuredSINR_dB", ...
            "SignalEnergyPerOccupiedRE","MeasuredSignalEnergyPerOccupiedRE", ...
            "GridNoiseVariance","MeasuredInjectedGridNoiseVariance"]));
        assert(~isempty(T) && all(T.CurrentDecodeOK), ...
            'Actual %s rank%d codewords must decode at the high-SNR anchor.',direction,rank);
        assert(height(T)==1 && all(T.CombinedDecodeOK) && all(T.ACK), ...
            'A passed receiver CRC must not be overturned by a second probe decoder.');
        assert(all(T.SignalEnergyPerOccupiedRE == .25), ...
            'test:HARQProbeReferenceRecalibrated', ...
            'Probe noise must use the fixed configured reference, not measured waveform/rank power.');
        assert(all(abs(T.GridNoiseVariance-.25e-3)<1e-12));
        assert(all(abs(T.AppliedNoiseSNR_dB-30)<1e-10));
        localCheckMeasuredNoise(T);
        assert(all(isfinite(T.MeasuredSINR_dB)));
        fprintf('HARQ_FIXED_REFERENCE_PASS direction=%s rank=%d reference=%g gridNoise=%g measuredPostEQ=%g\n', ...
            direction,rank,T.SignalEnergyPerOccupiedRE(1),T.GridNoiseVariance(1),T.MeasuredSINR_dB(1));
    end
end
% Exercise the real UL soft-buffer path, not an ideal ACK or a replayed
% second decoder. This fixed low-SNR point is not a BLER qualification.
opt.LinkSNR_dB = -12; opt.LinkSNRGrid_dB = -12;
rng(220931,'twister');
low = sixgr.truth.exportLLSHARQDiagnostics(cfg, ...
    fullfile(root,'UL_rank2_low_snr','air_interface'),opt);
T = low.PacketTable;
localCheckMeasuredNoise(T);
assert(height(T)>1 && any(T.HARQCombiningApplied), ...
    'The held low-SNR episode must execute a physical UL retransmission and combining.');
combined = logical(T.HARQCombiningApplied);
assert(all(isnan(T.CurrentDecodeOK(combined))) && ...
    all(~T.CurrentAttemptStandaloneCRCMeasured(combined)), ...
    'A cumulative decode cannot be relabeled as an independently measured current-attempt CRC.');
assert(all(T.HARQSoftCombiningPositionAware(combined)) && ...
    all(T.TBSize_bits==T.TBSize_bits(1)));
fprintf('HARQ_UL_COMBINING_PASS attempts=%d combined=%d\n',height(T),nnz(combined));
ok = true;
end

function localCheckMeasuredNoise(T)
% Score the actual demodulated injected-noise waveform, not just the
% requested variance or the exported SNR label. This is a bounded numerical
% regression, not a noise-detector false-alarm statistical qualification.
measured=double(T.MeasuredInjectedGridNoiseVariance);
expected=double(T.GridNoiseVariance);
assert(~isempty(measured) && all(isfinite(measured) & measured>0) && ...
    all(isfinite(expected) & expected>0), ...
    'test:HARQProbeMissingPhysicalNoise','Probe must retain measured injected grid noise.');
errorDB=10*log10(measured./expected);
assert(all(abs(errorDB)<0.5), ...
    'test:HARQProbePhysicalNoiseMismatch', ...
    'Actual probe noise differs from fixed reference by %s dB.',mat2str(errorDB.'));
fprintf('HARQ_MEASURED_NOISE_REFERENCE_PASS attempts=%d max_error_db=%.9g\n', ...
    height(T),max(abs(errorDB)));
end
