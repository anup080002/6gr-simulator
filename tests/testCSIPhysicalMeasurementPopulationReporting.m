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
localDirectChecks(source);
path=fullfile(layout.AirInterfaceCSVDir,'csi_rs_trials.csv');
sixgr.util.csvWriteTable(path,source,'PreserveSchema',true,'RoundTripNumericText',true);
digest=string(sixgr.util.sha256File(path));
roundtrip=sixgr.report.readCSIPhysicalMeasurementTrials(path);
assert(isstring(roundtrip.MeasurementResourceIDs)&& ...
    isequal(roundtrip.MeasurementResourceIDs,source.MeasurementResourceIDs)&& ...
    isequal(roundtrip.MeasurementPhysicalResourcesJSON,source.MeasurementPhysicalResourcesJSON), ...
    'Canonical singleton resource vectors and original JSON must survive CSV inference as text.');
for metric=["MeasurementRSRP_dBm","MeasurementRSRQ_dB","ReferenceMeasuredSINR_dB"]
    unit="dB"; if metric=="MeasurementRSRP_dBm", unit="dBm"; end
    checked=sixgr.report.collectCSIPhysicalMeasurementObservations(roundtrip,metric,unit);
    assert(height(checked)==2&&all(checked.Availability=="observed"));
end
% Cardinality may change after the type-inference prefix: preserve both a
% singleton token and a later vector, without rebuilding or rewriting them.
probe=source(:,{'MeasurementResourceIDs','MeasurementSymbolIndices0Based'});
probe.MeasurementResourceIDs=["17";"17|29"];
probe.MeasurementSymbolIndices0Based=["4";"4|8"];
probePath=fullfile(layout.AirInterfaceCSVDir,'declared_csi_vector_import.csv');
sixgr.util.csvWriteTable(probePath,probe,'PreserveSchema',true);
probeDigest=string(sixgr.util.sha256File(probePath));
assert(isequal(sixgr.report.readCSIPhysicalMeasurementTrials(probePath),probe)&& ...
    probeDigest==string(sixgr.util.sha256File(probePath)), ...
    'Declared vector import must preserve original singleton and multivalue tokens.');
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
T.DLMeasurementConfigurationFamily=repmat("CSI-RS",2,1);
T.DLMeasurementConfigurationSHA256=repmat(string(repmat('a',1,64)),2,1);
T.DLMeasurementNCellID=[1;2];
T.DLMeasurementInstallationSHA256=["";string(repmat('b',1,64))];
T.DLMeasurementAuthorityRequired=true(2,1);
T.DLMeasurementAuthorityEligible=[false;true];
T.DLMeasurementAuthorityStatus=["declared_diagnostic_only";"declared_installed"];
T.DLMeasurementAuthoritySource=repmat("declared_metadata_fixture_not_runtime_proof",2,1);
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
    expected=sort(source.(fields(k))); actual=sort(selected.ValueNumeric);
    assert(all(abs(actual-expected)<=64*eps(max(1,max(abs(expected))))), ...
        'sixgr:test:CSIObservationChanged','Do not average, remap or substitute original measurement values.');
    assert(all(strlength(selected.PopulationJSON)>0) && numel(unique(selected.PopulationID))==2, ...
        'sixgr:test:CSIPopulationMissing','Retain independent source-row identities.');
    assert(~any(contains(lower(selected.Notes),"absolute calibrated power plane")), ...
        'sixgr:test:CSIUnqualifiedCalibration','Absolute units are not calibrated-reference-point qualification.');
    for n=1:2
        expected=source.(fields(k))(n);
        row=selected(abs(selected.ValueNumeric-expected)<=64*eps(max(1,abs(expected))),:);
        assert(height(row)==1,'One original observation must retain its distinct value.');
        identity=jsondecode(row.PopulationJSON);
        for name=["SweepPointIndex","ConfiguredSNR_dB","ResourceID","BeamID","UEIndex","CellID", ...
                "ReceiverID","ReceiverWindowID","PhysicalMeasurementReferencePlane", ...
                "DLMeasurementConfigurationFamily","DLMeasurementConfigurationSHA256", ...
                "DLMeasurementNCellID","DLMeasurementInstallationSHA256", ...
                "DLMeasurementAuthorityStatus","DLMeasurementAuthoritySource"]
            assert(isfield(identity,name) && isequal(string(identity.(name)),string(source.(name)(n))), ...
                'sixgr:test:CSIPopulationIdentity','Preserve original identity field %s.',name);
        end
        for name=["DLMeasurementAuthorityRequired","DLMeasurementAuthorityEligible"]
            assert(double(identity.(name))==double(source.(name)(n)), ...
                'Observation publication must not promote diagnostic reception to operational eligibility.');
        end
    end
end
end

