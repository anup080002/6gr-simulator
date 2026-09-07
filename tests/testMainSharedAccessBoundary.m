function ok=testMainSharedAccessBoundary()
% Execute the actual main entry point through its migrated access boundary.
% This is deliberately NOT a full-run pass. Verify actual SSB/TRS and Msg1
% publication while retaining a genuine failed-access/no-data result.
setup6GRSimToolkit('Verbose',false);
folder=diagnoseMainSharedRA(16);
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
        assert(height(t)==4); found=true;
    end
end
assert(found,'The main scheduler must publish its actual four-candidate burst, not only component-test results.');
files=dir(fullfile(folder,'**','ra_received_observations','*Msg1*.mat'));
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
assert(isempty(ra.ArtifactTables.msg2_pdcch_candidates) && ...
    isempty(ra.ArtifactTables.msg2_dci_fields), ...
    'Unexecuted Msg2 must not publish a dummy candidate or decoded DCI row.');
for name=["dl_pdsch_trials","ul_pusch_trials"]
    file=fullfile(folder,'air_interface','csv',name+'.csv');
    if isfile(file), assert(isempty(readtable(file)),'Failed access cannot produce data trials.'); end
end
disp('MAIN_SHARED_ACCESS_BOUNDARY_PASS: actual SSB/SIB1 and PRACH evidence; failed access, no data qualification.');
ok=true;
end
