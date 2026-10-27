function report=diagnoseN40FailedRunReports(original,output,priorAttempt)
% Read-only original-table replay; no PHY, RNG/channel replay or checkpoint load.
arguments
    original (1,1) string
    output (1,1) string
    priorAttempt (1,1) string=""
end
setup6GRSimToolkit('Verbose',false);
original=string(sixgr.util.canonicalPath(original));
output=string(sixgr.util.canonicalPath(output));
assert(isfolder(original)&&~isfolder(output)&&~startsWith(lower(output),lower(original)+filesep), ...
    'test:DiagnosticFolderExists','Use a new separate diagnostic destination.');
mkdir(output);
inputs=table(strings(0,1),strings(0,1),zeros(0,1),strings(0,1), ...
    'VariableNames',{'RelativePath','OriginalPath','Bytes','SHA256Before'});
stages=table(strings(0,1),false(0,1),strings(0,1),strings(0,1), ...
    'VariableNames',{'Stage','Passed','ErrorIdentifier','Detail'});
configuration=take("meta/scenario_config_resolved.json",true);
identity=jsondecode(fileread(take("meta/scenario_config_identity.json",true)));
execution=jsondecode(fileread(take("meta/execution_identity.json",true)));
assert(string(sixgr.util.sha256File(configuration))==string(identity.ResolvedJSONSHA256)&& ...
    string(execution.ConfigHash)==string(identity.ConfigHash),'test:OriginalConfigHash');
cfg=sixgr.lls6g.buildInternalConfig(jsondecode(fileread(configuration)),output);
cfg.meta.configHash=char(identity.ConfigHash);
cfg.run.runTag=char(execution.RunID); cfg.run.executionID=char(execution.ExecutionID);
cfg.meta.executionID=char(execution.ExecutionID); cfg.run.rootRunFolder=char(output);
domains=["DL","UL","PBCH","PRACH","PDCCH","PUCCH","SRS","CSIRS","TRS"];
names=["dl_pdsch","ul_pusch","pbch","prach","pdcch","pucch","srs","csi_rs","trs"];
raw=struct();
for k=1:numel(domains)
    relative="air_interface/csv/"+names(k)+"_trials.csv";
    if ~isfile(fullfile(original,relative)), continue; end
    raw.(domains(k))=sixgr.util.csvReadTable(take(relative,true),'TextType','string');
    T=raw.(domains(k));
    if ~isempty(T)&&ismember('ConfigHash',T.Properties.VariableNames)
        assert(all(string(T.ConfigHash)==string(identity.ConfigHash)),'test:OriginalTableScope');
    end
end
assert(height(raw.DL)==12&&height(raw.UL)==1,'test:OriginalTrialPopulation');
raw.RAEvidenceTables.ra_runtime_stage_waveforms=sixgr.util.csvReadTable( ...
    take("control/csv/ra_runtime_stage_waveforms.csv",true),'TextType','string');
priorBinding=struct();
if strlength(priorAttempt)==0
% Compact original RF manifests retain their referenced small model bindings.
for pattern=["rf/csv/rf_endpoint_*","rf/mat/rf_endpoint_*"]
    files=dir(fullfile(original,pattern)); files=files(~[files.isdir]);
    for k=1:numel(files)
        path=string(fullfile(files(k).folder,files(k).name));
        take(extractAfter(path,strlength(original)+1),true);
    end
end
for relative=["components/frame_grid/csv/observed_re_allocation.csv", ...
        "components/frame_grid/csv/observed_prach_native_allocation.csv", ...
        "components/frame_grid/csv/observed_ssb_native_allocation.csv"]
    if isfile(fullfile(original,relative)), take(relative,false); end
