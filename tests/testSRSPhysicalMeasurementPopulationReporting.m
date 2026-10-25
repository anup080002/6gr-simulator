function [ok,result]=testSRSPhysicalMeasurementPopulationReporting(retainedCSV)
% Declared publication operands, not a physical SRS/accuracy campaign.
% Optional original CSV audit does not rewrite or synthesize its evidence.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','srs_measurement_populations', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite prior evidence.');
layout=sixgr.report.resultLayout(folder); sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
source=localSource(); original=source;
absolute=collect(source); normalized=sixgr.report.collectSRSPhysicalMeasurementObservations( ...
    source,"SRS_RSRP_dB_re_UnitOccupiedRE_Es","dB_re_UnitOccupiedRE_Es");
assert(height(absolute)==2&&all(absolute.Availability=="observed")&& ...
    height(normalized)==2&&all(normalized.Availability=="observed"));
assert(numel(unique(absolute.PopulationID))==2&&all(contains(normalized.Notes,"engineering")));
% Original singleton JSON interval vectors lose orientation on decode.
% Both one interval and an actual two-interval partition must retain their
% exact operands; never reconstruct coverage from the observation alone.
partitioned=source(1,:); intervalEvidence=jsondecode(partitioned.SRSAbsolutePowerEvidenceJSON);
first=intervalEvidence.ObservationStartSample; last=intervalEvidence.ObservationEndSampleExclusive;
middle=first+(last-first)/2;
intervalEvidence.ExecutionIntervals=[first middle; middle last];
partitioned=seal(partitioned,1,intervalEvidence);
assert(all(collect(partitioned).Availability=="observed"));
for mutation=["three_operands","gap","overlap"]
    e=intervalEvidence;
    switch mutation
        case "three_operands", e.ExecutionIntervals=[first middle last];
        case "gap", e.ExecutionIntervals(2,1)=middle+1;
        case "overlap", e.ExecutionIntervals(2,1)=middle-1;
    end
    bad=seal(partitioned,1,e);
    mustFail(@()collect(bad),'sixgr:report:SRSObservationClock');
end
legacy=source(:,{'SRS_RSRP_dBm'}); unqualified=collect(legacy);
assert(height(unqualified)==2&&all(unqualified.Availability=="not_available")&& ...
    isequal(unqualified.ValueNumeric,source.SRS_RSRP_dBm));
late=source(repmat(1,257,1),:); late(end,:)=source(2,:);
for mutation=["unavailable","branch","digest","reported","mean","tiny_linear", ...
        "resource","plane","clock","numeric_string","numeric_flag","unsupported_source"]
    bad=late; e=jsondecode(bad.SRSAbsolutePowerEvidenceJSON(end));
    identifier='sixgr:report:SRSObservationOperands';
    switch mutation
        case "unavailable"
            bad.SRSAbsolutePowerAvailable(end)=false; identifier='sixgr:report:SRSObservationAvailability';
        case "branch"
            bad.SRSAbsolutePowerSelectedBranch0(end)=1; identifier='sixgr:report:SRSObservationBranch';
        case "digest"
            bad.SRSAbsolutePowerEvidenceSHA256(end)="changed"; identifier='sixgr:report:SRSObservationDigest';
        case "reported"
            e.Reported_W=e.Reported_W*2;
        case "mean"
            e.EngineeringBranchMean_W=e.EngineeringBranchMean_W*2;
        case "tiny_linear"
            % Absolute error below 1e-14 W is still material at this link
            % level; an epsilon bound must use the actual operand scale.
            e.Reported_W=e.Reported_W+1e-15;
        case "resource"
            bad.SRSAbsolutePowerResourceID(end)=99; identifier='sixgr:report:SRSObservationResource';
        case "plane"
            e.ReferencePlane="conducted_connector"; identifier='sixgr:report:SRSObservationPlane';
        case "clock"
            e.ExecutionIntervals=[e.ObservationStartSample e.ObservationEndSampleExclusive-1];
            identifier='sixgr:report:SRSObservationClock';
        case "numeric_string"
            e.Reported_W="1e-12"; identifier='sixgr:report:SRSObservationMetadata';
        case "numeric_flag"
            e.AccuracyQualified=0; identifier='sixgr:report:SRSObservationMetadata';
        case "unsupported_source"
            e.Estimator="copied_unknown_estimator"; bad.SRSAbsolutePowerSource(end)=e.Estimator;
            identifier='sixgr:report:SRSObservationSource';
    end
    if ~any(mutation==["unavailable","branch","digest","resource"])
        bad=seal(bad,height(bad),e);
    end
    mustFail(@()collect(bad),identifier);
end
bad=source; bad.SRS_RSRP_dB_re_UnitOccupiedRE_Es(end)=bad.SRS_RSRP_dB_re_UnitOccupiedRE_Es(end)+1;
mustFail(@()sixgr.report.collectSRSPhysicalMeasurementObservations( ...
    bad,"SRS_RSRP_dB_re_UnitOccupiedRE_Es","dB_re_UnitOccupiedRE_Es"),'sixgr:report:SRSObservationOperands');
