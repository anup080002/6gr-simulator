function ok=testN40IntegrationGateEvaluator()
% Deliberately incomplete test-only artifact tree: never integration truth.
% Exercise fail-closed reduction and the physical CRC/software distinction.
root=tempname; mkdir(root); mkdir(fullfile(root,'meta'));
mkdir(fullfile(root,'air_interface','csv'));
identity=struct('RunID','gate_unit','ExecutionID','gate_execution','ConfigHash',repmat('a',1,64));
sixgr.util.jsonWrite(fullfile(root,'meta','execution_identity.json'),identity);
configPath=fullfile(root,'meta','scenario_config_resolved.json');
sixgr.util.jsonWrite(configPath,struct('TestFixture',true));
sixgr.util.jsonWrite(fullfile(root,'meta','scenario_config_identity.json'), ...
    struct('ConfigHash',identity.ConfigHash,'ResolvedJSONSHA256',sixgr.util.sha256File(configPath)));
T=table("gate_unit","gate_execution",string(identity.ConfigHash),1,0,0,0, ...
    'VariableNames',{'RunID','ExecutionID','ConfigHash','CRCApplicable','CRCPass','Crash','FallbackFlag'});
path=fullfile(root,'air_interface','csv','dl_pdsch_trials.csv');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
before=sixgr.util.sha256File(path);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~out.Ok && ~out.FinalAccepted && pass(out,'primary_pdsch') && pass(out,'execution_identity'), ...
    '%s',checkDetail(out,'primary_pdsch')+newline+checkDetail(out,'execution_identity'));
assert(out.RadioOutcomes.CRCFailCount(out.RadioOutcomes.Signal=="pdsch")==1, ...
    'Observed CRC failure must remain a radio result, not a software failure.');
assert(sixgr.util.sha256File(path)==before,'The evaluator must not rewrite evidence.');
assert(~pass(out,'received_csi')&&~pass(out,'completed_csi_application'));
T.Crash=1; sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'primary_pdsch') && ...
    out.Checks.Status(out.Checks.CheckID=="primary_pdsch")=="SOFTWARE_FAILURE", ...
    '%s',checkDetail(out,'primary_pdsch'));
T.Crash=0; T.ExecutionID="other_child"; sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root);
assert(~pass(out,'primary_pdsch') && ~out.FinalAccepted && ...
    out.Checks.Status(out.Checks.CheckID=="primary_pdsch")=="IDENTITY_MISMATCH", ...
    '%s',checkDetail(out,'primary_pdsch'));
assert(~pass(out,'actual_checkpoint_continuation'));
T.ExecutionID="gate_execution"; T.CRCPass=NaN;
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'primary_pdsch'),'Missing applicable CRC must not become a measured failure or pass.');
testOriginalCSIBinding(root);
testCompletedCSISelection(root);
testExecutedMCSTransitions(root);
testParentPublication();
fprintf('N40_INTEGRATION_GATE_EVALUATOR_PASS incomplete_test_fixture=%s\n',root);
ok=true;
end
function value=pass(out,id)
hit=out.Checks.CheckID==id; assert(nnz(hit)==1); value=out.Checks.Passed(hit);
end

function testCompletedCSISelection(root)
% Authored parser fixture only: no PHY execution or full-gate acceptance.
mkdir(fullfile(root,'control','csv'));
R=table("fixture_report","fixture_observation",1,"delivered_to_runtime_scheduler", ...
    'VariableNames',{'ReportIdentity','ObservationID','CSIUCIDecodeOk','DeliveryStatus'});
sixgr.util.csvWriteTable(fullfile(root,'control','csv','received_csi_reports.csv'),R);
a=struct('ReportIdentity','fixture_report','ObservationID','fixture_observation', ...
    'AvailableAtSample',100,'RI',1,'PMI',31,'CRI',1);
f=struct('ReportIdentity',a.ReportIdentity,'ObservationID',a.ObservationID, ...
    'ReportedRI',1,'ReportedPMI',31,'ReportedCRI',1, ...
    'FrozenNumLayers',1,'FrozenPMI',31,'FrozenCSIResourceIndex',1);
