function ok = testAgendaMeasurementExports()
% Reporting fixtures verify producer schema and content, not PHY performance.
setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

scenarioPath = fullfile("simulator", "configs", "scenarios", ...
    "lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, tmp);
layout = sixgr.report.resultLayout(tmp);
folders = [string(layout.AirInterfaceCSVDir), string(layout.HARQCSVDir), ...
    string(layout.PacketFlowCSVDir), string(layout.ReportCSVDir), ...
    string(layout.BeamformingCSVDir)];
for folder = folders, sixgr.util.ensureFolder(folder); end

dl = table([1;0], [0;50], [100;100], [0.12;0.12], [0.01;0.02], ...
    [2;2], [1000;1000], [0;1], [1;0], [20;20], ...
    'VariableNames', {'CRCPass','BitErrors','BitsCompared','RSOverheadFraction', ...
    'EVM_rms','Layers','TBSize_bits','HARQAttempt','CurrentDecodeOK','ActualEmittedPower_dBm'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), dl);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), dl);

pbch = table([-3;-4], ["[-10 -11]";"[-9 -12]"], [5;6], ["PASS";"PASS"], ...
    'VariableNames', {'SS_RSRP_dB_re_UnitOccupiedRE_Es', ...
    'SSBWindowReferenceRSRQPerReceiveAntenna_dB','SS_SINR_dB','Status'});
