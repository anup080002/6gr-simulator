function [ok,result]=testCSISelectionIdentityReporting(retainedCSV,runExporters)
% Declared reporting fixtures and optional original-CSV replay; NO PHY.
if nargin<1, retainedCSV=""; end
if nargin<2, runExporters=true; end
source=table([0;1;0;1],[17;29;17;29],[1;4;1;4],[3;14;3;14], ...
    [0;0;10;10],[1;1;2;2],[6;26;6;26],ones(4,1), ...
    ["book-a";"book-a";"book-b";"book-b"], ...
    'VariableNames',{'PMI','CRI','RI','CQI','ConfiguredSNR_dB','UEIndex','Slot','Frame','CodebookType'});
source.ResourceID=source.CRI; source.ResourceSetID=ones(4,1);
source.ReceiverID=["rx-a";"rx-a";"rx-b";"rx-b"];
source.FixtureScope=repmat("declared_metadata_no_PHY_execution",4,1);
source.DLMeasurementConfigurationFamily=repmat("CSI-RS",4,1);
source.DLMeasurementConfigurationSHA256=repmat(string(repmat('a',1,64)),4,1);
source.DLMeasurementNCellID=ones(4,1);
source.DLMeasurementInstallationSHA256=repmat(string(repmat('b',1,64)),4,1);
source.DLMeasurementAuthorityRequired=true(4,1);
source.DLMeasurementAuthorityEligible=[false;true;false;true];
source.DLMeasurementAuthorityStatus=["declared_diagnostic_only";"declared_eligible";"declared_diagnostic_only";"declared_eligible"];
source.DLMeasurementAuthoritySource=repmat("declared_metadata_fixture_not_runtime_proof",4,1);
original=source; savedRNG=rng;
observations=sixgr.report.collectCSISelectionObservations(source,["PMI","CRI","RI","CQI"], ...
    "air_interface/csv/csi_rs_trials.csv");
assert(height(observations)==16&&numel(unique(observations.PopulationID))==16&&isequaln(source,original));
checkObservations(observations,source);
assert(isempty(sixgr.report.collectCSISelectionObservations(source([],:),"PMI","fixture.csv")));
components=source(1:2,:); components.PMI=["[0,1]";"[1,0]"];
v=sixgr.report.collectCSISelectionObservations(components,"PMI","fixture.csv");
assert(isequal(v.ValueText,components.PMI)&&all(isnan(v.ValueNumeric)));
oriented=source(1:2,:); oriented.PMI={[0 1];[0;1]};
v=sixgr.report.collectCSISelectionObservations(oriented,"PMI","fixture.csv");
a=jsondecode(v.SupportConfigurationJSON(1)); b=jsondecode(v.SupportConfigurationJSON(2));
assert(isequal(a.OriginalValueSize(:),[1;2])&&isequal(b.OriginalValueSize(:),[2;1]));
anonymous=source([1 1],{'PMI','CRI'});
v=sixgr.report.collectCSISelectionObservations(anonymous,"PMI","fixture.csv");
assert(height(v)==2&&numel(unique(v.PopulationID))==2&&isequal(v.ValueNumeric,[0;0]));
a=jsondecode(v.PopulationJSON(1));
assert(~isfield(a,'CodebookType')&&~isfield(a,'ResourceID'), ...
    'Missing namespace must stay missing; duplicate rows remain distinct source observations.');
assert(~isfield(a,'DLMeasurementAuthorityEligible'), ...
    'Historical missing authority must not be inferred from a finite selection.');
missing=source; missing.PMI(:)=NaN;
assert(isempty(sixgr.report.collectCSISelectionObservations(missing,"PMI","fixture.csv")));
for badValue=[.5,-1,Inf]
    bad=source; bad.PMI(4)=badValue;
    reject(@()sixgr.report.collectCSISelectionObservations(bad,"PMI","fixture.csv"),'sixgr:report:SelectionValue');
end
bad=source; bad.CRI=[bad.CRI bad.CRI];
reject(@()sixgr.report.collectCSISelectionObservations(bad,"CRI","fixture.csv"),'sixgr:report:SelectionShape');
bad=source; bad.PMI=cellstr(string(bad.PMI)); bad.PMI{4}='true';
reject(@()sixgr.report.collectCSISelectionObservations(bad,"PMI","fixture.csv"),'sixgr:report:SelectionValue');
late=source(ones(257,1),:); late.PMI(257)=.5;
reject(@()sixgr.report.collectCSISelectionObservations(late,"PMI","fixture.csv"),'sixgr:report:SelectionValue');
assert(isequaln(savedRNG,rng));
result=struct('Scope',"declared_selection_metadata_no_PHY",'EvidenceRoot',"", ...
    'RetainedReplayRequested',strlength(string(retainedCSV))>0,'RetainedReplayRows',0,'PHYExecutions',0);