% Actual CSV reader preserves singleton and vector text; a numeric source
% never becomes acceptable through generic string casting in the collector.
bad=source; bad.SRSRSRPSource=ones(2,1);
mustFail(@()sixgr.report.collectSRSPhysicalMeasurementObservations( ...
    bad,"SRS_RSRP_dB_re_UnitOccupiedRE_Es","dB_re_UnitOccupiedRE_Es"),'sixgr:report:SRSObservationMetadata');
path=fullfile(layout.AirInterfaceCSVDir,'srs_trials.csv');
sixgr.util.csvWriteTable(path,source,'PreserveSchema',true,'RoundTripNumericText',true);
digest=string(sixgr.util.sha256File(path));
roundtrip=sixgr.report.readSRSPhysicalMeasurementTrials(path);
assert(isequal(roundtrip.SRSAbsolutePowerEvidenceJSON,source.SRSAbsolutePowerEvidenceJSON)&& ...
    isequal(roundtrip.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es,source.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es));
assert(all(collect(roundtrip).Availability=="observed"));
scfg=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
data=scfg.toStruct(); data.output.artifact_contract_engine.enabled=false;
scfg=sixgr.lls6g.config.ScenarioConfig(data); cfg=sixgr.lls6g.buildInternalConfig(scfg,folder);
canonical=sixgr.truth.SharedDataCompletionRuntime.ensureLinkTrialTable(source,"UL",0,cfg);
for name=["SRSRSRPSource","SRSRSRPStatus","SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"]
    assert(ismember(name,string(canonical.Properties.VariableNames))&&isequal(canonical.(name),source.(name)), ...
        'Canonical publication must preserve original normalized engineering operands.');
