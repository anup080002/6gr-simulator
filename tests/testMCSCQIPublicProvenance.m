function [ok,result]=testMCSCQIPublicProvenance()
% Declared publication-boundary fixtures; no PHY or calibrated CSI claims.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','mcs_cqi_public_provenance', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite retained evidence.');
sixgr.util.ensureFolder(folder);
meta=struct('logical_run_id',"declared_MCS_CQI_publication_fixture",'run_id',1);
contract=sixgr.truth.llsOutputContract();
source=table((1:4).',[3;7;7;0],[NaN;12;NaN;0], ...
    ["fixed_config";"received_csi_feedback";"";"received_csi_feedback"], ...
    ["qam64_table1";"qam64_table1";"";"qam64_table1"], ...
    ["";"table2";"";"table1"], ...
    'VariableNames',{'slot','mcs_selected','cqi_input','mcs_selection_source','mcs_table','cqi_table'});
source.cqi_source=["";"declared_decoded_CSI_fixture";"";"declared_CQI_out_of_range_fixture"];
source.calibration_profile=["";"declared_profile_identity_not_qualified";"";""];
source.CQICalibrationProfile=repmat("",4,1); % All-blank canonical CSV column.
source.mcs_value_status=["fixed";"measured_feedback_adapted";"";"measured_feedback_adapted"];
source.mcs_index_authority=["configured_index";"runtime_link_adaptation_decision";"";"runtime_link_adaptation_decision"];
source.grant_operating_point_source=["configured";"received_feedback";"";"received_feedback"];
source.link_adaptation_decision_reason=["fixed_mode";"received_report";"";"out_of_range_CQI"];
source.scheduler_grant_source=["declared_fixed_grant";"declared_adaptive_grant";"";"declared_adaptive_grant"];
source.source_artifact_ref=repmat("declared/path_not_a_scheduler_source.csv",4,1);
source.cqi_derived_mcs=[NaN;7;7;0];
snapshot=source; rngBefore=rng;
original=fullfile(folder,'table_mcs_tbs_evolution.csv');
sixgr.util.csvWriteTable(original,source,'PreserveSchema',true,'RoundTripNumericText',true);
digest=string(sixgr.util.sha256File(original));
% Use the production reader, including its inference for all-blank columns.
retained=sixgr.util.csvReadTable(original,'TextType','string');
published=project(retained);
for pair={"SelectedMCSSource","mcs_selection_source";"MCSTable","mcs_table"; ...
        "CQITable","cqi_table";"MCSValueStatus","mcs_value_status"; ...
        "MCSIndexAuthority","mcs_index_authority"; ...
        "GrantOperatingPointSource","grant_operating_point_source"; ...
        "LinkAdaptationDecisionReason","link_adaptation_decision_reason"; ...
        "CQISource","cqi_source";"CQICalibrationProfile","calibration_profile"; ...
        "SchedulerGrantSource","scheduler_grant_source"}.'
    assert(isequal(published.(pair{1}),source.(pair{2})), ...
        'Original decision provenance lost or invented: %s.',pair{1});
end
assert(isequaln(published.CQI,source.cqi_input) && ...
    isequal(published.SelectedMCS,source.mcs_selected));
assert(published.MCSMismatchStatus(3)=="unavailable" && ...
    isnan(published.SelectedSpectralEfficiency(3)) && isnan(published.BoundSpectralEfficiency(3)), ...
    'Missing MCS table cannot silently use qam64_table1 or claim index consistency.');
assert(published.MCSMismatchStatus(2)=="match" && isfinite(published.SelectedSpectralEfficiency(2)));
output=fullfile(folder,'mcs_cqi_decision_trace_table.csv');
sixgr.util.csvWriteTable(output,published,'PreserveSchema',true,'RoundTripNumericText',true);
outOpts=detectImportOptions(output,'Delimiter',',','VariableNamingRule','preserve');
outOpts=setvartype(outOpts,{'SelectedMCSSource','CQITable','CQICalibrationProfile','SchedulerGrantSource'},'string');
roundtrip=readtable(output,outOpts);
assert(roundtrip.SelectedMCSSource(2)==source.mcs_selection_source(2) && ...
    roundtrip.CQITable(2)=="table2" && ...
    roundtrip.CQICalibrationProfile(2)==source.calibration_profile(2));

% Missing columns, not merely blank cells: no heuristic/source/table claim.
minimal=source(:,{'slot','mcs_selected','cqi_input'});
p=project(minimal);
for name=["SelectedMCSSource","CQISource","CQICalibrationProfile","SchedulerGrantSource","CQITable","MCSTable"]
    assert(all(strlength(p.(name))==0),'Missing %s was fabricated.',name);
