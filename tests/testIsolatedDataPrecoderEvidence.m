function ok=testIsolatedDataPrecoderEvidence()
% Real DL/UL channel execution and exact joint matrix/pattern archives.
setup6GRSimToolkit('Verbose',false);
oldRNG=rng; restore=onCleanup(@()rng(oldRNG)); %#ok<NASGU>
root=fullfile(pwd,'results','lls','isolated_precoder_evidence', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd,'simulator','configs','fixtures','lls_result_richness.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
cfg=sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,1,1);
cfg.lls6g.userContext.UEIndex=1;
cfg.outputs.phySignalDiagnosticEnabled=false;
assert(cfg.outputs.antennaPatternSamplesEnabled);
save(fullfile(root,'configuration.mat'),'cfg');
fprintf('ISOLATED_PRECODER_EVIDENCE_ROOT=%s\n',root);
raw=struct('DL',table(),'UL',table());
allObservedRE=table();
for direction=["DL","UL"]
    for snr=[18 30]
        rng(530901,'twister');
        if direction=="DL"
            out=sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',1,'SNR_dB',snr);
        else
            out=sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',1,'SNR_dB',snr);
        end
        T=out.TrialTable;
        re=sixgr.truth.bindIndependentREObservation(out.ObservedREAllocationTable);
        save(fullfile(root,lower(direction)+'_'+string(snr)+'_observed_re.mat'),'re');
        assert(~isempty(re) && all(re.ConfiguredSNR_dB==snr) && all(re.Seed==T.Seed) && ...
            all(re.TrialIndex==1) && all(re.absolute_slot==T.Slot-1), ...
            'Executed occupancy must retain the actual trial, SNR and local slot.');
        assert(numel(unique(re.ObservationID))==1 && all(re.ObservationUEIndex==T.UEIndex));
        if any(re.channel=="CSI-RS")
            assert(all(isnan(re.ue_id(re.channel=="CSI-RS"))), ...
                'The observation identity must not convert cell CSI-RS to a UE-owned allocation.');
        end
        if isempty(allObservedRE), allObservedRE=re; else, allObservedRE=[allObservedRE;re]; end %#ok<AGROW>
        assert(height(T)==1 && ~T.Crash, ...
            'test:AppliedPrecoderExecutionFailed','%s',char(strjoin(string(T.Notes),' | ')));
        assert(strlength(T.AppliedDataPrecoderTransmissionID)>0);
        assert(T.CFOCorrectionApplied && isfinite(T.CFOCorrectionApplied_Hz) && ...
            T.ResidualCFOEstimateAvailable && isfinite(T.ResidualCFO_EstimatedPostCorrection_Hz) && ...
            strlength(T.ResidualCFOEstimateSource)>0 && ...
            T.ResidualCFOEstimateDomain=="receiver_measured_common_frequency_after_correction", ...
            'test:MissingReceivedCFOEvidence', ...
            '%s must export its executed correction and independent post-correction estimate.',direction);
        assert(startsWith(T.ResidualCFOEstimateSource,"dmrs_reference_symbol_phase_slope_"), ...
            'Both receivers must honor the configured DM-RS estimator for residual frequency.');
        assert(abs(T.ResidualCFO_PostCorrection_Hz-(T.InjectedCFO_Hz-T.CFOCorrectionApplied_Hz))<1e-9, ...
            'Keep the simulator scoring residual separate from the receiver estimate.');
        raw.(direction)=[raw.(direction);T];
        fprintf('%s SNR=%g CRC=%d applied_matrix=%s\n', ...
            direction,snr,T.CRCPass,T.AppliedDataPrecoderTransmissionID);
    end
    sixgr.util.csvWriteTable(fullfile(root,lower(direction)+'_trials.csv'), ...
        raw.(direction),'PreserveSchema',true,'RoundTripNumericText',true);
    live=sixgr.truth.exportLLSLiveSignalChainTables( ...
        fullfile(root,lower(direction)+'_live'),raw.(direction),table(), ...
        struct('FinalSnapshot',true));
    for path=[string(live.ChannelStateTracePath),string(live.StageTracePath)]
        stored=sixgr.util.csvReadTable(path,'TextType','string');
        for name=["CFOCorrectionApplied_Hz","ResidualCFO_EstimatedPostCorrection_Hz"]
            assert(all(abs(stored.(name)-raw.(direction).(name))<= ...
                1e-12*max(1,abs(raw.(direction).(name)))), ...
                'Live exports must retain the receiver value rather than a simulation-reference residual.');
        end
        assert(isequal(string(stored.ResidualCFOEstimateSource),raw.(direction).ResidualCFOEstimateSource));
    end
    disabled=cfg; disabled.outputs.antennaPatternSamplesEnabled=false;
    rng(530901,'twister');
    if direction=="DL"
        baseline=sixgr.link.runDLPDSCHThroughput(disabled,'NumFrames',1,'SNR_dB',30);
    else
        baseline=sixgr.link.runULPUSCHThroughput(disabled,'NumFrames',1,'SNR_dB',30);
    end
    for name=["CRCPass","BitErrors","BitsCompared","TBSize_bits","GoodBits","EVM_rms","PostEqSINR_dB", ...
            "CFOCorrectionApplied_Hz","ResidualCFO_EstimatedPostCorrection_Hz","ResidualCFOEstimateSource"]
        assert(isequaln(T.(name),baseline.TrialTable.(name)), ...
            'test:AppliedPrecoderChangedReception', ...
            'Angular capture must not change %s %s.',direction,name);
    end
    assert(~ismember('AppliedDataPrecoderTransmissionID',baseline.TrialTable.Properties.VariableNames), ...
        'Disabled capture must not create executed-pattern claims.');