pbch.SSBWindowReferenceRSRQScope=repmat("ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI",2,1);
pbch.SSBWindowReferenceRSRQNumRB=[20;20];
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"), pbch);
prach = table([7;7], [7;8], [1;1], [1;2], ["PASS";"FAIL"], ...
    'VariableNames', {'RequestedPreambleIndex','DetectedPreambleIndex', ...
    'PreambleDetected','PreambleAttemptNumber','Status'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"), prach);
pdcch = table([1;0], ["PASS";"FAIL"], 'VariableNames', ...
    {'PDCCHCausalGrantDecodeOk','Status'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"), pdcch);
pucch = table([1;0], [0;1], [0;0], [0;1], [0;1], [11;11], ...
    'VariableNames', {'UCIContentMatch','FalseAck','ExpectedAck','DTXFlag','DecodedAck','BitsCompared'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"), pucch);
csirs = table([-2;-1], [-10;-9], [4;5], [3;4], [18;20], [1;2], [0;0], ...
    'VariableNames', {'MeasurementRelativeRSRP_dB','MeasurementRSRQ_dB', ...
    'ReferenceMeasuredSINR_dB','CQI','PMI','RI','CRI'});
% Deliberately different legacy, normalized and absolute planes must never
% become interchangeable just because every value is a power in dB.
csirs.MeasurementRSRP_dB_re_UnitOccupiedRE_Es=[-10.61;NaN];
csirs.MeasurementRSRP_dBm=[NaN;-85];
% Explicit declared receiver-operand fixtures, not just finite scalar labels.
% The normalized and absolute observations have different resources, planes,
% points and RSRP/SINR receive-branch selections. No PHY is executed here.
csirs=localCSIObservationFixture(csirs);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "csi_rs_trials.csv"), csirs);
csirsOriginalSHA256=string(sixgr.util.sha256File(fullfile(layout.AirInterfaceCSVDir,"csi_rs_trials.csv")));
csiFeedback = table([0.002;0.004], 'VariableNames', {'CSIAgeSeconds'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "csi_feedback_reports.csv"), csiFeedback);
srs = table(["PASS";"PASS"], 'VariableNames', {'Status'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"), srs);

timeline = table(["DL";"DL";"UL"], ["p1";"p1";"p2"], [1;2;1], ...
    [0;1;1], [0;1;1], [0;1;0], [1000;1000;800], [1;1;1], [0;0;0], [0;0;0], ...
    'VariableNames', {'Direction','PacketID','Attempt','CurrentDecodeOK', ...
    'CombinedDecodeOK','IsRetransmission','TBSize_bits','FeedbackObservationAvailable', ...
    'FeedbackApplied','FeedbackStaleIgnored'});
% Explicit isolated-probe completion is required for residual BLER. A final
% observed row alone cannot establish transmitter termination in a runtime.
timeline.ProbeMode=repmat("closed_loop",height(timeline),1);
timeline.SNR_dB=repmat(20,height(timeline),1);
timeline.StopCondition=["pending";"crc_pass";"crc_pass"];
sixgr.util.csvWriteTable(fullfile(layout.HARQCSVDir, "harq_process_timeline.csv"), timeline);
ledger = table(["DL";"UL"], [1;0], 'VariableNames', {'Direction','DeliverySuccess'});
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, ...
    "live_application_packet_delivery_ledger.csv"), ledger);
power = table([0.1;0.3], 'VariableNames', {'cumulative_energy_j'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_power_runtime_table.csv"), power);
occupancy = table([24;48], 'VariableNames', {'occupancy_value'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "contract__air-interface-frame-slot-symbol-grid__re-occupancy-heatmap.csv"), occupancy);
beamState = table([0;1], 'VariableNames', {'BeamFailureFlag'});
sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir, "beam_management_state_trace.csv"), beamState);
beamEvents = table([1;0], [0.005;NaN], 'VariableNames', {'FailureEventFlag','SwitchLatency_s'});
sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir, "beam_management_event_trace.csv"), beamEvents);

manifest = struct("CodeVersion", "test", "CodeDetail", "agenda_measurements", ...
    "RandomSeed", 1, "GeneratedUTC", "test", "RunnerProfile", "test", ...
    "RunCompletion", "completed", "DeterministicMode", "test");
out = sixgr.truth.exportLLSReportingBundle(tmp, scfg, cfg, struct("Ok", true), ...
    manifest, struct("StartedUTC", "test", "ElapsedSeconds", 1), struct());
rows = out.CategoryRows;
requiredObserved = ["initial_transmission_bler","residual_bler", ...
    "undetected_block_error_probability","resource_occupancy", ...
    "grant_failure_probability","uci_block_error_rate","nack_to_ack_probability", ...
    "dtx_to_ack_probability","uplink_drop_probability","csi_rsrp","csi_rsrq", ...
    "csi_sinr","cqi","pmi","ri","cri","csi_age","beam_outage", ...
    "ss_rsrp","ss_rsrq","ss_sinr","wrong_identity_probability", ...
    "access_attempt_count","feedback_association_error","retransmission_cost", ...
    "total_device_energy"];
for key = requiredObserved
    selected = rows(rows.MetricKey == key, :);
    assert(~isempty(selected) && any(selected.CountsTowardCoverage), ...
        "Requested measurement did not retain executed evidence: %s", key);
end
assert(all(rows.Availability(rows.MetricKey == "cli_rssi") == "disabled"));
assert(all(rows.Availability(rows.MetricKey == "unused_reserved_resources") == "disabled"));
assert(~any(rows.CountsTowardCoverage(rows.MetricKey == "srs_rsrp")), ...
    "Missing SRS-RSRP must remain unavailable rather than becoming a synthetic zero.");
power=rows(rows.MetricKey=="csi_rsrp",:);
normalized=power(startsWith(power.Entity,"CSI-RSRP_normalized@source_row="),:);
absolute=power(startsWith(power.Entity,"CSI-RSRP_absolute@source_row="),:);
assert(height(normalized)==1 && height(absolute)==1 && ...
    abs(normalized.ValueNumeric+10.61)<=64*eps(10.61) && absolute.ValueNumeric==-85 && ...
    all(normalized.Unit=="dB_re_UnitOccupiedRE_Es") && all(absolute.Unit=="dBm"));
assert(all(contains(normalized.Notes,"MeasurementRSRP_dB_re_UnitOccupiedRE_Es")) && ...
    all(contains(absolute.Notes,"MeasurementRSRP_dBm")));
assert(all(power.Statistic=="observation")&&all(power.CountsTowardCoverage)&& ...
    numel(unique(power.PopulationID))==2&&all(strlength(power.PopulationSeriesID)==0));
assert(~any(contains(lower(power.Notes),"absolute calibrated power plane")), ...
    'Absolute units do not create standardized or hardware calibration evidence.');
for k=1:2
    row=normalized; if k==2, row=absolute; end
    identity=jsondecode(row.PopulationJSON);
    assert(identity.SourceRowIndex==k&&identity.ResourceID==csirs.ResourceID(k)&& ...
        identity.SweepPointIndex==csirs.SweepPointIndex(k)&& ...
        string(identity.ReceiverWindowID)==csirs.ReceiverWindowID(k)&& ...
        string(identity.PhysicalMeasurementReferencePlane)==csirs.PhysicalMeasurementReferencePlane(k)&& ...
        identity.MeasurementReceiveAntennaIndex1Based==k);
    sinr=jsondecode(identity.ReferenceSINRMeasurementJSON);
    assert(sinr.ReceiveBranch1Based==3-k,'Do not substitute the RSRP branch for the SINR selection.');
end
for key=["csi_rsrq","csi_sinr"]
    selected=rows(rows.MetricKey==key,:);
    assert(height(selected)==2&&all(selected.Statistic=="observation")&& ...
        all(selected.CountsTowardCoverage)&&numel(unique(selected.PopulationID))==2, ...
        'Every retained CSI observation must remain separate in coverage and publication.');
end
assert(csirsOriginalSHA256==string(sixgr.util.sha256File(fullfile(layout.AirInterfaceCSVDir,"csi_rs_trials.csv"))), ...
    'Reporting must not change the original CSI observation CSV.');
% Old captures lacking the physical measurement must remain explicitly
% unavailable, even when a finite post-front-end diagnostic is retained.
csirs=removevars(csirs,{'MeasurementRSRP_dB_re_UnitOccupiedRE_Es','MeasurementRSRP_dBm'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,"csi_rs_trials.csv"),csirs);
% Distinct points/beams/branches remain distinct in the final report. A NaN
% branch is not removed before numbering the remaining measured branches.
pbch=pbch([1;1;1],:);
pbch.SSBWindowReferenceRSRQPerReceiveAntenna_dB=["NaN|-10|-20";"[-30 -40 NaN]";"1|-8|-16"];
pbch.ConfiguredSNR_dB=[20;0;20]; pbch.SweepPointIndex=[1;2;1];
pbch.SSBIndex=[0;0;1]; pbch.UEID=ones(3,1);
pbch.SS_RSRP_dB_re_UnitOccupiedRE_Es=[-3;NaN;-7];
pbch.SS_RSRP_dBm=[NaN;-85;NaN];
pbch.PowerReferencePlane=["normalized_fixed_esn0_unit_occupied_re_es";"absolute_antenna_plane";"normalized_fixed_esn0_unit_occupied_re_es"];
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,"pbch_trials.csv"),pbch);
out=sixgr.truth.exportLLSReportingBundle(tmp,scfg,cfg,struct("Ok",true), ...
    manifest,struct("StartedUTC","test","ElapsedSeconds",1),struct());