end
assert(all(isnan(p.SelectedSpectralEfficiency)));
% Explicit unknown canonical aliases may defer to actual populated aliases.
duplicate=source; duplicate.SelectedMCSSource=repmat("",4,1);
duplicate.CQICalibrationProfile=source.calibration_profile;
duplicate.CQITable=source.cqi_table;
p=project(duplicate);
assert(isequal(p.SelectedMCSSource,source.mcs_selection_source) && ...
    isequal(p.CQICalibrationProfile,source.calibration_profile));
for pair={"SelectedMCSSource","different_selection_owner"; ...
        "CQISource","different_CQI_owner";"CQICalibrationProfile","different_profile"; ...
        "CQITable","table1";"MCSTable","qam256_table2"; ...
        "SchedulerGrantSource","different_grant_owner"}.'
    bad=source; bad.(pair{1})=repmat("",4,1); bad.(pair{1})(2)=pair{2};
    reject(@()project(bad),'sixgr:report:MCSCQIProvenanceConflict');
end
bad=source; bad.CQISource=ones(4,1);
reject(@()project(bad),'sixgr:report:MCSCQIProvenanceType');
unknown=source; unknown.CQICalibrationProfile=nan(4,1);
p=project(unknown);
assert(isequal(p.CQICalibrationProfile,source.calibration_profile), ...
    'Only scalar numeric NaN from a blank import may remain unavailable.');
bad=source; bad.CQISource=repmat(["a","b"],4,1);
reject(@()project(bad),'sixgr:report:MCSCQIProvenanceShape');
checkOriginalGrantProducer(folder);
assert(isequaln(source,snapshot)&&isequaln(rngBefore,rng)&& ...
    digest==string(sixgr.util.sha256File(original)), ...
    'Public projection must not mutate original evidence or RNG.');
result=struct('EvidenceRoot',string(folder),'SourceSHA256',digest,'PHYExecutions',0, ...
    'Scope',"declared_original_CSV_to_actual_public_projection_and_CSV", ...
    'CalibrationQualified',false);
ok=true;
fprintf('MCS_CQI_PUBLIC_PROVENANCE_PASS original_rows=4 PHY_executions=0 root=%s\n',folder);

    function T=project(input)
        allTables=sixgr.truth.buildLLSPublicOutputTables( ...
            struct('table_mcs_tbs_evolution',input),contract,meta);
        T=allTables.mcs_cqi_decision_trace_table;
    end
end

function checkOriginalGrantProducer(parentFolder)
% Actual bounded producer route used by testDLMCSCQIConsistencyGate: two
% declared grant rows, no waveform/scenario or full report rendering.
folder=fullfile(parentFolder,'original_grant_producer');
inputDir=fullfile(folder,'packet_flow','csv'); sixgr.util.ensureFolder(inputDir);
hashes=strings(2,1); inputs=cell(2,1); directions=["DL","UL"];
for k=1:2
    direction=directions(k);
    g=table(direction,1,16+k,1,4660,1,"declared_fixture",false,1,10,7, ...
        "qam64_table1","table1",0,10,2,12,176, ...
        'VariableNames',{'Direction','Frame','Slot','UEIndex','RNTI','ServingCell', ...
        'GrantReason','IsRetransmission','HarqID','CQIUsed','MCSIndex', ...
        'MCSTable','CQITable','PRBStart','PRBCount','SymbolStart','NumSymbols','TBSBits'});
    g.MCSSelectionSource="declared_"+direction+"_selection";
    g.CQIProvenance="declared_"+direction+"_original_CQI_owner";
    g.SchedulerCQISource="declared_"+direction+"_scheduler_adjustment_owner";
    g.SchedulerCQIRawCQI=11; g.SchedulerAdjustedSINR_dB=12.25; g.SchedulerSINRBackoff_dB=1.5;
    g.GrantContextId="declared_"+direction+"_grant";
    g.FrozenGrantContextId="declared_"+direction+"_frozen";
    g=g([1;1;1],:);
    g.Slot=g.Slot+(0:2).';
    g.MCSTable(2)=""; g.CQITable(3)="";
    g.MCSIndex(2:3)=27; % Would falsely exceed a manufactured table1 CQI bound.
    inputs{k}=g;
    path=fullfile(inputDir,"live_"+lower(direction)+"_scheduler_grants.csv");
    sixgr.util.csvWriteTable(path,g,'PreserveSchema',true,'RoundTripNumericText',true);
    hashes(k)=sixgr.util.sha256File(path);
