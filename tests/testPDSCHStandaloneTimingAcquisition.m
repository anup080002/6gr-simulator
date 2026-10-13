function ok = testPDSCHStandaloneTimingAcquisition()
% Standalone data reception must acquire DM-RS timing before CFO estimation.
setup6GRSimToolkit('Verbose',false);
prior = rng; cleanup = onCleanup(@()rng(prior));
rng(82193,'twister');
cfg = localConfig();
for rankValue = [1 2]
    cfg.phy.pdsch.nLayers = rankValue;
    cfg.phy.pdsch.numLayers = rankValue;
    if rankValue==1
        precoder=[1;1i]/sqrt(2);
    else
        precoder=eye(2);
    end
    [tx,~] = sixgr.phy.dl.PDSCH_Tx(cfg,'NumTxAnt',2, ...
        'PrecodingMatrix',precoder,'ExecutionProfile','phy_calibration');
    assert(size(tx.Waveform,2)==2 && tx.PDSCH.NumLayers==rankValue, ...
        'Timing qualification must execute the declared physical ports and layers.');
    args = {'Carrier',tx.Carrier,'PDSCH',tx.PDSCH, ...
        'PDSCHIndices',tx.PDSCHIndices,'CodingPlan',tx.CodingPlans, ...
        'ExecutionProfile','phy_calibration','NoiseVar',1e-8, ...
        'NoiseVarDomain','time','PrecodingMatrix',precoder};
    fs = nrOFDMInfo(tx.Carrier).SampleRate;
    channel = [1 .12i; .15 .85*exp(.3i)];
    for cfoMethod = ["cyclic_prefix","dmrs_two_symbol"]
    for delay = [0 16 43]
        cfo = 700*(1-2*(delay==16));
        received = [complex(zeros(delay,2));tx.Waveform*channel; ...
            complex(zeros(64-delay,2))];
        received = received.*exp(1i*2*pi*cfo*(0:size(received,1)-1)'/fs);
        % Deliberately false impairment/filter metadata: estimates must be
        % functions of RX samples and receiver-known DM-RS, not these values.
        probe = cfg;
        probe.phy.impairments.cfoEstimationMethod = cfoMethod;
        probe.phy.impairments.timingOffsetSamples = 91;
        probe.phy.impairments.cfoHz = -4321;
        probe.lls6g.receiverSync.ChannelFilterDelay_samples = 300;
        % These samples have not undergone receiver alignment. A channel
        % filter-delay annotation is not permission to claim they have.
        probe.lls6g.receiverSync.RuntimeWaveformSampleAligned = false;
        [rx,~] = sixgr.phy.dl.PDSCH_Rx(received,probe,args{:});
        assert(rx.Ok && rx.TBCRCPass,'Standalone synchronized TB must decode.');
        receivedGrid=reshape(rx.OFDMGrid,[],size(rx.OFDMGrid,3));
        expectedReceived=receivedGrid(double(rx.ResourcePlan.DataIndices)+1,:);
        assert(isequal(rx.PDSCHRxSymbolsForEvidence,expectedReceived) && ...
            size(rx.PDSCHRxSymbolsForEvidence,2)==2, ...
            'Pre-EQ evidence must retain both receive antennas, independently of rank.');
        assert(size(rx.EqualizedSymbolsForEvidence,2)==rankValue, ...
            'Equalized evidence must remain in the separately declared layer domain.');
        assert(rx.RawTimingEstimate_samples==delay && ...
            rx.AppliedTimingCorrection_samples==delay && rx.TimingEstimateUsed, ...
            'DM-RS timing must acquire the actual RX offset without subtracting TX/channel metadata.');
        assert(string(rx.TimingEstimateSource)== ...
            "nrTimingEstimate_pdsch_dmrs_receiver_input");
        assert(rx.CFOCorrectionApplied && abs(rx.EstimatedCFO_Hz-cfo)<15, ...
            'Standalone CFO estimation must operate on timing-aligned samples.');
        expectedResidualSource="cyclic_prefix_post_timing_and_frequency_correction";
        if cfoMethod=="dmrs_two_symbol"
            expectedResidualSource="dmrs_reference_symbol_phase_slope_post_timing_and_frequency_correction";
        end
        assert(isfinite(rx.ResidualCFO_EstimatedPostCorrection_Hz) && ...
            abs(rx.ResidualCFO_EstimatedPostCorrection_Hz)<15 && ...
            string(rx.ResidualCFOEstimateSource)==expectedResidualSource, ...
            'The measured residual must use corrected RX samples, not poisoned injected-CFO metadata.');
        assert(abs(rx.ResidualCFO_PostCorrection_Hz-rx.ResidualCFO_EstimatedPostCorrection_Hz)>1000, ...
            'The deliberately false simulation reference must remain separate from measured residual.');
        fprintf('STANDALONE_PDSCH_TIMING_PASS rank=%d delay=%d method=%s CFO=%.3f estimated=%.3f\n', ...
            rankValue,delay,cfoMethod,cfo,rx.EstimatedCFO_Hz);
    end
    end
    % An explicit already-aligned producer must not be corrected twice.
    aligned = cfg;
    aligned.lls6g.receiverSync.RuntimeWaveformSampleAligned = true;
    aligned.phy.impairments.timingOffsetSamples = 0;
    [rx,~] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform*channel,aligned,args{:});
    assert(rx.Ok && ~rx.TimingEstimateUsed && rx.AppliedTimingCorrection_samples==0);
    assert(string(rx.TimingEstimateSource)=="runtime_aligned_waveform_no_timing_reacquisition");
    [rx,~] = sixgr.phy.dl.PDSCH_Rx(tx.Waveform*channel,cfg,args{:},'SkipTimingEstimate',true);
    assert(~rx.TimingEstimateUsed && rx.AppliedTimingCorrection_samples==0 && ...
        string(rx.TimingEstimateStatus)=="bypassed");