function localDirectChecks(source)
collect=@(t) sixgr.report.collectCSIPhysicalMeasurementObservations(t,"MeasurementRSRP_dBm","dBm");
actual=collect(source);
assert(height(actual)==2&&all(actual.Availability=="observed")&&isequal(actual.ValueNumeric,[-80;-100]));
legacy=source(:,{'MeasurementRSRP_dBm'});
retained=collect(legacy);
assert(height(retained)==2&&all(retained.Availability=="not_available")&& ...
    isequal(retained.ValueNumeric,legacy.MeasurementRSRP_dBm));
identity=jsondecode(retained.PopulationJSON(1));
assert(~isfield(identity,'ResourceID')&&~isfield(identity,'ReceiverID')&& ...
    ~isfield(identity,'DLMeasurementAuthorityEligible'), ...
    'Do not create a receiver/resource identity for legacy scalars.');
capsule=localWithPopulation(source);
assert(height(collect(capsule))==2,'Valid capsules with original nullable seed fields must remain accepted.');
% Late contradictions must not disappear behind the first rows or a sample
% limit. All cases use this same production collector, not a test replica.
late=source(repmat(1,257,1),:); late(end,:)=source(2,:);
bad=late; bad.DLMeasurementAuthorityEligible=double(bad.DLMeasurementAuthorityEligible);
bad.DLMeasurementAuthorityEligible(end)=2;
localMustFail(@() collect(bad),'sixgr:report:CSIObservationMetadata');
bad=late; bad.DLMeasurementAuthoritySource=repmat(1,height(bad),1);
localMustFail(@() collect(bad),'sixgr:report:CSIObservationMetadata');
bad=late; bad.ResourceID(end)=99;
localMustFail(@() collect(bad),'sixgr:report:CSIObservationResource');
bad=late; bad.MeasurementReceiveAntennaIndex1Based(end)=1;
localMustFail(@() collect(bad),'sixgr:report:CSIObservationBranch');
bad=late; bad.MeasurementSymbolIndices0Based(end)="0|1";
localMustFail(@() collect(bad),'sixgr:report:CSIObservationSupport');
bad=late; bad.MeasurementPowerReferenceNormalized(end)=true;
localMustFail(@() collect(bad),'sixgr:report:CSIObservationUnit');
bad=late; bad.MeasurementRSRQDenominatorRSSI_dBm(end)=bad.MeasurementRSRQDenominatorRSSI_dBm(end)+1;
localMustFail(@() sixgr.report.collectCSIPhysicalMeasurementObservations(bad,"MeasurementRSRQ_dB","dB"), ...
    'sixgr:report:CSIObservationSupport');
bad=late; q=jsondecode(bad.ReferenceSINRMeasurementJSON(end)); q.ReceiveBranch1Based=2;
bad.ReferenceSINRMeasurementJSON(end)=string(jsonencode(q));
localMustFail(@() sixgr.report.collectCSIPhysicalMeasurementObservations(bad,"ReferenceMeasuredSINR_dB","dB"), ...
    'sixgr:report:CSIObservationSINR');
% Coherently copying both JSON aliases must not bypass the independent
% selected-resource source/domain/unit contract. These are metadata tests.
for mutation=["source","unsupported_source","domain","unit"]
    bad=late; q=jsondecode(bad.ReferenceSINRMeasurementJSON(end));
    r=jsondecode(bad.MeasurementPhysicalResourcesJSON(end)); if iscell(r), r=r{1}; end
    expected='sixgr:report:CSIObservationSINR';
    switch mutation
        case "source"
            q.Source="nrChannelEstimate_port3000_reference_RE_power_per_receive_branch";
            bad.ReferenceMeasuredSINRSource(end)=q.Source;
        case "unsupported_source"
            q.Source="unverified_copied_reference";
            r.RSRPSource=q.Source; bad.ReferenceMeasuredSINRSource(end)=q.Source;
        case "domain"
            q.MeasurementDomain="different_received_plane";
        case "unit"
            q.PowerUnit="relative_to_unit_occupied_RE_Es";
            expected='sixgr:report:CSIObservationUnit';
    end
    r.SINR=q; bad.ReferenceSINRMeasurementJSON(end)=string(jsonencode(q));
    bad.MeasurementPhysicalResourcesJSON(end)=string(jsonencode({r}));
    localMustFail(@() sixgr.report.collectCSIPhysicalMeasurementObservations(bad,"ReferenceMeasuredSINR_dB","dB"),expected);
end
native=source;
for k=1:height(native)
    q=jsondecode(native.ReferenceSINRMeasurementJSON(k)); q=rmfield(q,'PowerUnit');
    r=jsondecode(native.MeasurementPhysicalResourcesJSON(k)); if iscell(r), r=r{1}; end
    r.SINR=q; native.ReferenceSINRMeasurementJSON(k)=string(jsonencode(q));
    native.MeasurementPhysicalResourcesJSON(k)=string(jsonencode({r}));