end
paths=sixgr.report.exportIsolatedDataPrecoderArchives(root,raw.DL,raw.UL);
assert(numel(unique(allObservedRE.ObservationID))==4);
[deduped,nRemoved]=sixgr.truth.deduplicateObservedREAllocation([allObservedRE;allObservedRE]);
assert(height(deduped)==height(allObservedRE) && nRemoved==height(allObservedRE));
layout=sixgr.report.resultLayout(root);
sixgr.truth.writeObservedREAllocationArtifacts(deduped,cfg,layout);
restored=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'live_re_allocation_snapshot.csv'), ...
    'TextType','string');
assert(height(restored)==height(allObservedRE) && ...
    isequal(restored.ObservationID,allObservedRE.ObservationID) && ...
    isequal(restored.re_count,allObservedRE.re_count), ...
    'One joint RE CSV must preserve all actual DL/UL/SNR observations.');
weightsHash=string(sixgr.phy.waveform.WaveformHash.file(paths.WeightsCSV));
patternsHash=string(sixgr.phy.waveform.WaveformHash.file(paths.PatternsCSV));
% The actual recovery path calls this same exporter after canonicalization.
% Repeated publication must preserve the executed binary64 matrix, including
% an unavailable shared-grant context, without changing any original archive.
sixgr.truth.sanitizeLLSArtifactCSVs(root);
recovered=sixgr.report.exportIsolatedDataPrecoderArchives(root,raw.DL,raw.UL);
assert(string(sixgr.phy.waveform.WaveformHash.file(recovered.WeightsCSV))==weightsHash && ...
    string(sixgr.phy.waveform.WaveformHash.file(recovered.PatternsCSV))==patternsHash, ...
    'test:AppliedPrecoderRecoveryChanged','Repeated recovery changed exact executed beam evidence.');
w=sixgr.util.csvReadTable(paths.WeightsCSV,'TextType','string');
p=sixgr.util.csvReadTable(paths.PatternsCSV,'TextType','string');
assert(numel(unique(w.TransmissionID))==4 && ...
    isequal(unique(w.TransmissionID),unique(p.TransmissionID)));
assert(isequal(sort(unique(w.ConfiguredSNR_dB)),[18;30]) && ...
    all(w.ExecutionScope=="independent_link_execution") && ...
    ~any(w.SameScenarioInPathEligible) && ~any(p.OverTheAirMeasurement));
for id=unique(w.TransmissionID).'
    rows=w(w.TransmissionID==id,:);
    W=complex(zeros(max(rows.ElementIndex0)+1,max(rows.LayerIndex0)+1));
    for k=1:height(rows)
        W(rows.ElementIndex0(k)+1,rows.LayerIndex0(k)+1)= ...
            complex(rows.WeightReal(k),rows.WeightImag(k));
    end
    assert(all(rows.MatrixSHA256==sixgr.phy.mimo.MatrixContract.digest(W)), ...
        'test:AppliedPrecoderRoundTrip','Joint CSV must preserve the executed complex matrix exactly.');
end
bad=raw.DL; bad.SNR_dB(1)=bad.SNR_dB(1)+1;
try
    sixgr.report.exportIsolatedDataPrecoderArchives(root,bad,raw.UL);
    error('test:ExpectedFailure','Mismatched trial identity was accepted.');
catch err
    assert(strcmp(err.identifier,'sixgr:report:AppliedPrecoderTrialMismatch'));
end
ok=true;
end