power=out.CategoryRows(out.CategoryRows.MetricKey=="csi_rsrp",:);
assert(~any(power.CountsTowardCoverage & isfinite(power.ValueNumeric)), ...
    'Legacy post-front-end power must not rescue a missing physical CSI-RSRP measurement.');
rsrq=out.CategoryRows(out.CategoryRows.MetricKey=="ss_rsrq" & out.CategoryRows.Statistic=="mean",:);
assert(height(rsrq)==7 && all(startsWith(rsrq.Entity,"SSB-window-reference-RSRQ@")));
assert(all(contains(rsrq.Notes,"not primary noise-debiased SSS RSRP")) && ...
    all(contains(rsrq.Notes,"Not a full configured NR-carrier/SMTC RSRQ claim")));
selected=contains(rsrq.Entity,"@SweepPointIndex=1@") & contains(rsrq.Entity,"@SSBIndex=0@") & ...
    contains(rsrq.Entity,"@RxBranch1Based=2");
assert(sum(selected)==1 && rsrq.ValueNumeric(selected)==-10);
selected=contains(rsrq.Entity,"@SweepPointIndex=2@") & contains(rsrq.Entity,"@RxBranch1Based=1");
assert(sum(selected)==1 && rsrq.ValueNumeric(selected)==-30);
assert(~any(contains(rsrq.Entity,"@SweepPointIndex=1@") & contains(rsrq.Entity,"@SSBIndex=0@") & ...
    contains(rsrq.Entity,"@RxBranch1Based=1")));
rsrp=out.CategoryRows(out.CategoryRows.MetricKey=="ss_rsrp" & out.CategoryRows.Statistic=="mean",:);
assert(height(rsrp)==3 && sum(rsrp.Unit=="dBm")==1 && rsrp.ValueNumeric(rsrp.Unit=="dBm")==-85);
% Legacy ratios lacking scope cannot silently become full-carrier RSRQ.
pbch=removevars(pbch,'SSBWindowReferenceRSRQScope');
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,"pbch_trials.csv"),pbch);
out=sixgr.truth.exportLLSReportingBundle(tmp,scfg,cfg,struct("Ok",true), ...
    manifest,struct("StartedUTC","test","ElapsedSeconds",1),struct());
rsrq=out.CategoryRows(out.CategoryRows.MetricKey=="ss_rsrq",:);
assert(~any(rsrq.CountsTowardCoverage),'Unscoped window ratios must not become qualified SS-RSRQ.');
fprintf('AGENDA_MEASUREMENT_EXPORTS_PASS point_beam_branch_identity=1 window_scope=1 absolute_power=1 missing_scope=1\n');
ok = true;
end

