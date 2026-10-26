function ok = testLoadAllTrialDataCanonicalCSVDelimiter()
%TESTLOADALLTRIALDATACANONICALCSVDELIMITER Keep vector payloads inside CSV fields.

setup6GRSimToolkit("Verbose", false);
root = tempname;
mkdir(root);
cleanup = onCleanup(@() localRemove(root)); %#ok<NASGU>

layout = sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
parityVector = join(repmat("0", 1, 5000), "|");
sourceT = table("DL", 1, 5, parityVector, ...
    'VariableNames', {'Direction','Frame','SNR_dB','MeasuredLDPCParityCheckVector'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "dl_pdsch_trials.csv"), sourceT);

loaded = sixgr.analytics.loadAllTrialData(root);
assert(height(loaded.dl) == 1 && width(loaded.dl) == width(sourceT), ...
    "Canonical CSV loader must not infer pipe-delimited vector payloads as table columns.");
assert(isequal(string(loaded.dl.Properties.VariableNames), ...
    string(sourceT.Properties.VariableNames)), ...
    "Canonical CSV loader must preserve the named comma-separated trial schema.");
assert(string(loaded.dl.MeasuredLDPCParityCheckVector(1)) == parityVector, ...
    "Canonical CSV loader must preserve the complete vector-valued evidence field.");

% Empty callback populations must recover the original primary rows rather
% than overwrite receiver accounting with zero observations. This is a
% declared CSV fixture, not waveform evidence or a measured performance run.
dl=table("DL",1,1,608,1,608,.5,parityVector, ...
    'VariableNames',{'Direction','UEIndex','Slot','TBSize_bits','CRCPass', ...
    'GoodBits','AirInterfaceTTI_ms','MeasuredLDPCParityCheckVector'});
ul=dl; ul.Direction(:)="UL"; ul.TBSize_bits(:)=5000; ul.GoodBits(:)=5000;
% CRC success and an attempt slot alone cannot identify a logical TB.
% Preserve this negative before adding explicitly authored fixture IDs.
withoutIdentity=sixgr.kpi.creditTransportGoodput(ul);
assert(isnan(withoutIdentity.UniqueDeliveredTBBits) && ...
    withoutIdentity.TransportGoodputStatus=="unavailable_logical_TB_identity", ...
    'Missing TB identity must not gain delivery credit from its attempt slot.');
dl.LogicalTBID="declared_csv_dl_tb";
ul.LogicalTBID="declared_csv_ul_tb";
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'),dl,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'ul_pusch_trials.csv'),ul,'PreserveSchema',true);
[recoveredDL,recoveredUL]=sixgr.analytics.resolveRetainedDirectionalTrials(root,table(),table());
assert(height(recoveredDL)==1 && height(recoveredUL)==1 && ...
    recoveredUL.MeasuredLDPCParityCheckVector==parityVector);
cfg=struct('frame_timing',struct('slot_duration_ms',.5));
audit=sixgr.analytics.writeRFInterferenceReconciliation(cfg,root,struct(),struct(),struct());
fprintf(['RETAINED_CSV_ACCOUNTING dl_rows=%g ul_rows=%g dl_bits=%g ul_bits=%g ' ...
    'dl_mbps=%g ul_mbps=%g status=%s\n'], ...
    audit.Tables.Scheduler.DL_GrantCount,audit.Tables.Scheduler.UL_GrantCount, ...
    audit.Tables.Scheduler.DL_GoodBits,audit.Tables.Scheduler.UL_GoodBits, ...
    audit.Tables.Scheduler.DL_Goodput_Mbps,audit.Tables.Scheduler.UL_Goodput_Mbps, ...
    string(audit.Tables.Scheduler.EvaluationStatus));
assert(audit.Tables.Scheduler.DL_GrantCount==1 && audit.Tables.Scheduler.UL_GrantCount==1 && ...
    audit.Tables.Scheduler.DL_GoodBits==608 && audit.Tables.Scheduler.UL_GoodBits==5000 && ...
    audit.Tables.Scheduler.UL_Goodput_Mbps==10);
curves=sixgr.analytics.generateMeasuredSINRCurves(root,'declared_csv_population', ...
    'TrialData',struct('DL',table(),'UL',table()),'ScenarioConfig',cfg,'UpdateAnchorKPIs',false);
assert(curves.Tables.SchedulerKPIReconciliation.DL_GrantCount==1 && ...
    curves.Tables.SchedulerKPIReconciliation.UL_GrantCount==1 && ...
    curves.Tables.SchedulerKPIReconciliation.UL_GoodBits==5000, ...
    'A later empty-input publisher must not erase retained receiver accounting.');
unavailable=sixgr.analytics.buildSchedulerKPIReconciliation(table(),table(),cfg);
assert(~unavailable.SchedulerKpiReconciliationOk && ...
    unavailable.EvaluationStatus=="unavailable_no_receiver_trials");

% A present but semantically unreadable primary file must not become an
% empty population, including through the full live-export entry point.
bad=table(1,0,'VariableNames',{'Var1','Var2'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'ul_pusch_trials.csv'), ...
    bad,'PreserveSchema',true);
expected='sixgr:analytics:InvalidRetainedPrimarySchema';
localThrows(@()sixgr.analytics.resolveRetainedDirectionalTrials(root,table(),table()),expected);
localThrows(@()sixgr.analytics.writeRFInterferenceReconciliation( ...
    cfg,root,struct(),struct(),struct()),expected);
localThrows(@()sixgr.truth.exportLLSLiveDerivedTables( ...
    cfg,root,struct(),struct(),struct(),struct()),expected);
% No producer is allowed to overwrite the prior receiver accounting when
% its required retained input is malformed.
kept=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'scheduler_kpi_reconciliation.csv'));
assert(kept.DL_GrantCount==1 && kept.UL_GrantCount==1 && kept.UL_GoodBits==5000);

missingRoot=tempname;
[absentDL,absentUL]=sixgr.analytics.resolveRetainedDirectionalTrials(missingRoot,table(),table());
assert(isempty(absentDL) && isempty(absentUL),'Genuinely missing files remain unavailable.');

ok = true;
end

function localThrows(f,expected)
try
    f();
catch ME
    assert(string(ME.identifier)==string(expected), ...
        'Expected %s, got %s: %s',expected,ME.identifier,ME.message);
    return;
end
error('sixgr:test:ExpectedRetainedArtifactFailure','Expected %s.',expected);
end

function localRemove(pathStr)
if exist(pathStr, "dir") == 7
    rmdir(pathStr, "s");
end
end