end
manifest=struct('CodeVersion',"test",'CodeDetail',"declared_original_rows_no_PHY", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
out=sixgr.truth.exportLLSReportingBundle(folder,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
check(out.CategoryRows,source);
check(sixgr.util.csvReadTable(out.DetailCSV,'TextType','string'),source);
assert(isequaln(source,original)&&digest==string(sixgr.util.sha256File(path)));
retainedCount=0;
if nargin>0
    before=string(sixgr.util.sha256File(retainedCSV));
    retained=collect(sixgr.report.readSRSPhysicalMeasurementTrials(retainedCSV));
    assert(~isempty(retained)&&all(retained.Availability=="observed"));
    assert(before==string(sixgr.util.sha256File(retainedCSV)));
    retainedCount=height(retained);
end
result=struct('EvidenceRoot',string(folder),'SourceCSV',string(path),'SourceSHA256',digest, ...
    'DeclaredOriginalRows',2,'PHYExecutions',0,'RetainedOriginalRowsAudited',retainedCount);
fprintf('SRS_POPULATION_REPORT_PASS declared_rows=2 negative_groups=17 late_row=257 retained_rows=%d PHY_executions=0 root=%s\n',retainedCount,folder);
ok=true;
end

function T=localSource()
T=table([11;21],[1;2],[0;10],[1;2], ...
    'VariableNames',{'Slot','SweepPointIndex','ConfiguredSNR_dB','UEIndex'});
for name=["SRS_RSRP_dBm","SRS_RSRP_dB_re_UnitOccupiedRE_Es", ...
        "SRSAbsolutePowerResourceID","SRSAbsolutePowerSelectedBranch0","SRSAbsolutePowerBranchMean_dBm"]
    T.(name)=NaN(2,1);
end
T.SRSAbsolutePowerAvailable=true(2,1); T.SRSAbsolutePowerAccuracyQualified=false(2,1);
for name=["SRSAbsolutePowerStatus","SRSAbsolutePowerSource","SRSAbsolutePowerReferencePlane", ...
        "SRSAbsolutePowerAggregation","SRSAbsolutePowerEvidenceJSON","SRSAbsolutePowerEvidenceSHA256", ...
        "SRSRSRPPerReceiveAntenna_dBm","SRSRSRPSource","SRSRSRPStatus", ...
        "SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es"]
    T.(name)=strings(2,1);
end
for k=1:2
    power=[1e-12 4e-12]; if k==2, power=[3e-13 1e-13]; end
    [value,branch]=max(power); first=1000*k; receiver="gnb_"+k+"_rx";
    e=struct('Version',"sixgr.srs.antenna_power/v1", ...
        'Definition',"TS_38.215_V18.4.0_5.2.5_UL_SRS_RSRP", ...
        'ReferencePlane',"internal_physical_receive_element_before_RX_front_end", ...
        'ReferencePointApplicability',"internal_element_measurement_not_standardized_1O_or_2O_UL_SRS_RSRP_qualification", ...
        'Aggregation',"maximum_branch_selection_satisfies_diversity_lower_bound", ...
        'Estimator',"independent_preRF_nrChannelEstimate_per_symbol_known_SRS_reconstruction", ...
        'ReceiverID',receiver,'PlaneID',receiver+":pre_rf",'ObservationID',"declared_observation_"+k, ...
        'ObservationStartSample',first,'ObservationEndSampleExclusive',first+100, ...
        'ObservationSampleRateHz',7.68e6,'ObservationSHA256',string(repmat('a',1,64)), ...
        'PhysicalConfigurationEpoch',k,'ExecutionIntervals',[first first+100], ...
        'WaveformAmplitudeUnit',"sqrt_mW",'Resource',struct('ResourceID',10*k+7,'ConfigHash',"declared_resource_"+k), ...
        'ResourceSupportSubcarrier0Symbol0',[(0:5).' repmat(12,6,1)], ...
        'SRSNumPorts',1,'ReferenceSymbolSHA256',string(repmat('b',1,64)), ...
        'ReceiveBranchIndices0',[0 1],'PerReceiveBranch_W',power,'PerPortReceiveBranch_W',power, ...
        'MappedRECountPerPort',6,'UniquePhysicalRECount',6,'Reported_W',value, ...
        'EngineeringBranchMean_W',mean(power),'SelectedBranch0',branch-1, ...
        'Nfft',512,'RawGridScaleToSqrtW',1/(512*sqrt(1000)), ...
        'AlignedWaveformSHA256',string(repmat('c',1,64)),'ReceivedGridSHA256',string(repmat('d',1,64)), ...
        'AccuracyQualified',false,'DetectedPathPowerMeasured',false,'PostRFEstimateConsumed',false, ...
        'TruthChannelConsumed',false,'ReceiverFeedbackInput',false, ...
        'ReceiveBranchBinding',struct('Available',false,'ReferencePlane',"internal_physical_receive_element_before_RX_front_end", ...
        'HardwareConformanceVerified',false,'AccuracyQualified',false));
    T.SRS_RSRP_dBm(k)=10*log10(value)+30;
    T.SRSRSRPPerReceiveAntenna_dBm(k)=string(jsonencode(10*log10(power)+30));
    T.SRSAbsolutePowerBranchMean_dBm(k)=10*log10(mean(power))+30;
    T.SRSAbsolutePowerSelectedBranch0(k)=branch-1; T.SRSAbsolutePowerResourceID(k)=e.Resource.ResourceID;
    T.SRSAbsolutePowerStatus(k)="available_actual_antenna_capture_estimate_not_accuracy_qualified";
    T.SRSAbsolutePowerSource(k)=e.Estimator; T.SRSAbsolutePowerReferencePlane(k)=e.ReferencePlane;
    T.SRSAbsolutePowerAggregation(k)=e.Aggregation;
    normalized=[-k -k-3];
    T.SRS_RSRP_dB_re_UnitOccupiedRE_Es(k)=10*log10(mean(10.^(normalized/10)));
    T.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es(k)=string(jsonencode(normalized));
    T.SRSRSRPSource(k)="received_srs_channel_estimate_times_known_reference_symbols";
    T.SRSRSRPStatus(k)="observed";
    T=seal(T,k,e);
end
end
function T=seal(T,k,e)
T.SRSAbsolutePowerEvidenceJSON(k)=string(jsonencode(e));
T.SRSAbsolutePowerEvidenceSHA256(k)=string(sixgr.rrc.asn1.asn1SHA256Hex( ...
    unicode2native(char(T.SRSAbsolutePowerEvidenceJSON(k)),'UTF-8')));
end
function rows=collect(T)
rows=sixgr.report.collectSRSPhysicalMeasurementObservations(T,"SRS_RSRP_dBm","dBm");
end
function check(rows,source)
selected=rows(rows.MetricKey=="srs_rsrp",:);
assert(height(selected)==4&&all(selected.Statistic=="observation")&&all(selected.CountsTowardCoverage)&& ...
    numel(unique(selected.PopulationID))==4&&all(strlength(selected.PopulationSeriesID)==0));
for k=1:height(selected)
    p=jsondecode(selected.PopulationJSON(k));
    row=p.SourceRowIndex; assert(row==1||row==2);
    assert(p.SweepPointIndex==source.SweepPointIndex(row));
    expected=source.(string(p.SourceField))(row);
    assert(abs(selected.ValueNumeric(k)-expected)<=64*eps(max(abs([selected.ValueNumeric(k),expected]))));
    if selected.Unit(k)=="dBm"
        assert(p.PowerMeasurementSelectedBranch0==source.SRSAbsolutePowerSelectedBranch0(row)&& ...
            p.PowerMeasurementResource.ResourceID==source.SRSAbsolutePowerResourceID(row));
    else
        assert(contains(selected.Notes(k),"engineering"));
    end
end
end
function mustFail(f,identifier)
try, f(); catch ME
    assert(string(ME.identifier)==identifier,'Expected %s, received %s.',identifier,ME.identifier); return;
end
error('sixgr:test:MissingSRSObservationGuard','Expected %s.',identifier);
end
