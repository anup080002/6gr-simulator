function ok=testSRSRuntimeTrialSchema()
% Exercise the exact private collector and its preallocation using two real
% shared-SRS receiver results. Isolate the unchanged local functions in a
% generated test harness: no 100-slot campaign or report recovery is needed.
% The generated source is a diagnostic artifact, never a production path.
setup6GRSimToolkit('Verbose',false);
[~,receptions]=testSRSSharedPhaseHistory();
source=fileread(which('sixgr.truth.runWaveformLinkBundle'));
starts=regexp(source,'(?m)^function ','start');
assert(numel(starts)>1);
locals=source(starts(2):end);
declaration='row.RuntimeNoiseVarianceSource = "";';
assert(numel(strfind(locals,declaration))==1, ...
    'The canonical preallocated trial must declare the SRS noise source.');
folder=fullfile(pwd,'results','lls','srs_runtime_trial_schema', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
% Reproduce the exact old defect before checking the corrected source.
writeHarness(folder,'srsCollectorBeforeRepair',erase(locals,declaration));
writeHarness(folder,'srsCollectorAfterRepair',locals);
addpath(folder); cleanup=onCleanup(@()rmpath(folder)); %#ok<NASGU>
try
    srsCollectorBeforeRepair(receptions{1}.Config,receptions{1}.Output);
    error('test:SRSExpectedSchemaFailure','Old collector unexpectedly accepted its row.');
catch cause
    assert(strcmp(cause.identifier,'MATLAB:heterogeneousStrucAssignment'), ...
        'Expected the retained slot-45 failure, got %s: %s',cause.identifier,cause.message);
end
rows=table();
for k=1:numel(receptions)
    out=receptions{k}.Output;
    before=rng;
    row=srsCollectorAfterRepair(receptions{k}.Config,out);
    assert(isequal(before,rng),'Reduction must not execute another channel/noise realization.');
    assert(height(row)==1 && ~row.Crash && row.Status=="PASS", ...
        'Physical receiver output must survive the production row collector.');
    assert(string(row.RuntimeNoiseVarianceSource)==string(out.RuntimeNoiseVarianceSource) && ...
        row.RuntimeNoiseVarianceMean==out.RuntimeNoiseVarianceMean && ...
        string(row.RuntimeNoiseVarianceDomain)==string(out.RuntimeNoiseVarianceDomain));
    for field=string(fieldnames(sixgr.link.srsPilotPhaseEvidence())).'
        assert(isequaln(row.(field),out.(field)),'Lost SRS phase evidence: %s',field);
    end
    assert(row.NMSE_dB==out.NMSE_dB && row.MeasuredTrialSINR_dB==out.SINR_dB && ...
        row.RankEstimate==out.RankEstimate && row.WidebandCQI==out.CQI);
    rows=[rows;row]; %#ok<AGROW>
end
% A missing measurement stays missing; no preceding row may fill its value.
missing=receptions{2}.Output;
missing=rmfield(missing,{'RuntimeNoiseVarianceMean','RuntimeNoiseVarianceDomain','RuntimeNoiseVarianceSource'});
row=srsCollectorAfterRepair(receptions{2}.Config,missing);
assert(~row.Crash && isnan(row.RuntimeNoiseVarianceMean) && ...
    row.RuntimeNoiseVarianceDomain=="" && row.RuntimeNoiseVarianceSource=="");
failed=receptions{2}.Output;
failed.Ok=false; failed.StrictOk=false; failed.FailureReason="declared_negative_receiver_result";
row=srsCollectorAfterRepair(receptions{2}.Config,failed);
assert(~row.Crash && row.Status=="FAIL" && row.FailureReason==failed.FailureReason);
sixgr.util.csvWriteTable(fullfile(folder,'srs_trials.csv'),rows,'PreserveSchema',true);
saved=sixgr.util.csvReadTable(fullfile(folder,'srs_trials.csv'));
assert(height(saved)==2 && isequal(string(saved.RuntimeNoiseVarianceSource),string(rows.RuntimeNoiseVarianceSource)));
fprintf('SRS_RUNTIME_TRIAL_SCHEMA_PASS physical_occasions=2 original_failure_reproduced=1 evidence=%s\n',folder);
ok=true;
end

function writeHarness(folder,name,locals)
% Use literal production function bodies, not rewritten collector logic.
path=fullfile(folder,[name '.m']);
[fid,msg]=fopen(path,'w'); assert(fid>=0,'%s',msg);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'function T=%s(cfg,received)\n',name);
fprintf(fid,'T=localCollectSRSTrials(cfg,40,1,[],45,received);\nend\n');
fprintf(fid,'%s',locals);
end
