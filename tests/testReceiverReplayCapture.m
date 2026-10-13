function ok=testReceiverReplayCapture()
% Exact DL/UL receiver input replay; capture policy cannot change reception.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
root=fullfile(pwd,'results','lls','receiver_replay_capture', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.run.shortRun=true;
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.phy.csirs.enable=false; cfg.phy.csirs.enabled=false;
cfg.outputs.saveFigures=false; cfg.outputs.phySignalDiagnosticEnabled=false;
cfg.run.rootRunFolder=root;
cfg.outputs.receiverReplayCapturePolicy='all';
cfg.outputs.receiverReplayCaptureMaxTrials=1;
for direction=["DL","UL"]
    rng(719104,'twister'); captured=runOne(cfg,direction);
    T=captured.TrialTable;
    assert(height(T)==2 && ~any(T.Crash), 'Actual %s runner must complete.',direction);
    assert(isequal(T.ReceiverReplayCaptureStatus, ...
        ["captured_exact_receiver_input";"capture_limit_reached"]));
    path=fullfile(root,T.ReceiverReplayMATFile(1));
    assert(string(sixgr.util.sha256File(path))==T.ReceiverReplayMATSHA256(1));
    saved=load(path,'ReceiverReplay'); c=saved.ReceiverReplay;
    assert(c.WaveformSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(c.Waveform)));
    assert(~c.CaptureUsedByReceiver && c.AdditionalChannelExecutions==0);
    assert(~c.Context.ScoringReferenceReceiverInput && c.Context.ScoringReferenceAdditionalChannelExecutions==0);
    assert(c.Context.ScoringOnlyDesiredWaveformSource=="same_executed_isolated_desired_link_samples" && ...
        ~isempty(c.Context.ScoringOnlyDesiredWaveform) && all(isfinite(c.Context.ScoringOnlyDesiredWaveform),'all'));
    assert(~isempty(c.Context.ScoringOnlyTransmittedLayerSymbols) && ...
        numel(c.Context.ScoringOnlyTransmittedLayerSymbols)==numel(c.Context.ScoringOnlyTransmittedLayerIndices));
    assert(~any(startsWith(string(c.ReceiverArguments(1:2:end)),"ScoringOnly")));
    repeated=feval(c.ReceiverFunction,c.Waveform,c.Config,c.ReceiverArguments{:});
    for field=["TransportBlock","TBCRCPass","EstimatedCFO_Hz","AppliedTimingCorrection_samples"]
        assert(isequaln(repeated.(field),c.ReceiverResult.(field)), ...
            'Exact %s replay changed %s.',direction,field);
    end
    disabled=cfg; disabled.outputs.receiverReplayCapturePolicy='none';
    rng(719104,'twister'); baseline=runOne(disabled,direction);
    for field=["CRCPass","BitErrors","BitsCompared","TBSize_bits","GoodBits","EVM_rms"]
        assert(isequaln(T.(field),baseline.TrialTable.(field)), ...
            'Capture changed actual %s %s.',direction,field);
    end
    % Failed-only selection uses physical CRC outcomes, not a mock result.
    failed=cfg; failed.run.rootRunFolder=fullfile(root,lower(direction)+'_failed_only');
    mkdir(failed.run.rootRunFolder); failed.outputs.receiverReplayCapturePolicy='failed';
    assert(c.ReceiverResult.TBCRCPass,'The noise-free/high-SNR baseline must decode.');
    e=sixgr.link.captureReceiverReplay(failed,direction,c.Waveform,c.ReceiverArguments,c.ReceiverResult,c.Context);
    assert(e.Status=="not_selected_crc_pass" && ~isfolder(fullfile(failed.run.rootRunFolder,'air_interface')));
    noise=complex(randn(size(c.Waveform)),randn(size(c.Waveform)));
    noiseRx=feval(c.ReceiverFunction,noise,c.Config,c.ReceiverArguments{:});
    assert(~noiseRx.TBCRCPass,'Independent no-transmitter samples must fail this data decode.');
    e=sixgr.link.captureReceiverReplay(failed,direction,noise,c.ReceiverArguments,noiseRx,c.Context);
    assert(e.Status=="captured_exact_receiver_input");
end
scfg=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/dl_4ghz_baseline.yaml');
s=scfg.Data; s.output_control.receiver_replay_capture_policy='all';
s.output_control.receiver_replay_capture_max_trials=3;
sixgr.lls6g.config.validateScenarioConfig(s);
internal=sixgr.lls6g.buildInternalConfig(sixgr.lls6g.config.ScenarioConfig(s),root);
assert(string(internal.outputs.receiverReplayCapturePolicy)=="all" && internal.outputs.receiverReplayCaptureMaxTrials==3);
s.output_control.receiver_replay_capture_max_trials=0; caught=false;
try, sixgr.lls6g.buildInternalConfig(sixgr.lls6g.config.ScenarioConfig(s),root);
catch ME, caught=strcmp(ME.identifier,'sixgr:lls6g:config:ReceiverReplayCaptureLimit'); end
assert(caught,'An enabled unbounded/zero-limit receiver capture must not silently run.');
fprintf('RECEIVER_REPLAY_CAPTURE_PASS root=%s\n',root);
ok=true;
end

function out=runOne(cfg,direction)
if direction=="DL"
    out=sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',2,'SNR_dB',30,'ExecutionProfile','phy_calibration');
else
    out=sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',2,'SNR_dB',30);
end
end