if strlength(string(retainedCSV))>0
    before=string(sixgr.util.sha256File(retainedCSV));
    actual=sixgr.report.readCSIPhysicalMeasurementTrials(retainedCSV);
    replay=sixgr.report.collectCSISelectionObservations(actual,["PMI","CRI","RI","CQI"], ...
        "air_interface/csv/csi_rs_trials.csv");
    checkObservations(replay,actual);
    assert(height(replay)>0&&before==string(sixgr.util.sha256File(retainedCSV)));
    result.RetainedReplayRows=height(replay);
end
if runExporters
    root=fullfile(pwd,'results','validation','csi_selection_identity',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
    assert(~isfolder(root),'Never overwrite previous evidence.');
    scfg=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
    assert(logical(scfg.get('output.artifact_contract_engine.enabled',false)), ...
        'This first publication must exercise the default contract-owned raster path.');
    cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
    cfg.run.runTag=''; cfg.run.executionID=''; cfg.meta.configHash='';
    live=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,struct('CSIRS',source));
    checkObservations(live.CSISelectionObservations,source);
    assert(all(isnan(live.CSIRSStats.MeanPMI))&&all(isnan(live.CSIRSStats.MeanCRI))&& ...
        all(live.CSIRSStats.MeanPMIStatus=="not_applicable_discrete_identity_mean_removed"));
    persisted=sixgr.util.csvReadTable(live.CSISelectionObservationsPath,'TextType','string');
    assert(isequal(string(persisted.PopulationJSON),live.CSISelectionObservations.PopulationJSON));
    layout=sixgr.report.resultLayout(root);
    path=fullfile(layout.AirInterfaceCSVDir,'csi_rs_trials.csv');
    sixgr.util.csvWriteTable(path,source,'PreserveSchema',true,'RoundTripNumericText',true);
    originalHash=string(sixgr.util.sha256File(path));
    % Applied Layers are source data; receiver RI must not replace them.
    dl=table([1;4],[1;0],repmat("DL",2,1),["PASS";"FAIL"],ones(2,1),(41:42).', ...
        [8;4],repmat("scheduler_shared_stream_receiver",2,1), ...
        'VariableNames',{'Layers','CRCPass','Direction','Status','Frame','Slot','Goodput_Mbps','ExecutionBackend'});
    for field=["FinalizedFlag","DecodeAttempted","DecodeUsable","CRCApplicable","DLSCHDecodeAttempted","DLSCHDecodeAvailable"]
        dl.(field)=ones(2,1);
    end
    for field=["PartialRowFlag","Crash","IsWarmupFrame"], dl.(field)=zeros(2,1); end
    dlPath=fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv');
    sixgr.util.csvWriteTable(dlPath,dl,'PreserveSchema',true,'RoundTripNumericText',true);
    dlHash=string(sixgr.util.sha256File(dlPath));
    manifest=struct('CodeVersion',"test",'CodeDetail',result.Scope,'RandomSeed',1, ...
        'GeneratedUTC',"test",'RunnerProfile',"test",'RunCompletion',"completed",'DeterministicMode',"test");
    report=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false),manifest, ...
        struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
    for field=["PMI","CRI","RI","CQI"]
        rows=report.CategoryRows(report.CategoryRows.MetricKey==lower(field),:);
        rows=rows(startsWith(rows.Entity,"CSI-selection-"),:);
        assert(height(rows)==4&&all(rows.Statistic=="observation")&& ...
            isequal(rows.ValueNumeric,source.(field))&&numel(unique(rows.PopulationID))==4);
    end
    checkRankGroups(layout);
    assert(~isfile(fullfile(layout.ReportImageDir,'applied_rank_kpi_diagnostics.png')), ...
        'Default contract authority must not produce a duplicate legacy MATLAB PNG.');
    assert(originalHash==string(sixgr.util.sha256File(path))&&dlHash==string(sixgr.util.sha256File(dlPath)));

    % A second, explicitly configured legacy-renderer fixture exercises the
    % PNG route. These are declared metadata rows, not another PHY execution.
    legacyRoot=fullfile(root,'legacy_raster');
    data=scfg.toStruct(); data.output.artifact_contract_engine.enabled=false;
    legacyScenario=sixgr.lls6g.config.ScenarioConfig(data);
    legacyCfg=sixgr.lls6g.buildInternalConfig(legacyScenario,legacyRoot);
    legacyCfg.run.runTag=''; legacyCfg.run.executionID=''; legacyCfg.meta.configHash='';
    legacyLayout=sixgr.report.resultLayout(legacyRoot);
    sixgr.util.ensureFolder(legacyLayout.AirInterfaceCSVDir);
    legacyCSIPath=fullfile(legacyLayout.AirInterfaceCSVDir,'csi_rs_trials.csv');
    legacyDLPath=fullfile(legacyLayout.AirInterfaceCSVDir,'dl_pdsch_trials.csv');
    sixgr.util.csvWriteTable(legacyCSIPath,source,'PreserveSchema',true,'RoundTripNumericText',true);
    sixgr.util.csvWriteTable(legacyDLPath,dl,'PreserveSchema',true,'RoundTripNumericText',true);
    legacyCSIHash=string(sixgr.util.sha256File(legacyCSIPath));
    legacyDLHash=string(sixgr.util.sha256File(legacyDLPath));
    sixgr.truth.exportLLSReportingBundle(legacyRoot,legacyScenario,legacyCfg,struct('Ok',false),manifest, ...
        struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
    checkRankGroups(legacyLayout);
    heat=sixgr.util.csvReadTable(fullfile(legacyLayout.ReportCSVDir,'heatmap_beam_rank_trp_kpi.csv'),'TextType','string');
    assert(all(contains(heat.RowLabel,'DL layers {1,4}'))&&~any(contains(heat.RowLabel,'R2.5')));
    assert(isfile(fullfile(legacyLayout.ReportImageDir,'applied_rank_kpi_diagnostics.png')));
    assert(legacyCSIHash==string(sixgr.util.sha256File(legacyCSIPath))&& ...
        legacyDLHash==string(sixgr.util.sha256File(legacyDLPath)));
    assert(originalHash==string(sixgr.util.sha256File(path))&&dlHash==string(sixgr.util.sha256File(dlPath)));
    result.EvidenceRoot=string(root);
    result.LegacyRasterEvidenceRoot=string(legacyRoot);
end
fprintf('CSI_SELECTION_IDENTITY_PASS declared_metadata=1 PHY_executions=0 retained_rows=%d root=%s\n', ...
    result.RetainedReplayRows,result.EvidenceRoot);
ok=true;
end

function checkRankGroups(layout)
rank=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'applied_rank_kpi_diagnostics.csv'),'TextType','string');
assert(height(rank)==2&&isequal(string(rank.Direction),["DL";"DL"])&& ...
    isequal(rank.AppliedLayers,[1;4])&&isequal(rank.CompletedAttemptBLER,[0;1])&& ...
    isequal(rank.CRCErrorCount,[0;1])&&all(rank.CompletedDecodeAttemptCount==1)&& ...
    all(rank.SourceObservationCount==1)&&~any(rank.StatisticalIndependenceClaimed));
