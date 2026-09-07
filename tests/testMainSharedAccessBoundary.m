function ok=testMainSharedAccessBoundary(folder)
% Execute the actual main entry point through its migrated access boundary.
% This is deliberately NOT a full-run pass. Verify actual SSB/TRS and Msg1
% publication while retaining a genuine failed-access/no-data result.
setup6GRSimToolkit('Verbose',false);
if nargin<1, folder=diagnoseMainSharedRA(36); end
files=dir(fullfile(folder,'**','*pbch*trials*.csv'));
found=false;
for f=files(:).'
    t=readtable(fullfile(f.folder,f.name),'TextType','string');
    if ~isempty(t) && all(ismember({'ObservationEndSampleExclusive','ReceiverGainCompensationApplied'},t.Properties.VariableNames))
        assert(all(t.BCHCrcPass==1) && all(t.SIB1DCICrcPass==1) && all(t.SIB1DLSCHCrcPass==1));
        assert(all(t.ReceiverGainCompensationApplied) && all(t.ObservationDeliverySlot>=6));
        for row=1:height(t)
            rss=jsondecode(t.SSBWindowPowerMeasurementJSON(row));
            assert(rss.Available && all(isfinite(rss.RSSIPerAntenna_dBm)));
        end
        assert(height(t)==8 && isequal(unique(t.Slot),[1;21]));
        for slot=[1 21]
            burst=t(t.Slot==slot,:);
            assert(isequal(sort(burst.SSBIndex),[0;1;2;3]) && ...
                all(burst.ObservationStartSample==(slot-1)*7680));
        end
        found=true;
    end
end
assert(found,'The main scheduler must publish its actual four-candidate burst, not only component-test results.');
files=dir(fullfile(folder,'air_interface','mat','ra_received_observations','*Msg1*.mat'));
assert(numel(files)==1,'Actual main Msg1 planes must be retained.');
data=load(fullfile(files.folder,files.name),'capture'); c=data.capture;
% The receiver's broadcast capsule must carry both decoded MIB and SIB1
% through the scheduler, not reconstruct CORESET0 from the scenario at RA.
mib=c.ReceiverContinuation.Config.UECommonMIBConfiguration;
ref=c.ReceiverContinuation.RAConfig.RARDCIReference;
assert(mib.Source=="decoded_mib_bch_transport_block" && mib.CORESET0Present);
assert(ref.FrequencyReferenceSource=="decoded_mib_coreset0" && ...
    ref.FrequencyReferenceSize==mib.CORESET0NumRB && ...
    ref.FrequencyReferenceStart==mib.CORESET0RBStart && ...
    ref.DMRSTypeAPosition==mib.DMRSTypeAPosition);
assert(abs(c.Prepared.StartTime_s-0.0145)<1e-12 && c.StartSample==111360);
ra=c.ReceivedResult; row=ra.RuntimeStageRows(end,:);
assert(row.RuntimeChannelStateUsed && ~row.SelfLoopWaveformUsed && ...
    row.RuntimeTransportMode=="shared_physical_waveform_stream" && row.ReceiverGainCompensationApplied);
assert(row.CompositeReceiverFrontEndApplied && row.RxRFAppliedStageCount>0 && ...
    isfinite(row.AppliedLargeScaleLoss_dB) && row.ThermalSampleNoiseBandwidth_Hz==c.SampleRateHz);
assert(ra.RARNTI==127,'Mixed-numerology RA-RNTI must address PRACH slot 9/symbol 0.');
assert(~ra.PreambleDetected && ~ra.RACompleted && ~ra.StrictOk, ...
    'Do not turn this low-detection-margin physical observation into an access pass.');
assert(ra.RuntimeExecutionState=="pending_next_stage" && ra.NextRuntimeStage=="Msg2" && ...
    strlength(ra.FailureReason)==0 && ~ra.RARWindowExpired, ...
    'A gNB detector miss cannot become an immediate UE RAR failure.');
monitor=readtable(fullfile(folder,'control','csv','rar_monitoring_observations.csv'),'TextType','string');
window=c.ReceiverContinuation.RAConfig.RARMonitoringWindow;
assert(isequal(monitor.AbsoluteSlot,window.MonitoringSlots) && all(monitor.CandidatesAttempted>0));
assert(all(~monitor.RARAccepted & ~monitor.ProxyUsed & ~monitor.FallbackUsed));
assert(all(monitor.Source=="actual_received_samples_ue_rar_monitoring"));
assert(all(monitor.ObservationEndSampleExclusive*c.SampleRateHz^-1 <= double(window.ExpiryTicksExclusive)/1966080000));
timers=readtable(fullfile(folder,'control','csv','ra_timer_events.csv'),'TextType','string');
expired=timers(timers.TimerName=="ra-ResponseWindow" & timers.Action=="expire",:);
assert(height(expired)==1 && expired.Expired && expired.ExpiryTicksExclusive==double(window.ExpiryTicksExclusive));
for name=["msg2_rar_trials","msg3_pusch_trials","msg4_contention_resolution"]
    assert(isempty(readtable(fullfile(folder,'control','csv',name+'.csv'))), ...
        'A response-window timeout cannot create unexecuted stage trials.');
end
captures=dir(fullfile(folder,'air_interface','mat','rar_monitoring_observations','*.mat'));
assert(numel(captures)==height(monitor));
for f=captures(:).'
    data=load(fullfile(f.folder,f.name),'capture'); record=data.capture;
    assert(size(record.RXBeforeRF,1)==record.EndSampleExclusive-record.StartSample);
    assert(record.ReceiverObservation.ObservationStartSample==record.StartSample && ...
        all(isfinite(record.RXBeforeRF),'all') && record.ExecutionReplay.RuntimeChannelStateUsed);
end
for name=["dl_pdsch_trials","ul_pusch_trials"]
    file=fullfile(folder,'air_interface','csv',name+'.csv');
    if isfile(file), assert(isempty(readtable(file)),'Failed access cannot produce data trials.'); end
end
assert(~isfolder(fullfile(folder,'air_interface','air_interface')), ...
    'A component folder must not be used as the canonical run root.');
disp('MAIN_SHARED_ACCESS_BOUNDARY_PASS: actual SSB/SIB1, PRACH and every receive occasion without a RAR transmission before expiry; no data qualification.');
ok=true;
end