end
ok = true;
end

function cfg = localConfig()
cfg = sixgr.config.defaultConfig();
cfg.run.pdschExecutionProfile = 'phy_calibration';
cfg.phy.pdsch.executionProfile = 'phy_calibration';
cfg.phy.carrier.NSizeGrid = 6;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.pdsch.PRBSet = 0:5; cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.SymbolAllocation = [2 10]; cfg.phy.pdsch.symbolAllocation = [2 10];
cfg.phy.pdsch.MappingType = 'A'; cfg.phy.pdsch.mappingType = 'A';
cfg.phy.pdsch.mcsTable = 'qam64_table1'; cfg.phy.pdsch.mcsIndex = 4;
cfg.phy.pdsch.modulation = 'QPSK'; cfg.phy.pdsch.codeRate = 308/1024;
cfg.phy.pdsch.dmrs.additionalPositions = 1;
cfg.phy.pdsch.UECapability1024QAM = false; cfg.phy.pdsch.RRCEnabled1024QAM = false;
cfg.phy.pdsch.DCIEnabled1024QAM = false; cfg.phy.pdsch.DeploymentAllows1024QAM = false;
cfg.phy.pdsch.FrequencyRangeAllows1024QAM = false; cfg.phy.pdsch.BandAllows1024QAM = false;
cfg.phy.pdsch.FrequencyRange = 'FR1'; cfg.phy.pdsch.OperatingBand = 'n77';
cfg.phy.pdsch.DeploymentClass = 'macro'; cfg.phy.pdsch.DCIFormat = '1_1';
cfg.phy.csirs.enable = false; cfg.phy.csirs.enabled = false;
% This six-PRB data-receiver test contains no SS/PBCH burst. Do not inherit
% a system SSB allocation wider than the deliberately narrow data carrier.
cfg.phy.ssb.enable = false;
cfg.channel.model = 'AWGN'; cfg.channel.awgnOnly = true;
cfg.phy.rx.useIdealTimingSync = false; cfg.phy.rx.cfoCorrectionEnabled = true;
cfg.phy.impairments.cfoEstimationMethod = 'cyclic_prefix';
cfg.outputs.saveCSV = false; cfg.outputs.saveMAT = false; cfg.outputs.saveFigures = false;
end
