function ok=testPUCCHDetectionOutcomeWaveform()
% Frozen component matrix; not a statistical detector qualification campaign.
setup6GRSimToolkit('Verbose',false);
fixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,int8(mod((0:10).',2)));
audit=table();
contract=sixgr.truth.llsOutputContract();
meta=struct('logical_run_id',"pucch_detection_outcome_component",'run_id',1);
for present=[true false]
    snrs=[-30 -10 20];
    if ~present, snrs=-10; end
    for snr=snrs
        for seed=17:20
            trial=sixgr.link.runPUCCHWaveformTrial(fixture.Carrier, ...
                'Carrier',fixture.Carrier,'Assignment',fixture.Assignment, ...
                'Report',fixture.Report,'ReceiverContext',fixture.Context, ...
                'ChannelProfile','AWGN','SNR_dB',snr,'Seed',seed, ...
                'DetectionThreshold',.2,'SignalPresent',present);
            assert(strlength(string(trial.ErrorID))==0, ...
                'test:PUCCHExecutionFailed','Physical trial failed: %s',trial.ErrorMessage);
            rx=trial.Receiver;
            expected="unavailable";
            if rx.DetectionMetricValid
                expected="detected";
                if rx.DTX, expected="dtx"; end
            end
            assert(rx.DetectionOutcome==expected && trial.DetectionOutcome==expected);
            assert(trial.DetectionMetric==rx.DetectionMetric && ...
                trial.DetectionThreshold==.2 && trial.DTXFlag==rx.DTX);
            if present && ~trial.UCIContentMatch
                assert(~trial.Ok && trial.Status=="FAIL", ...
                    'Detected corrupted payloads must retain failure scoring.');
            end
            row=table(snr,seed,present,trial.DetectionMetric,trial.DetectionThreshold, ...
                trial.DetectionOutcome,trial.DTXFlag,trial.CRCApplicable, ...
                trial.UCIContentMatch,trial.BitErrors,trial.Status, ...
                'VariableNames',{'SNR_dB','Seed','SignalPresent','DetectionMetric', ...
                'DetectionThreshold','DetectionOutcome','DTXFlag','CRCApplicable', ...
                'UCIContentMatch','BitErrors','Status'});
            published=sixgr.truth.buildLLSPublicOutputTables(struct('pucch_table',row),contract,meta);
            assert(published.pucch_uci_table.DetectionOutcome==expected && ...
                published.pucch_uci_table.UCIContentMatch==trial.UCIContentMatch);
            audit=[audit;row]; %#ok<AGROW>
        end
    end
end
logsRoot=fullfile(pwd,'logs');
if ~isfolder(logsRoot), mkdir(logsRoot); end
output=tempname(logsRoot); mkdir(output);
file=fullfile(output,'receiver_presence_and_payload.csv'); writetable(audit,file);
restored=readtable(file,'TextType','string');
assert(isequal(restored.DetectionOutcome,audit.DetectionOutcome));
corrupted=audit.SignalPresent & audit.DetectionOutcome=="detected" & ~audit.UCIContentMatch;
assert(any(corrupted),'test:MissingCorruptedDetectionCoverage', ...
    'The frozen waveform matrix must exercise detected but incorrect UCI.');
assert(all(audit.Status(corrupted)=="FAIL") && ~any(audit.CRCApplicable));
assert(any(audit.SignalPresent & audit.SNR_dB==20 & audit.UCIContentMatch));
fprintf('PUCCH_DETECTION_OUTCOME_WAVEFORM_PASS cases=%d detected_corrupt=%d noise_only_detected=%d/%d qualified=0 csv=%s\n', ...
    height(audit),sum(corrupted),sum(~audit.SignalPresent & audit.DetectionOutcome=="detected"), ...
    sum(~audit.SignalPresent),file);
ok=true;
end