for k=1:height(rank)
    assert(isequal(jsondecode(string(rank.SourceRowsJSON(k))),k));
end
assert(isequal(rank.MeanTrialThroughput_Mbps,[8;4]));
end

function checkObservations(observations,source)
for k=1:height(observations)
    row=observations(k,:); id=jsondecode(row.PopulationJSON);
    assert(string(sixgr.util.sha256Hex(char(row.PopulationJSON)))==row.PopulationID);
    assert(id.SourceRowIndex==row.SourceRowIndex&&string(id.SourceField)==row.SourceField);
    original=source.(row.SourceField)(row.SourceRowIndex,:);
    if isnumeric(original)&&isscalar(original), assert(row.ValueNumeric==original); end
    for field=["Slot","Frame","ConfiguredSNR_dB","UEIndex","ResourceID","ResourceSetID","RI"]
        if ismember(field,string(source.Properties.VariableNames))
            assert(isequaln(id.(field),source.(field)(row.SourceRowIndex,:)));
        end
    end
    for field=["DLMeasurementConfigurationFamily","DLMeasurementConfigurationSHA256", ...
            "DLMeasurementNCellID","DLMeasurementInstallationSHA256", ...
            "DLMeasurementAuthorityRequired","DLMeasurementAuthorityEligible", ...
            "DLMeasurementAuthorityStatus","DLMeasurementAuthoritySource"]
        if ismember(field,string(source.Properties.VariableNames))
            expected=source.(field)(row.SourceRowIndex,:);
            if isstring(expected)||ischar(expected)
                assert(isequal(string(id.(field)),string(expected)));
            else
                assert(isequaln(id.(field),expected));
            end
        else
            assert(~isfield(id,field));
        end
    end
end
end

function reject(fn,id)
try, fn(); catch cause, assert(string(cause.identifier)==id,cause.message); return; end
error('sixgr:test:MissingSelectionGuard','Expected %s.',id);
end