end
energy=[]; resources=[];
runStage("retained_resource_loader",@loadResources);
runStage("energy_csv_representation",@energyCSV);
runStage("energy_native_logical_representation",@energyNative);
runStage("live_derived_reports",@derived);
else
    % Reconcile only the optional scheduler audit after a prior real replay.
    % Bind its successful evidence explicitly; never pretend it reran here.
    priorReceipt=fullfile(priorAttempt,'receipt.json');
    prior=jsondecode(fileread(priorReceipt));
    assert(string(prior.OriginalFolder)==original&&prior.OriginalsUnchanged&& ...
        prior.DLRows==12&&prior.ULRows==1&&string(prior.ConfigHash)==string(identity.ConfigHash), ...
        'test:PriorReplayScope');
    required=["retained_resource_loader","energy_csv_representation", ...
        "energy_native_logical_representation","live_derived_reports"];
    for name=required
        match=prior.Stages(string({prior.Stages.Stage})==name);
        assert(isscalar(match)&&match.Passed,'test:PriorReplayStage');
        stages(end+1,:)={name,true,"","prior_actual_replay_hash_bound_not_reexecuted"};
    end
    priorInputs=sixgr.util.csvReadTable(fullfile(priorAttempt,'input_hashes.csv'),'TextType','string');
    for k=1:height(priorInputs)
        path=take(priorInputs.RelativePath(k),false);
        assert(string(sixgr.util.sha256File(path))==string(priorInputs.SHA256After(k))&& ...
            string(priorInputs.SHA256Before(k))==string(priorInputs.SHA256After(k)), ...
            'test:PriorReplayOriginalChanged');
    end
    artifacts=["receipt.json","replay_stages.csv","input_hashes.csv", ...
        "original_common_energy_observations.csv","derived_population_reconciliation.csv", ...
        "reports/csv/live_link_adaptation_input_table.csv", ...
        "reports/csv/live_symbol_throughput_table.csv","reports/csv/live_error_rate_summary.csv"];
    hashes=strings(numel(artifacts),1);
    for k=1:numel(artifacts), hashes(k)=sixgr.util.sha256File(fullfile(priorAttempt,artifacts(k))); end
    priorBinding=struct('OriginalDiagnosticFolder',priorAttempt, ...
        'Artifacts',{cellstr(artifacts)},'SHA256',{cellstr(hashes)}, ...
        'Scope',"four_successful_actual_prior_stages_plus_new_scheduler_reconciliation_no_PHY");
end
runStage("retained_scheduler_summary_reconciliation",@scheduler);
inputs.SHA256After=strings(height(inputs),1);
for k=1:height(inputs), inputs.SHA256After(k)=sixgr.util.sha256File(inputs.OriginalPath(k)); end
unchanged=all(inputs.SHA256Before==inputs.SHA256After);
sixgr.util.csvWriteTable(fullfile(output,'input_hashes.csv'),inputs,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(output,'replay_stages.csv'),stages,'PreserveSchema',true);
report=struct('OriginalFolder',original,'DiagnosticFolder',output,'Ok',all(stages.Passed)&&unchanged, ...
    'OriginalsUnchanged',unchanged,'DLRows',height(raw.DL),'ULRows',height(raw.UL), ...
    'RunID',execution.RunID,'ExecutionID',execution.ExecutionID,'ConfigHash',identity.ConfigHash, ...
    'PhysicalReplayExecuted',false,'NativeCheckpointLoaded',false,'PrimaryStudyEligible',false, ...
    'Scope',"derived_report_replay_of_original_failed_run_tables_not_completed_run_or_new_PHY", ...
    'Stages',table2struct(stages),'PriorReplayBinding',priorBinding);