e=struct('AdmittedCSI',a,'FrozenApplication',f,'DecisionClock',struct('AtSample',101), ...
    'FirstActiveSample',110,'CompletedAtSample',200,'WaveformApplicationVerified',true, ...
    'AdditionalPHYExecutions',0);
path=fullfile(root,'air_interface','csv','dl_pdsch_trials.csv');
writeCompletedCSI(path,e,1);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'completed_csi_application')&&~out.Ok,'%s',checkDetail(out,'completed_csi_application'));
for name=["ReportedRI","ReportedPMI","ReportedCRI","FrozenNumLayers","FrozenPMI","FrozenCSIResourceIndex"]
    for value=[NaN f.(name)+1]
        bad=e; bad.FrozenApplication.(name)=value;
        writeCompletedCSI(path,bad,1); before=sixgr.util.sha256File(path);
        out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
        assert(~pass(out,'completed_csi_application') && ...
            out.Checks.Status(out.Checks.CheckID=="completed_csi_application")=="IDENTITY_MISMATCH", ...
            'Missing or inconsistent selected CSI operand must fail: %s',name);
        assert(sixgr.util.sha256File(path)==before,'Evaluator must preserve the original evidence.');
    end
end
writeCompletedCSI(path,e,2);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'completed_csi_application'),'Completed layer count must match its frozen selection.');
bad=e; bad.FrozenApplication.ObservationID='wrong_observation'; writeCompletedCSI(path,bad,1);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'completed_csi_application'),'Frozen observation substitution must fail.');
writeCompletedCSI(path,e,1);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'completed_csi_application')&&pass(out,'primary_pdsch')&&~out.Ok);
assert(out.RadioOutcomes.CRCFailCount(out.RadioOutcomes.Signal=="pdsch")==1, ...
    'A measured NACK remains a valid radio result with correct application provenance.');
end

function writeCompletedCSI(path,e,layers)
token=string(jsonencode(e));
hash=string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8'))));
T=table("gate_unit","gate_execution",string(repmat('a',1,64)),1,0,0,0,layers, ...
    1,token,hash,string(e.AdmittedCSI.ReportIdentity),string(e.AdmittedCSI.ObservationID), ...
    'VariableNames',{'RunID','ExecutionID','ConfigHash','CRCApplicable','CRCPass','Crash', ...
    'FallbackFlag','Layers','CompletedCSIApplicationVerified','CompletedCSIApplicationEvidenceJSON', ...
    'CompletedCSIApplicationEvidenceSHA256','CompletedCSIApplicationReportIdentity', ...
    'CompletedCSIApplicationReportObservationID'});
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
end

function testExecutedMCSTransitions(root)
% Authored parser evidence, deliberately incomplete: never a full gate pass.
policy=struct('enabled',true,'max_up_step',1,'max_down_step',2,'increase_ack_count',2);
path=fullfile(root,'meta','scenario_config_resolved.json');
sixgr.util.jsonWrite(path,struct('TestFixture',true, ...
    'frame_timing',struct('slot_duration_ms',1), ...
    'link_adaptation',struct('mcs_transition',policy,'bootstrap_mcs_index',1)));
sixgr.util.jsonWrite(fullfile(root,'meta','scenario_config_identity.json'), ...
    struct('ConfigHash',repmat('a',1,64),'ResolvedJSONSHA256',sixgr.util.sha256File(path)));