function T=localCSIObservationFixture(T)
% Hand-declared producer-shaped publication operands; no waveform claim.
T.Slot=[11;21]; T.SweepPointIndex=[1;2]; T.ConfiguredSNR_dB=[0;10];
T.ResourceID=[7;9]; T.ResourceSetID=[2;3]; T.UEIndex=[1;2]; T.CellID=[1;2];
T.ReceiverID=["declared_ue1";"declared_ue2"];
T.ReceiverWindowID=["declared_normalized_window";"declared_absolute_window"];
T.MeasurementSelectedResourceOrdinal=ones(2,1); T.MeasurementResourceIDs=["7";"9"];
T.MeasurementReceiveAntennaIndex1Based=[1;2]; T.MeasurementRSRQReceiveAntennaIndex1Based=[1;2];
T.MeasurementNumRB=[24;24]; T.MeasurementFirstPRB0Based=[0;1];
T.MeasurementSubcarrierSpacing_kHz=[15;15]; T.MeasurementSymbolIndices0Based=["4|8";"5|9"];
T.MeasurementPowerReferenceNormalized=[true;false];
T.PhysicalMeasurementReferencePlane=["normalized_fixed_esn0_unit_occupied_re_es";"supplied_received_grid_columns"];
T.PowerReferencePlane=T.PhysicalMeasurementReferencePlane;
T.PhysicalMeasurementStatus=["available_normalized_fixed_esn0_not_absolute_dbm";"available"];
T.PhysicalMeasurementStandardizedReferencePointQualified=false(2,1);
T.PhysicalMeasurementHardwareQualified=false(2,1);
T.MeasurementSource=["actual_csirs_re_measurement_relative_to_unit_occupied_re_es"; ...
    "received_port3000_linear_RSRP_and_native_RSSI_pre_front_end_grid"];
T.ReferenceMeasuredSINRSource=["nrChannelEstimate_port3000_reference_RE_power_per_receive_branch"; ...
    "received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power"];
T.ReferenceMeasuredSINRStatus=repmat("available",2,1);
T.ReferenceMeasuredSINRDomain=repmat("csi_rs_port3000_reference_re_received_plane",2,1);
T.ReferenceSINRMeasurementJSON=strings(2,1); T.MeasurementPhysicalResourcesJSON=strings(2,1);
for k=1:2
    powerUnit="W_resource_grid"; suffix="_dBm"; value=T.MeasurementRSRP_dBm(k);
    if k==1, powerUnit="relative_to_unit_occupied_RE_Es"; suffix="_dB_re_UnitOccupiedRE_Es"; value=T.MeasurementRSRP_dB_re_UnitOccupiedRE_Es(k); end
    rsrp=value+[-3 -3]; rsrp(k)=value;
    rssi=repmat(10*log10(24)+value-T.MeasurementRSRQ_dB(k),1,2);
    ratios=T.ReferenceMeasuredSINR_dB(k)+[-2 -2]; ratios(3-k)=T.ReferenceMeasuredSINR_dB(k);
    signalPower=10.^(rsrp/10); if k==2, signalPower=signalPower*1e-3; end
    disturbancePower=signalPower./10.^(ratios/10);
    disturbance="nrChannelEstimate_received_reference_residual";
    im=struct('Available',false,'Plan',struct('Enabled',false));
    if k==2
        disturbance="configured_CSI_IM_received_RE_second_moment";
        im=struct('Available',true,'Source',disturbance,'Plan',struct('Enabled',true), ...
            'PowerPerReceiveAntenna',disturbancePower,'SampleCount',24);
    end
    sinr=struct('Available',true,'Status',"measured",'CSI_SINR_dB',T.ReferenceMeasuredSINR_dB(k), ...
        'CSI_SINRPerReceiveAntenna_dB',ratios,'ReceiveBranch1Based',3-k, ...
        'DesiredPowerPerReceiveAntenna',signalPower,'NoiseInterferencePowerPerReceiveAntenna',disturbancePower, ...
        'DisturbanceSource',disturbance,'InterferenceMeasurement',im,'ReferencePort',3000, ...
        'ReferenceRECount',48,'PowerUnit',powerUnit,'MeasurementDomain',T.ReferenceMeasuredSINRDomain(k), ...
        'Source',T.ReferenceMeasuredSINRSource(k));
    measured=struct('ResourceID',T.ResourceID(k),'PowerUnit',powerUnit,'SINR',sinr, ...
        'NumReceiveAntennas',2,'NumRB',24,'FirstPRB0Based',k-1, ...
        'SymbolIndices0Based',[3+k 7+k],'SubcarrierSpacing_kHz',15, ...
        'RSRPSource',T.ReferenceMeasuredSINRSource(k),'RSRPReferencePort',3000,'Available',true);
    measured.("RSRPPerAntenna"+suffix)=rsrp;
    measured.("RSSIPerAntenna"+suffix)=rssi;
    measured.RSRQPerAntenna_dB=10*log10(24)+rsrp-rssi;
    measured.Source="received_port3000_linear_RSRP_and_nrCSIRSMeasurements_RSSI";
    if k==1, measured.Source="received_port3000_linear_RSRP_and_native_RSSI_normalized_unit_RE_grid"; end
    T.ReferenceSINRMeasurementJSON(k)=string(jsonencode(sinr));
    T.MeasurementPhysicalResourcesJSON(k)=string(jsonencode({measured}));
end
end

function localCleanup(path)
if exist(path, "dir") == 7
    rmdir(path, "s");
end
end