end
scfg=struct('ScenarioID',"declared_mcs_cqi_producer",'ConfigHash',"declared_not_PHY");
scfg.simulation.random_seed=1;
scfg.frequency=struct('center_frequency_hz',4e9,'bandwidth_hz',100e6);
scfg.frame.scs_khz=30;
cfg=struct('frequency',scfg.frequency,'run',struct('runTag',"declared_not_PHY"));
sixgr.truth.exportLLSOutputCoverageArtifacts(folder,scfg,cfg);
csvDir=fullfile(folder,'reports','csv');
base=sixgr.util.csvReadTable(fullfile(csvDir,'table_mcs_tbs_evolution.csv'),'TextType','string');
public=sixgr.util.csvReadTable(fullfile(csvDir,'mcs_cqi_decision_trace_table.csv'),'TextType','string');
assert(height(base)==6&&height(public)==6);
for k=1:2
    direction=directions(k); g=inputs{k};
    b=base(base.direction==direction,:); p=public(public.Direction==direction,:);
    assert(height(b)==3&&height(p)==3);
    for name=["CQIProvenance","SchedulerCQISource","GrantContextId","FrozenGrantContextId", ...
            "SchedulerCQIRawCQI","SchedulerAdjustedSINR_dB","SchedulerSINRBackoff_dB"]
        assert(isequal(b.(name),g.(name))&&isequal(p.(name),g.(name)), ...
            'Original grant field lost or conflated in actual producer: %s.',name);
    end
    artifact="packet_flow/csv/live_"+lower(direction)+"_scheduler_grants.csv";
    assert(all(b.source_artifact_ref==artifact)&&all(p.GrantSourceArtifactRef==artifact)&& ...
        isequal(b.GrantSourceRow,(1:3).')&&isequal(p.GrantSourceRow,(1:3).')&& ...
        isequal(p.SelectedMCSSource,g.MCSSelectionSource));
    assert(isfinite(b.cqi_derived_mcs(1))&&all(isnan(b.cqi_derived_mcs(2:3)))&& ...
        all(isnan(p.CQIDerivedMCS(2:3)))&&all(p.MCSMismatchStatus(2:3)=="unavailable"), ...
        'Missing original MCS/CQI table must not manufacture a derived index or match.');
    assert(all(p.CQIProvenance~=p.SchedulerCQISource), ...
        'Original observation provenance and scheduler adjustment source are distinct.');
    for name=["CQISource","CQICalibrationProfile"]
        if ~ismember(name,string(p.Properties.VariableNames)), continue; end
        raw=p.(name);
        assert((isnumeric(raw)&&all(isnan(raw)))|| ...
            (isstring(raw)&&all(ismissing(raw)|strlength(raw)==0)), ...
            'Absent grant field must not be inferred from an unrelated receipt: %s.',name);
    end
    assert(hashes(k)==string(sixgr.util.sha256File(fullfile(folder,artifact))));
end
issues=sixgr.util.csvReadTable(fullfile(csvDir,'result_issue_registry.csv'),'TextType','string');
for direction=directions
    assert(~any(ismember(string(issues.issue_id), ...
        lower(direction)+"_mcs_above_cqi_"+string([2,3]))), ...
        'Missing original table identity cannot create a false MCS/CQI issue either.');
end
% Exercise generic CSV inference when an entire original table-name column
% is numeric NaN, not only a missing string within a populated column.
missingFolder=fullfile(parentFolder,'missing_original_table_imports');
missingDir=fullfile(missingFolder,'packet_flow','csv'); sixgr.util.ensureFolder(missingDir);
missingHashes=strings(2,1);
for k=1:2
    g=inputs{k}(1,:); g.MCSIndex=27;
    if k==1, g.MCSTable=NaN; else, g.CQITable=NaN; end
    path=fullfile(missingDir,"live_"+lower(directions(k))+"_scheduler_grants.csv");
    sixgr.util.csvWriteTable(path,g,'PreserveSchema',true,'RoundTripNumericText',true);
    missingHashes(k)=sixgr.util.sha256File(path);
    imported=sixgr.util.csvReadTable(path,'TextType','string');
    field="MCSTable"; if k==2, field="CQITable"; end
    assert(isnumeric(imported.(field))&&isscalar(imported.(field))&&isnan(imported.(field)), ...
        'This regression must exercise the actual numeric-NaN CSV import.');
end
sixgr.truth.exportLLSOutputCoverageArtifacts(missingFolder,scfg,cfg);
for filename=["table_mcs_tbs_evolution","mcs_cqi_decision_trace_table"]
    t=sixgr.util.csvReadTable(fullfile(missingFolder,'reports','csv',filename+".csv"),'TextType','string');
    assert(height(t)==2);
    name="cqi_derived_mcs"; if filename=="mcs_cqi_decision_trace_table", name="CQIDerivedMCS"; end
    if ismember(name,string(t.Properties.VariableNames)), assert(all(isnan(t.(name)))); end
    if filename=="mcs_cqi_decision_trace_table", assert(all(t.MCSMismatchStatus=="unavailable")); end
end
for k=1:2
    path=fullfile(missingDir,"live_"+lower(directions(k))+"_scheduler_grants.csv");
    assert(missingHashes(k)==string(sixgr.util.sha256File(path)));
end
end

function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, received %s.',id,cause.identifier); return;
end
error('test:MissingMCSCQIProvenanceGuard','Expected %s.',id);
end