dl=mcsFixtureSequence("DL"); ul=mcsFixtureSequence("UL");
writeMCSSequence(root,"DL",dl); writeMCSSequence(root,"UL",ul);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'executed_mcs_transitions')&&~out.Ok,'%s',checkDetail(out,'executed_mcs_transitions'));
% The first authored DL data CRC is zero while its independently authored
% received UCI is ACK. The gate must use the latter for DL policy credits.
for variant=1:11
    bad=dl;
    switch variant
        case 1, bad(3).ACKIdentities(1)="DL|cell=1|rnti=101|slot=99|pid=1";
        case 2, bad(3).EffectivePreviousMCS=2; bad(3).PreviousCommittedMCS=2;
        case 3, bad(3).PolicySelectedMCS=4; bad(3).AppliedMCS=4;
        case 4, bad(3).GrantContextId="foreign_grant";
        case 5, bad(3).MaxUpStep=2;
        case 8, bad(3).SpatialPoint="different_original_operator";
        case 10, bad(4).NACKIdentities=bad(2).ACKIdentities;
        case 11, bad(4).PolicySelectedMCS=2; bad(4).AppliedMCS=2;
    end
    writeMCSSequence(root,"DL",bad); writeMCSSequence(root,"UL",ul);
    if any(variant==[6 7])
        feedbackPath=fullfile(root,'control','csv','gnb_harq_feedback_observations.csv');
        F=readtable(feedbackPath,'TextType','string','VariableNamingRule','preserve');
        if variant==6, F.FeedbackOutcome(1)="NACK";
        else, F.AvailableAtSample(1)=999999; end
        sixgr.util.csvWriteTable(feedbackPath,F,'PreserveSchema',true);
    elseif variant==9
        feedbackPath=fullfile(root,'harq','csv','runtime_harq_process_timeline.csv');
        F=readtable(feedbackPath,'TextType','string','VariableNamingRule','preserve');
        F.CurrentDecodeOK(1)=0;
        sixgr.util.csvWriteTable(feedbackPath,F,'PreserveSchema',true);
    end
    primaryPath=fullfile(root,'air_interface','csv','dl_pdsch_trials.csv');
    before=sixgr.util.sha256File(primaryPath);
    out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
    assert(~pass(out,'executed_mcs_transitions')&&sixgr.util.sha256File(primaryPath)==before, ...
        'Invalid original MCS/feedback evidence variant %d was accepted or rewritten.',variant);
end
writeMCSSequence(root,"DL",dl); writeMCSSequence(root,"UL",ul);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'executed_mcs_transitions'),'%s',checkDetail(out,'executed_mcs_transitions'));
end

function E=mcsFixtureSequence(direction)
scope=direction+"|cell=1|rnti=101";
e=struct('Enabled',true,'Direction',direction,'RNTI',101,'ServingCell',1,'DataSlot',1, ...
    'DecisionSlot',1,'GrantContextId',"",'RawTargetMCS',24,'ScopeKey',scope, ...
    'SpatialPoint',"declared_parser_operator",'OperatingPointGeneration',0, ...
    'PreviousCommittedMCS',NaN,'EffectivePreviousMCS',1,'PolicySelectedMCS',1,'AppliedMCS',1, ...
    'FinalCapacityReduction',false,'MaxUpStep',1,'MaxDownStep',2,'RequiredACKCount',2, ...
    'ACKCount',0,'NACKCount',0,'ACKIdentities',strings(0,1),'NACKIdentities',strings(0,1), ...
    'RawTargetAuthority',"authored_parser_target",'Reason',"hold_without_current_point_ACK_confirmation");
E=repmat(e,4,1); slots=[1 3 5 7]; applied=[1 1 2 0]; previous=[NaN 1 1 2]; generation=[0 1 1 2];
for k=1:4
    E(k).DataSlot=slots(k); E(k).DecisionSlot=slots(k);
    E(k).GrantContextId="fixture_"+direction+"_"+slots(k);
    E(k).AppliedMCS=applied(k); E(k).PolicySelectedMCS=applied(k);
    E(k).PreviousCommittedMCS=previous(k); E(k).OperatingPointGeneration=generation(k);
    if k>1, E(k).EffectivePreviousMCS=previous(k); end
end
E(2).ACKCount=1; E(2).ACKIdentities=scope+"|slot=1|pid=1";
E(3).ACKCount=2; E(3).ACKIdentities=[scope+"|slot=1|pid=1";scope+"|slot=3|pid=3"];
E(3).Reason="received_ACK_confirmed_up_step";
E(4).NACKCount=1; E(4).NACKIdentities=scope+"|slot=5|pid=1"; E(4).Reason="received_NACK_down_step";
end

