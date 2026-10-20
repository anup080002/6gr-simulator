function ok=testPHYDiagnosticWaveformWindow()
% Actual DL/UL coded trials: display capture must not change PHY execution.
% A 100-MHz carrier with 24 allocated PRBs, not full-band qualification.
setup6GRSimToolkit('Verbose',false);
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
runFolder=fullfile(pwd,'results','lls','phy_signal_window_repair',stamp);
sixgr.util.ensureFolder(runFolder);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    fullfile(pwd,'simulator','configs','fixtures','lls_result_richness.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,runFolder);
% Match the production runner's artifact ownership. Enabled applied-
% precoder evidence must not be disabled to hide a missing fixture root.
cfg.run.rootRunFolder=runFolder;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
% This test checks bounded waveform clocks, not a second full-grid export.
cfg.outputs.phySignalDiagnosticFullChannelGrid=false;
cfg.outputs.phySignalDiagnosticEnabled=true;
% The fixture requests executed array/precoder exports. Install the same
% configured arrays as the runtime before calling the independent PHY APIs;
% do not fabricate an array after the waveform has executed.
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,runFolder,multi,struct(),1);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
save(fullfile(runFolder,'configuration.mat'),'cfg');
fprintf('PHY_WINDOW_EVIDENCE_ROOT=%s\n',runFolder);
captured=struct(); uncaptured=struct();
for direction=["DL","UL"]
    if direction=="DL", runner=@sixgr.link.runDLPDSCHThroughput;
    else, runner=@sixgr.link.runULPUSCHThroughput; end
    [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,direction);
    with=runner(bound,'NumFrames',1,'SNR_dB',30);
    withoutCfg=bound; withoutCfg.outputs.phySignalDiagnosticEnabled=false;
    without=runner(withoutCfg,'NumFrames',1,'SNR_dB',30);
    captured.(direction)=with; uncaptured.(direction)=without;
    save(fullfile(runFolder,'physical_trials.mat'),'captured','uncaptured','-v7.3');
    assert(height(with.TrialTable)==1 && height(without.TrialTable)==1 && ...
        with.TrialTable.CRCPass && without.TrialTable.CRCPass, ...
        'The declared 30-dB coded trial must decode with and without diagnostics.');
    for field=["CRCPass","BitErrors","BitsCompared","TBSize_bits","EVM_rms", ...
            "PostEqSINR_dB","AppliedTimingCorrection_samples","EstimatedCFO_Hz"]
        assert(ismember(field,string(with.TrialTable.Properties.VariableNames)), ...
            'Required physical comparison column is missing: %s',field);
        assert(isequaln(with.TrialTable.(field),without.TrialTable.(field)), ...
            'Diagnostic capture changed physical evidence: %s %s',direction,field);
    end
    snapshot=with.SignalDiagnostic;
    assert(snapshot.Available,'Actual coded trial must retain diagnostic arrays.');
    assert(snapshot.Metadata.OFDMFFTLength==4096 && snapshot.Metadata.FFTLength==1024, ...
        'Actual 100-MHz modulator FFT and bounded diagnostic FFT must remain distinct.');
    T=snapshot.SourceTable;
    tx=T(T.Panel=="time_domain" & T.Series=="tx",:);
    rx=T(T.Panel=="time_domain" & T.Series=="rx",:);
    post=T(T.Panel=="time_domain" & T.Series=="post_channel",:);
    cp=T(T.Panel=="ofdm_symbol_cp_samples",:);
    assert(isequal(tx.SampleIndex,rx.SampleIndex) && isequal(tx.SampleIndex,post.SampleIndex) && ...
        isequal(tx.SampleIndex,cp.SampleIndex) && all(diff(tx.SampleIndex)==1), ...
        'DL/UL waveform, post-channel preview and OFDM ownership must share one original sample clock.');
    assert(any(abs(complex(tx.IValue,tx.QValue))>0) && ...
        any(abs(complex(post.IValue,post.QValue))>0));
    assert(all(cp.UsefulSymbolLength_samples==4096));
    spectrum=T(T.Panel=="spectrum" & T.Series=="tx",:);
    assert(any(isfinite(spectrum.YValue)) && max(spectrum.YValue)>-100);
    if direction=="DL"
        assert(tx.SampleIndex(1)>1,'Scheduled PDSCH starts after silent control symbols.');
    end
    fprintf('PHY_WINDOW_RUNTIME_PASS %s start=%d samples=%d OFDM_FFT=%d diagnostic_FFT=%d CRC=1 unchanged_PHY=1\n', ...
        direction,tx.SampleIndex(1),height(tx),snapshot.Metadata.OFDMFFTLength,snapshot.Metadata.FFTLength);
end
artifacts=sixgr.truth.exportPHYSignalDiagnostic(runFolder,cfg, ...
    struct('DL',captured.DL.SignalDiagnostic,'UL',captured.UL.SignalDiagnostic),true);
save(fullfile(runFolder,'artifact_receipt.mat'),'artifacts','-v7.3');
assert(artifacts.DLAvailable && artifacts.ULAvailable && ...
    isfile(artifacts.DLImage) && isfile(artifacts.ULImage));
ok=true;
end
