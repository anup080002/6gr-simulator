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
testParentPublication();
fprintf('N40_INTEGRATION_GATE_EVALUATOR_PASS incomplete_test_fixture=%s\n',root);
ok=true;
end
function value=pass(out,id)
hit=out.Checks.CheckID==id; assert(nnz(hit)==1); value=out.Checks.Passed(hit);
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
