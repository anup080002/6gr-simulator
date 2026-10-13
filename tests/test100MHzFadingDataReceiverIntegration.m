function ok=test100MHzFadingDataReceiverIntegration()
% Current production DL/UL data runners; no access/export/calibration claim.
% Keep the resolved 100-MHz/4-GHz TDD configuration, actual DMRS overhead,
% CFO/timing impairments and receiver policy. Never replace failed TBs.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','lls','fading_data_receiver_integration', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
fprintf('FADING_DATA_RECEIVER_EVIDENCE_ROOT=%s\n',folder);
scenario='simulator/configs/fixtures/lls_result_richness.yaml';
resolved=sixgr.lls6g.config.loadScenarioConfig(scenario);
cfg=sixgr.lls6g.buildInternalConfig(resolved,folder);
% The public scenario runner normally binds this execution-owned path.
% Calling the data runners directly still requires the same capture root.
cfg.run.rootRunFolder=folder;
cfg=sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,1,1);
cfg.lls6g.userContext.UEIndex=1;
assert(cfg.phy.fc_Hz==4e9 && cfg.phy.carrier.NSizeGrid==273 && ...
    cfg.phy.carrier.SubcarrierSpacing==30 && strcmpi(cfg.phy.duplex.mode,'TDD'));
assert(cfg.phy.impairments.cfoEnabled && cfg.phy.impairments.cfoHz==40 && ...
    cfg.phy.impairments.timingOffsetEnabled && ...
    cfg.phy.impairments.timingOffsetSamples==16 && ...
    string(cfg.phy.impairments.cfoEstimationMethod)=="dmrs_two_symbol");
source=resolved.toStruct();
tuning=sixgr.lls6g.runners.resolveWaveformBundleRuntimeTuning(resolved,cfg,[18 30]);
assert(tuning.PrimaryTrialsPerSNR==8 && ~cfg.run.useParallel);
save(fullfile(folder,'configuration.mat'),'cfg','source','scenario');
dlRows=table(); ulRows=table(); summary=table();
for point=[18 30]
    for direction=["DL" "UL"]
        fprintf('FADING_DATA_START %s SNR=%g trials=8\n',direction,point);
        if direction=="DL"
            result=sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',8, ...
                'SNR_dB',point,'ExecutionProfile','phy_calibration');
            dlRows=[dlRows;result.TrialTable]; %#ok<AGROW>
            sixgr.util.csvWriteTable(fullfile(folder,'dl_trials.csv'),dlRows, ...
                'PreserveSchema',true,'RoundTripNumericText',true);
        else
            result=sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',8, ...
                'SNR_dB',point,'ExecutionProfile','phy_calibration');
            ulRows=[ulRows;result.TrialTable]; %#ok<AGROW>
            sixgr.util.csvWriteTable(fullfile(folder,'ul_trials.csv'),ulRows, ...
                'PreserveSchema',true,'RoundTripNumericText',true);
        end
        save(fullfile(folder,lower(direction)+"_"+point+"db.mat"),'result','-v7.3');
        rows=result.TrialTable;
        assert(height(rows)==8 && all(rows.ConfiguredSNR_dB==point) && ...
            all(rows.AppliedAWGNSNR_dB==point), ...
            'The actual applied noise point and all physical trials must be retained.');
        assert(all(rows.CFOApplied) && all(rows.TimingOffsetApplied) && ...
            all(rows.InjectedCFO_Hz==40) && all(rows.InjectedTimingOffset_samples==16), ...
            'The receiver check must execute, not disable, its configured impairments.');
        summary=[summary;table(direction,point,height(rows),nnz(rows.CRCPass), ...
            nnz(rows.Crash),double(result.BLER),double(result.BER),logical(result.Ok),false, ...
            'VariableNames',{'Direction','ConfiguredSNR_dB','Trials','CRCPassCount', ...
            'CrashCount','BLER','BER','ConfiguredObjectivePassed','StatisticallyQualified'})]; %#ok<AGROW>
        sixgr.util.csvWriteTable(fullfile(folder,'receiver_summary.csv'),summary, ...
            'PreserveSchema',true,'RoundTripNumericText',true);
        fprintf('FADING_DATA_RESULT %s SNR=%g CRC=%d/8 crashes=%d BLER=%g BER=%g objective=%d\n', ...
            direction,point,nnz(rows.CRCPass),nnz(rows.Crash),result.BLER,result.BER,result.Ok);
    end
end
assert(all(summary.CrashCount==0) && all(summary.ConfiguredObjectivePassed), ...
    'test:FadingDataReceiverObjectiveFailed', ...
    'Retain actual receiver/physical objective failures; inspect %s.',folder);
ok=true;
end