function writeMCSSequence(root,direction,E)
rows=cell(numel(E),1); feedbackRows=cell(numel(E),1); slots=[1 3 5 7]; crc=[1 1 0 1];
for k=1:numel(E)
    slot=slots(k); context="fixture_"+direction+"_"+slot;
    token=string(jsonencode(E(k))); actualCRC=crc(k);
    if direction=="DL"&&k==1, actualCRC=0; end
    rows{k}=struct('RunID',"gate_unit",'ExecutionID',"gate_execution", ...
        'ConfigHash',string(repmat('a',1,64)),'Slot',slot,'RNTI',101,'ServingCell',1, ...
        'GrantContextId',context,'HarqID',mod(slot,4),'MCSIndex',E(k).AppliedMCS, ...
        'IsRetransmission',0,'MCSTransitionReceiptJSON',token, ...
        'MCSTransitionReceiptSHA256',string(sixgr.util.sha256Hex(token)), ...
        'MCSTransitionAppliedMCS',E(k).AppliedMCS,'CRCApplicable',1,'CRCPass',actualCRC, ...
        'Crash',0,'FallbackFlag',0,'HARQFeedbackDueSlot',slot+1, ...
        'DataDecodeAvailableAtSample',(slot-1)*1000+800,'DataReceiveSampleRateHz',1e6);
    if direction=="DL"
        outcome="ACK"; if crc(k)==0, outcome="NACK"; end
        feedbackRows{k}=struct('SourceSlot',slot,'RNTI',101,'ServingCell',1,'HarqID',mod(slot,4), ...
            'PHYGrantContextId',context,'FeedbackOutcome',outcome,'HARQFeedbackApplied',1, ...
            'ReceiverUsable',1,'StaleFeedbackIgnored',0,'DecodeAttempted',1, ...
            'ReceiverExecutionStatus',"executed",'IsRetransmission',0,'DueSlot',slot+1, ...
            'Slot',slot+1,'AvailableAtSample',slot*1000,'ObservationSampleRateHz',1e6);
    else
        feedbackRows{k}=struct('Direction',"UL",'RNTI',101,'Slot',slot,'HarqID',mod(slot,4), ...
            'PHYGrantContextId',context,'IsRetransmission',0,'CurrentDecodeOK',crc(k), ...
            'FeedbackDueSlot',slot+1,'DataDecodeAvailableAtSample',(slot-1)*1000+800, ...
            'DataReceiveSampleRateHz',1e6,'FeedbackMechanism',"gnb_pusch_decoder", ...
            'FeedbackEvidenceSource',"same_waveform_pusch_rx_crc");
    end
end
file="dl_pdsch_trials.csv"; feedbackPath=fullfile(root,'control','csv','gnb_harq_feedback_observations.csv');
if direction=="UL"
    file="ul_pusch_trials.csv"; feedbackPath=fullfile(root,'harq','csv','runtime_harq_process_timeline.csv');
end
if ~isfolder(fileparts(feedbackPath)), mkdir(fileparts(feedbackPath)); end
T=struct2table(vertcat(rows{:}));
sixgr.util.csvWriteTable(fullfile(root,'air_interface','csv',file),T,'PreserveSchema',true);
sixgr.util.csvWriteTable(feedbackPath,struct2table(vertcat(feedbackRows{:})),'PreserveSchema',true);
end

function testParentPublication()
root=tempname; mkdir(fullfile(root,'reports','csv')); mkdir(fullfile(root,'reports','image'));
labels=["reference_esn0_20_db";"reference_esn0_0_db"];
roles=["scenario_identity","resolved_configuration","scenario_summary","dl_waveform_trials","ul_waveform_trials"];
rows=repmat(struct('Label',"",'PointRunID',"",'PointConfigHash',"", ...
    'ArtifactRole',"",'RelativePath',"",'Bytes',0,'SHA256',"", ...
    'EvidenceClass',"",'ParentPrimaryWaveformRowsCopied',false),0,1);