end
nativeRows=sixgr.report.collectCSIPhysicalMeasurementObservations(native,"ReferenceMeasuredSINR_dB","dB");
assert(height(nativeRows)==2&&all(nativeRows.Availability=="observed"), ...
    'The original parent unit remains authoritative when native SINR has no optional unit alias.');
bad=capsule; bad.CSIObservationPopulationSHA256(end)="changed";
localMustFail(@() collect(bad),'sixgr:report:CSIObservationPopulationDigest');
bad=capsule; bad.SweepPointIndex(end)=99;
localMustFail(@() collect(bad),'sixgr:report:CSIObservationPopulation');
bad=late; q=jsondecode(bad.MeasurementPhysicalResourcesJSON(end));
if iscell(q), q=q{1}; end
q.NumReceiveAntennas="2"; bad.MeasurementPhysicalResourcesJSON(end)=string(jsonencode({q}));
localMustFail(@() collect(bad),'sixgr:report:CSIObservationMetadata');
% Signed/zero-disturbance JSON may lack a nonfinite token. The original CSV
% infinity remains visible but may not be upgraded to validated operands.
limit=source(1,:); limit.ReferenceMeasuredSINR_dB=Inf;
q=jsondecode(limit.ReferenceSINRMeasurementJSON); q.CSI_SINR_dB=[];
r=jsondecode(limit.MeasurementPhysicalResourcesJSON); if iscell(r), r=r{1}; end
r.SINR=q; limit.ReferenceSINRMeasurementJSON=string(jsonencode(q));
limit.MeasurementPhysicalResourcesJSON=string(jsonencode({r}));
observed=sixgr.report.collectCSIPhysicalMeasurementObservations(limit,"ReferenceMeasuredSINR_dB","dB");
assert(height(observed)==1&&isinf(observed.ValueNumeric)&&observed.Availability=="not_available");
fprintf('CSI_POPULATION_COLLECTOR_CHECKS_PASS metadata_only negative_cases=13 late_row=257\n');
end

function T=localWithPopulation(T)
for name=["CSIObservationPopulationJSON","CSIObservationPopulationSHA256", ...
        "CSIObservationPopulationSource","CSIObservationPopulationBindingJSON"]
    T.(name)=strings(height(T),1);
end
for k=1:height(T)
    fields=struct('RunFolder',"",'RunID',T.RunID(k),'RunTag',"", ...
        'ExecutionID',T.ExecutionID(k),'ConfigHash',T.ConfigHash(k),'ScenarioID',"", ...
        'RandomSeed',NaN,'ChannelSeed',NaN,'SweepPointIndex',T.SweepPointIndex(k), ...
        'ConfiguredSNR_dB',T.ConfiguredSNR_dB(k));
    queue=struct('SourceSlot',T.Slot(k),'QueuedAtSample',T.ObservationStartSample(k), ...
        'ClockDomain',"shared_physical_sample_clock/v1", ...
        'PhysicalConfigurationEpoch',T.MeasurementClockEpoch(k),'SampleRateHz',T.ObservationSampleRateHz(k));
    population=struct('Version',"csi_observation_population/v1", ...
        'Source',"configured_queue_context_not_emission_proof",'Fields',fields,'Queue',queue, ...
        'ConfiguredSNRRole',"configured_operating_point_label_not_measured_SINR_or_thermal_noise_authority", ...
        'SeedRole',"configured_global_and_channel_seeds_not_executed_receiver_noise_stream_seed");
    population.SHA256=string(sixgr.util.sha256Hex(jsonencode(population)));
    binding=struct('Source',"queued_population_matched_to_completed_same_owner_CSI_RS_TX_receipt", ...
        'ComponentID',"declared_component_"+k,'SourceSlot',T.Slot(k),'ServingCell',T.CellID(k), ...
        'FirstActiveSample',T.ObservationStartSample(k)+1,'CommittedAtSample',T.ObservationEndSampleExclusive(k), ...
        'PhysicalConfigurationEpoch',T.MeasurementClockEpoch(k),'SampleRateHz',T.ObservationSampleRateHz(k), ...
        'ReceiverResultAvailableAtSample',T.ResultAvailableAtSample(k));
    T.CSIObservationPopulationJSON(k)=string(jsonencode(population));
    T.CSIObservationPopulationSHA256(k)=population.SHA256;
    T.CSIObservationPopulationSource(k)=population.Source;
    T.CSIObservationPopulationBindingJSON(k)=string(jsonencode(binding));
end
end

function localMustFail(action,identifier)
try, action(); catch ME
    assert(string(ME.identifier)==identifier,'Expected %s, received %s.',identifier,ME.identifier); return;
end
error('sixgr:test:MissingCSIObservationGuard','Expected %s.',identifier);
end