sixgr.util.jsonWrite(fullfile(output,'receipt.json'),report);
assert(unchanged,'test:OriginalReportsChanged');
fprintf('N40_FAILED_REPORT_REPLAY ok=%d DL=12 UL=1 originals_unchanged=%d output=%s\n',report.Ok,unchanged,output);

    function path=take(relative,copy)
        relative=replace(string(relative),'\','/'); path=fullfile(original,relative);
        assert(isfile(path),'test:MissingOriginalInput','Missing %s.',relative);
        if ~any(inputs.RelativePath==relative)
            info=dir(path); inputs(end+1,:)={relative,path,info.bytes,string(sixgr.util.sha256File(path))};
        end
        if copy
            destination=fullfile(output,relative); parent=fileparts(destination);
            if ~isfolder(parent), mkdir(parent); end
            copyfile(path,destination);
            assert(sixgr.util.sha256File(destination)==inputs.SHA256Before(inputs.RelativePath==relative), ...
                'test:DiagnosticCopyIntegrity');
        end
    end
    function runStage(name,action)
        fprintf('REPORT_REPLAY_STAGE_START %s\n',name);
        try
            action(); stages(end+1,:)={name,true,"","completed_original_table_replay"};
        catch cause
            stages(end+1,:)={name,false,string(cause.identifier),string(getReport(cause,'extended','hyperlinks','off'))};
            fprintf('REPORT_REPLAY_STAGE_FAILED %s %s\n',name,cause.identifier);
        end
        sixgr.util.csvWriteTable(fullfile(output,'replay_stages.csv'),stages,'PreserveSchema',true);
    end
    function loadResources()
        [resources,~,audit]=sixgr.truth.loadLLSEnergyResourceEvidence(cfg,fullfile(original,'air_interface'),raw);
        assert(~isempty(resources)&&resources.ConfigHash==string(identity.ConfigHash));
        sixgr.util.jsonWrite(fullfile(output,'resource_read_audit.json'),audit);
    end
    function energyCSV()
        assert(~isempty(resources),'test:NoExecutedResourceEvidence');
        energy=sixgr.truth.exportLLSEnergyDiagnostics(cfg,fullfile(output,'air_interface'),raw,resources);
        sixgr.util.csvWriteTable(fullfile(output,'original_common_energy_observations.csv'),energy.CommonSignalObservations);
    end
    function energyNative()
        assert(~isempty(energy),'test:MissingCSVRepresentationComparison');
        native=raw;
        for field=["RuntimeStageWaveformUsed","SelfLoopWaveformUsed"]
            native.RAEvidenceTables.ra_runtime_stage_waveforms.(field)=logicalColumn( ...
                native.RAEvidenceTables.ra_runtime_stage_waveforms.(field));
        end
        for domain=["PRACH","PBCH"]
            T=native.(domain);
            fields=["Msg2DCICrcPass","Msg2PDSCHCrcPass","Msg3PUSCHCrcPass", ...
                "Msg4PDCCHCrcPass","Msg4PDSCHCrcPass","RRCSetupCompleteCRC"];
            if domain=="PBCH", fields=["SIB1DCICrcPass","SIB1DLSCHCrcPass"]; end
            for field=fields
                value=T.(field);
                assert((isnumeric(value)||islogical(value))&& ...
                    all(isnan(value)|value==0|value==1,'all'),'test:OriginalBooleanEncoding');
                % Unattempted SIB1/RA outcomes remain unavailable. A MATLAB
                % logical column cannot represent NaN; retain its exact
                % numeric representation instead of inventing failed CRCs.
                if all(isfinite(value),'all'), T.(field)=logicalColumn(value); end
            end
            native.(domain)=T;
        end
        actual=sixgr.truth.exportLLSEnergyDiagnostics(cfg,fullfile(output,'air_interface'),native,resources);
        assert(isequaln(actual.CommonSignalObservations,energy.CommonSignalObservations), ...
            'test:NativeCSVReportMismatch');
    end
    function derived()
        sixgr.truth.exportLLSLiveDerivedTables(cfg,output,raw,struct(),struct(),struct());
        T=sixgr.util.csvReadTable(fullfile(output,'reports','csv','live_link_adaptation_input_table.csv'),'TextType','string');
        assert(height(T)==13&&nnz(string(T.Direction)=="DL")==12&&nnz(string(T.Direction)=="UL")==1, ...
            'test:DerivedTrialPopulation');
        S=sixgr.util.csvReadTable(fullfile(output,'reports','csv','live_symbol_throughput_table.csv'),'TextType','string');
        assert(~isempty(S),'test:MissingDerivedThroughput');
        counts=[nnz(string(T.Direction)=="DL");nnz(string(T.Direction)=="UL")];
        bits=[sum(raw.DL.TBSize_bits);sum(raw.UL.TBSize_bits)];
        exported=[sum(S.ScheduledDLBits,'omitnan');sum(S.ScheduledULBits,'omitnan')];
        assert(isequal(counts,[12;1])&&all(abs(bits-exported)<=1e-10*max(1,bits)), ...
            'test:DerivedScheduledBitsMismatch');
        audit=table(["DL";"UL"],counts,bits,exported, ...
            'VariableNames',{'Direction','ActualTrialRows','OriginalTBSBits','DerivedScheduledBits'});
        sixgr.util.csvWriteTable(fullfile(output,'derived_population_reconciliation.csv'),audit,'PreserveSchema',true);
    end
    function scheduler()
        % The production scheduler summary builder is private to the live
        % runtime exporter. This independently checks its retained grouping;
        % it does not fabricate native scheduler state or republish a summary.
        D=sixgr.util.csvReadTable(take("packet_flow/csv/scheduler_decision_log.csv",true),'TextType','string');
        S=sixgr.util.csvReadTable(take("packet_flow/csv/scheduler_ue_summary.csv",true),'TextType','string');
        checks=table(strings(0,1),zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1),false(0,1), ...
            'VariableNames',{'Direction','UEIndex','Field','Retained','Recomputed','Passed'});
        covered=false(height(D),1);
        for k=1:height(S)
            selected=string(D.Direction)==string(S.Direction(k))&D.UEIndex==S.UEIndex(k)&D.RNTI==S.RNTI(k);
            assert(any(selected)&&~any(covered(selected)),'test:SchedulerSummaryGrouping');
            covered=covered|selected;
            blocked=false(height(D),1);
            if ismember('HARQBlocked',D.Properties.VariableNames), blocked=logicalColumn(D.HARQBlocked); end
            if ismember('RejectionReason',D.Properties.VariableNames)
                blocked=blocked|string(D.RejectionReason)=="HARQ_ALL_PROCESSES_BUSY";
            end
            expected=struct('CandidateCount',nnz(selected), ...
                'ScheduledGrantCount',sum(D.Scheduled(selected)), ...
                'RejectedCount',sum(D.Rejected(selected)), ...
                'HARQBlockedCount',nnz(blocked&selected), ...
                'ScheduledFrac',sum(D.Scheduled(selected))/max(1,sum(D.Scheduled(string(D.Direction)==string(S.Direction(k))))), ...
                'MeanPFMetric',mean(D.PFMetric(selected),'omitnan'), ...
                'MeanInstantRate_bps',mean(D.InstantRate_bps(selected),'omitnan'), ...
                'MeanAvgThroughput_bps',mean(D.AvgThroughput_bps(selected),'omitnan'));
            for field=string(fieldnames(expected)).'
                a=S.(field)(k); b=expected.(field);
                passed=isequaln(a,b)||(isfinite(a)&&isfinite(b)&&abs(a-b)<=1e-12*max(1,abs(b)));
                checks(end+1,:)={string(S.Direction(k)),S.UEIndex(k),field,a,b,passed};
            end
        end
        sixgr.util.csvWriteTable(fullfile(output,'scheduler_summary_reconciliation.csv'),checks,'PreserveSchema',true);
        assert(all(covered)&&all(checks.Passed),'test:SchedulerSummaryMismatch');
    end
end

function value=logicalColumn(value)
assert((isnumeric(value)||islogical(value))&&all(isfinite(value),'all')&& ...
    all(value==0|value==1,'all'),'test:OriginalBooleanEncoding', ...
    'Only exact original CSV0/1 values can restore the producer logical representation.');
value=logical(value);
end