S=table(); points=strings(2,1); sources=points;
for j=1:2
    child=fullfile(root,'sweeps',labels(j)); mkdir(fullfile(child,'meta'));
    I=struct('RunID',"child_"+j,'ExecutionID',"exec_"+j,'ConfigHash',repmat(char('a'+j-1),1,64));
    sixgr.util.jsonWrite(fullfile(child,'meta','execution_identity.json'),I);
    S=[S;table(labels(j),string(child),true,true,I.RunID,string(I.ConfigHash), ...
        'VariableNames',{'Label','RunFolder','Returned','Ok','RunID','ConfigHash'})]; %#ok<AGROW>
    for k=1:5
        rel="sweeps/"+labels(j)+"/"+roles(k)+".csv"; path=fullfile(root,rel);
        sixgr.util.csvWriteTable(path,table(j,'VariableNames',{'FixtureValue'})); d=dir(path);
        rows(end+1)=struct('Label',labels(j),'PointRunID',I.RunID,'PointConfigHash',string(I.ConfigHash), ...
            'ArtifactRole',roles(k),'RelativePath',rel,'Bytes',d.bytes,'SHA256',sixgr.util.sha256File(path), ...
            'EvidenceClass',"measured_child_run_artifact",'ParentPrimaryWaveformRowsCopied',false); %#ok<AGROW>
    end
    points(j)="["+j+", "+string(jsonencode(char(labels(j))))+", ""passed"", "+sprintf('%.1f',20*(2-j))+"]";
    sources(j)="["+j+", "+string(jsonencode(char(sixgr.util.sha256File(fullfile(child,'scenario_summary.csv')))))+"]";
end
sixgr.util.csvWriteTable(fullfile(root,'reports','csv','sweep_summary.csv'),S);
indexPath=fullfile(root,'reports','csv','sweep_artifact_index.csv');
index=struct2table(rows); sixgr.util.csvWriteTable(indexPath,index);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'sweep_artifact_index')&&~out.Ok,'%s',checkDetail(out,'sweep_artifact_index'));
index.PointRunID(1)="wrong_child"; sixgr.util.csvWriteTable(indexPath,index);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'sweep_artifact_index'));
index=struct2table(rows); sixgr.util.csvWriteTable(indexPath,index);
combined='reports/csv/combined.csv'; sixgr.util.csvWriteTable(fullfile(root,combined),table(1,'VariableNames',{'FixtureValue'}));
token='{"points": ['+strjoin(points,', ')+'], "sources": ['+strjoin(sources,', ')+'], "version": 3}';
M=table("scenario_summary.csv",string(combined),"1|2", ...
    string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8')))), ...
    string(sixgr.util.sha256File(fullfile(root,combined))),"written","cross_run_exact_rows", ...
    'VariableNames',{'SourceRelativePath','CombinedArtifact','SourcePoints','SourceSignature','OutputSHA256','Status','EvidenceClass'});
M=repmat(M,5,1);
for k=1:5
    M.SourceRelativePath(k)=roles(k)+".csv";
    for j=1:2
        sources(j)="["+j+", "+string(jsonencode(char(sixgr.util.sha256File(fullfile(root,'sweeps',labels(j),roles(k)+".csv")))))+"]";
    end
    token='{"points": ['+strjoin(points,', ')+'], "sources": ['+strjoin(sources,', ')+'], "version": 3}';
    M.SourceSignature(k)=string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8'))));
end
sixgr.util.csvWriteTable(fullfile(root,'reports','csv','sweep_comparison_manifest.csv'),M);
plots=["sweep_link_comparison.png","sweep_bler_vs_configured_snr.png","sweep_bler_vs_measured_sinr.png"];
for name=plots, imwrite(uint8(zeros(2,2)),fullfile(root,'reports','image',name)); end
P=table(string(combined),"reports/image/"+plots(1),1, ...
    'VariableNames',{'CampaignCSV','CampaignPNG','ObservedRowCount'});
