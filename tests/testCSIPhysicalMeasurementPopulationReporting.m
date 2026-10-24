function [ok,result]=testCSIPhysicalMeasurementPopulationReporting()
% Declared source-row publication fixture, NOT new PHY/accuracy evidence.
% One actual public exporter invocation. Distinct receiver/resource/plane
% observations cannot become one averaged CSI-RSRP/RSRQ/SINR measurement.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','csi_physical_measurement_populations', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite retained evidence.');
layout=sixgr.report.resultLayout(folder);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
data=scfg.toStruct();
data.output.artifact_contract_engine.enabled=false;
scfg=sixgr.lls6g.config.ScenarioConfig(data);
cfg=sixgr.lls6g.buildInternalConfig(scfg,folder);
source=localSource(); original=source;
path=fullfile(layout.AirInterfaceCSVDir,'csi_rs_trials.csv');
sixgr.util.csvWriteTable(path,source,'PreserveSchema',true,'RoundTripNumericText',true);
digest=string(sixgr.util.sha256File(path));
manifest=struct('CodeVersion',"test",'CodeDetail',"declared_original_rows_no_PHY", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
out=sixgr.truth.exportLLSReportingBundle(folder,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
localCheck(out.CategoryRows,source);
localCheck(sixgr.util.csvReadTable(out.DetailCSV,'TextType','string'),source);
assert(isequaln(source,original)&&digest==string(sixgr.util.sha256File(path)), ...
    'Original measurement values, scope and source bytes must remain unchanged.');
result=struct('EvidenceRoot',string(folder),'SourceCSV',string(path), ...
    'SourceSHA256',digest,'OriginalObservationCount',2,'PHYExecutions',0, ...
    'Scope',"declared_original_CSI_rows_to_actual_report_not_PHY_accuracy");
ok=true;
fprintf('CSI_PHYSICAL_POPULATION_REPORT_PASS source_rows=2 metrics=3 report_invocations=1 PHY_executions=0 root=%s\n',folder);
end

function T=localSource()
T=table([11;21],[1;2],[0;10],[17;29],[4;8],[1;2], ...
    'VariableNames',{'Slot','SweepPointIndex','ConfiguredSNR_dB','ResourceID','BeamID','UEIndex'});
T.Frame=[2;3]; T.SFN=[1;2]; T.CellID=[1;2]; T.ResourceSetID=[3;5];
T.RunID=repmat("declared_metadata_fixture",2,1);
T.ExecutionID=["declared_execution_a";"declared_execution_b"];
T.ConfigHash=["declared_config_a";"declared_config_b"];
T.ReceiverID=["declared_ue_a";"declared_ue_b"];
T.ReceiverWindowID=["declared_window_a";"declared_window_b"];
T.ReceiverClockDomain=repmat("shared_receiver_sample_clock/v1",2,1);
T.ReceiverClockEpoch=[1;2]; T.MeasurementClockEpoch=[1;2];
T.MeasurementClockDomain=T.ReceiverClockDomain;
T.ObservationStartSample=[100;300]; T.ObservationEndSampleExclusive=[200;400];
T.ResultAvailableAtSample=[201;401]; T.ObservationSampleRateHz=repmat(7.68e6,2,1);
T.PhysicalMeasurementReferencePlane=["supplied_received_grid_columns";"original_pre_RX_RF_physical_element_columns"];
T.PowerReferencePlane=T.PhysicalMeasurementReferencePlane;
T.PhysicalMeasurementStandardizedReferencePointQualified=false(2,1);
T.PhysicalMeasurementHardwareQualified=false(2,1);
T.PhysicalMeasurementStatus=repmat("available",2,1);
T.PhysicalMeasurementWaveformStatus=repmat("available",2,1);
T.PhysicalMeasurementWaveformSource=repmat("declared_source_rows_no_new_waveform",2,1);
T.MeasurementPowerReferenceNormalized=false(2,1);
T.MeasurementSource=repmat("received_port3000_linear_RSRP_and_native_RSSI_pre_front_end_grid",2,1);
T.MeasurementRSRP_dBm=[-80;-100]; T.MeasurementRSSI_dBm=[-60;-75];
T.MeasurementRSRP_dB_re_UnitOccupiedRE_Es=nan(2,1);
T.MeasurementRSRQ_dB=10*log10(24)+T.MeasurementRSRP_dBm-T.MeasurementRSSI_dBm;
T.MeasurementNumRB=repmat(24,2,1); T.MeasurementFirstPRB0Based=[0;1];
T.MeasurementSymbolIndices0Based=["4|8";"5|9"];
T.MeasurementSubcarrierSpacing_kHz=repmat(15,2,1);
T.MeasurementSelectedResourceOrdinal=ones(2,1);
T.MeasurementResourceIDs=["17";"29"];
T.MeasurementReceiveAntennaIndex1Based=[1;2];
T.MeasurementRSRQReceiveAntennaIndex1Based=[1;2];
T.MeasurementRSRQNumeratorRSRP_dBm=T.MeasurementRSRP_dBm;
T.MeasurementRSRQDenominatorRSSI_dBm=T.MeasurementRSSI_dBm;
T.ReferenceMeasuredSINR_dB=[10;20];
T.ReferenceMeasuredSINRSource=["nrChannelEstimate_port3000_reference_RE_power_per_receive_branch"; ...
    "received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power"];
T.ReferenceMeasuredSINRStatus=repmat("available",2,1);
T.ReferenceMeasuredSINRDomain=repmat("csi_rs_port3000_reference_re_received_plane",2,1);
T.ReferenceSINRMeasurementJSON=strings(2,1); T.MeasurementPhysicalResourcesJSON=strings(2,1);
for k=1:2
    % Use the original producer's exact field/source vocabulary. These are
    % declared metadata operands, not an invented execution receipt.
    branchPower=T.MeasurementRSRP_dBm(k)+[-3 -3]; branchPower(k)=T.MeasurementRSRP_dBm(k);
    signalPower=10.^((branchPower-30)/10);
    ratios=[5 10]; if k==2, ratios=[20 10]; end
    denominator=signalPower./10.^(ratios/10);
    im=struct('Available',false,'Plan',struct('Enabled',false));
    disturbance="nrChannelEstimate_received_reference_residual";
    if k==2
        disturbance="configured_CSI_IM_received_RE_second_moment";
        im=struct('Available',true,'Source',disturbance,'Plan',struct('Enabled',true), ...
            'PowerPerReceiveAntenna',denominator,'SampleCount',24);
    end
    sinr=struct('Available',true,'Status',"measured",'CSI_SINR_dB',T.ReferenceMeasuredSINR_dB(k), ...
        'CSI_SINRPerReceiveAntenna_dB',ratios,'ReceiveBranch1Based',3-k, ...
        'DesiredPowerPerReceiveAntenna',signalPower,'NoiseInterferencePowerPerReceiveAntenna',denominator, ...
        'DisturbanceSource',disturbance,'InterferenceMeasurement',im,'ReferencePort',3000, ...
        'ReferenceRECount',48,'PowerUnit',"W_resource_grid",'MeasurementDomain',T.ReferenceMeasuredSINRDomain(k), ...
        'Source',T.ReferenceMeasuredSINRSource(k));
    measured=struct('ResourceID',T.ResourceID(k),'PowerUnit',"W_resource_grid", ...
        'RSRPPerAntenna_dBm',branchPower, ...
        'RSSIPerAntenna_dBm',[T.MeasurementRSSI_dBm(k) T.MeasurementRSSI_dBm(k)], ...
        'RSRQPerAntenna_dB',10*log10(24)+branchPower-T.MeasurementRSSI_dBm(k), ...
        'SINR',sinr,'NumReceiveAntennas',2,'NumRB',24, ...
        'FirstPRB0Based',T.MeasurementFirstPRB0Based(k), ...
        'SymbolIndices0Based',[3+k 7+k],'SubcarrierSpacing_kHz',15, ...
        'Source',"received_port3000_linear_RSRP_and_nrCSIRSMeasurements_RSSI", ...
        'RSRPSource',T.ReferenceMeasuredSINRSource(k),'RSRPReferencePort',3000,'Available',true);
    T.ReferenceSINRMeasurementJSON(k)=string(jsonencode(sinr));
    T.MeasurementPhysicalResourcesJSON(k)=string(jsonencode({measured}));
end
end

function localCheck(rows,source)
keys=["csi_rsrp","csi_rsrq","csi_sinr"];
fields=["MeasurementRSRP_dBm","MeasurementRSRQ_dB","ReferenceMeasuredSINR_dB"];
for k=1:numel(keys)
    selected=rows(rows.MetricKey==keys(k) & isfinite(rows.ValueNumeric),:);
    assert(height(selected)==2 && all(selected.Statistic=="observation"), ...
        'sixgr:test:CSIPopulationCollapsed','Retain each original observation, not pooled mean/p95/max.');
    assert(isequal(sort(selected.ValueNumeric),sort(source.(fields(k)))), ...
        'sixgr:test:CSIObservationChanged','Do not average, remap or substitute original measurement values.');
    assert(all(strlength(selected.PopulationJSON)>0) && numel(unique(selected.PopulationID))==2, ...
        'sixgr:test:CSIPopulationMissing','Retain independent source-row identities.');
    assert(~any(contains(lower(selected.Notes),"absolute calibrated power plane")), ...
        'sixgr:test:CSIUnqualifiedCalibration','Absolute units are not calibrated-reference-point qualification.');
    for n=1:2
        row=selected(selected.ValueNumeric==source.(fields(k))(n),:);
        identity=jsondecode(row.PopulationJSON);
        for name=["SweepPointIndex","ConfiguredSNR_dB","ResourceID","BeamID","UEIndex","CellID", ...
                "ReceiverID","ReceiverWindowID","PhysicalMeasurementReferencePlane"]
            assert(isfield(identity,name) && isequal(string(identity.(name)),string(source.(name)(n))), ...
                'sixgr:test:CSIPopulationIdentity','Preserve original identity field %s.',name);
        end
    end
end
end
