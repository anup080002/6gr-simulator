function ok = testSummaryRateExportPrecision()
% Serialization fixture only; no generated rows are presented as PHY results.
setup6GRSimToolkit('Verbose',false);
sixgr.db.deactivateArtifactStore();
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,root);
nominal=sixgr.truth.summarizeEffectiveOperatingPoint(s,table(),table(),cfg);
layout=sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
for direction=["DL","UL"]
    point=nominal.Configured.(direction);
    T=table(repmat(point.Layers,15,1),repmat(point.Modulation,15,1), ...
        repmat(point.MCS,15,1),'VariableNames',{'Layers','Modulation','MCS'});
    T.MCS(3:end)=point.MCS+1;
    if direction=="DL", filename='dl_pdsch_trials.csv'; else, filename='ul_pusch_trials.csv'; end
    sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,filename),T,'PreserveSchema',true);
end
summary=table(2/15,2/15,'VariableNames', ...
    {'EffectiveDLConfiguredMatchRate','EffectiveULConfiguredMatchRate'});
summaryPath=fullfile(layout.ReportCSVDir,'scenario_summary.csv');
sixgr.util.csvWriteTable(summaryPath,summary,'PreserveSchema',true);
out=sixgr.truth.exportLLSConfigOwnershipArtifacts(root,s,cfg);
localCheck(out.SummaryVsRawConsistency,2/15,"consistent");
% A real discrepancy must remain visible, not be overwritten by raw values.
summary.EffectiveDLConfiguredMatchRate=0.2;
summary.EffectiveULConfiguredMatchRate=0.2;
sixgr.util.csvWriteTable(summaryPath,summary,'PreserveSchema',true);
out=sixgr.truth.exportLLSConfigOwnershipArtifacts(root,s,cfg);
localCheck(out.SummaryVsRawConsistency,0.2,"mismatch");
fprintf('SUMMARY_RATE_PRECISION_PASS ratio=2/15 independent_mismatch_retained=1\n');
ok=true;
end

function localCheck(path,expectedSummary,expectedStatus)
opts=detectImportOptions(path,'Delimiter',',','VariableNamingRule','preserve');
opts=setvartype(opts,opts.VariableNames,'string');
T=readtable(path,opts);
T=T(endsWith(T.SummaryField,'ConfiguredMatchRate'),:);
assert(height(T)==2);
assert(all(abs(str2double(T.RawDerivedValue)-2/15)<2e-15));
assert(all(abs(str2double(T.SummaryValue)-expectedSummary)<2e-15));
assert(isequal(T.SummaryValue,T.BrowserDisplayedValue));
assert(all(T.ConsistencyStatus==expectedStatus));
end