sixgr.util.csvWriteTable(fullfile(root,'reports','csv','sweep_measurement_plot_manifest.csv'),P);
sixgr.util.jsonWrite(fullfile(root,'reports','sweep_comparison_receipt.json'), ...
    struct('Complete',true,'CompletedPoints',2,'TotalPoints',2,'FailedArtifacts',0,'ArtifactCount',5,'StandardizedMeasurementPlotCount',1));
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'sweep_comparative_publication')&&~out.Ok,'%s',checkDetail(out,'sweep_comparative_publication'));
sixgr.util.csvWriteTable(fullfile(root,rows(3).RelativePath),table(99,'VariableNames',{'FixtureValue'}));
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'sweep_artifact_index')&&~pass(out,'sweep_comparative_publication'),'Stale child hashes must fail.');
end

function message=checkDetail(out,id)
selected=out.Checks(out.Checks.CheckID==id,:);
message="Fixture "+out.RunFolder+"; "+strjoin(selected.Status+": "+selected.Detail,'; ');
end

function testOriginalCSIBinding(root)
% Explicit parser/contract fixture only; it does not qualify integration.
b=struct('SourceSlot',6,'ServingCell',1,'SampleRateHz',30720000,'PhysicalConfigurationEpoch',1);
T=table(6,1,1,1,"ue_1_rx",30720000,1,string(jsonencode(b)),true,false, ...
    "awaiting_received_DL_acquisition_and_configuration","", ...
    'VariableNames',{'Slot','UEIndex','ServingCell','CellID','ReceiverID', ...
    'ObservationSampleRateHz','MeasurementClockEpoch','CSIObservationPopulationBindingJSON', ...
    'DLMeasurementAuthorityRequired','DLMeasurementAuthorityEligible', ...
    'DLMeasurementAuthorityStatus','DLMeasurementInstallationSHA256'});
plane=struct('ContractVersion',"sixgr.csirs.original_measurement_plane/v1", ...
    'ReceiverID',"ue_1_rx",'ReceiverWindowID',"fixture_window", ...
    'ObservationStartSample',100,'ObservationEndSampleExclusive',200,'SampleRateHz',30720000);
T.PhysicalMeasurementPlaneBindingJSON=string(jsonencode(plane));
T.PhysicalMeasurementPlaneBindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(char(T.PhysicalMeasurementPlaneBindingJSON),'UTF-8'))));
T.ReceiverWindowID="fixture_window"; T.ObservationStartSample=100; T.ObservationEndSampleExclusive=200;
path=fullfile(root,'air_interface','csv','csi_rs_trials.csv');
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'original_csi_binding')&&~out.Ok,'%s',checkDetail(out,'original_csi_binding'));
T.DLMeasurementInstallationSHA256=string(repmat('c',1,64));
T.DLMeasurementAuthorityStatus="diagnostic_observation_started_before_configuration_installation";
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'original_csi_binding'),'Installation presence must not force early observation eligibility.');
T.DLMeasurementAuthorityStatus="DL_measurement_not_yet_available";
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'original_csi_binding'),'A pending receiver result remains a legitimate diagnostic.');
T.DLMeasurementAuthorityStatus="missing_original_DL_measurement_configuration_binding";
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
before=sixgr.util.sha256File(path);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'original_csi_binding')&&sixgr.util.sha256File(path)==before, ...
    'Later populated ServingCell must not conceal missing original binding.');
T.DLMeasurementAuthorityStatus="post_installation_original_received_measurement";
T.DLMeasurementAuthorityEligible=true;
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(pass(out,'original_csi_binding'),'%s',checkDetail(out,'original_csi_binding'));
T.ServingCell=2;
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
out=sixgr.validation.evaluateN40IntegrationGate(root,'RequireContinuation',false);
assert(~pass(out,'original_csi_binding'),'Current-cell substitution must not overwrite original physical identity.');
end
