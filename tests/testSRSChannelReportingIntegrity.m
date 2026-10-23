function [ok,result]=testSRSChannelReportingIntegrity(runExporter)
% Declared reporting-boundary fixtures only; no RF/PHY/channel is executed.
% false runs the pure arithmetic/authority cases while other publishers are
% frozen. The default also exercises the actual report and persisted CSVs.
if nargin<1, runExporter=true; end
setup6GRSimToolkit('Verbose',false);
savedRNG=rng;
T=table([-Inf;-20;-10;30;NaN;Inf],[1;1;1;0;1;1], ...
    ["PASS";"PASS";"FAIL";"PASS";"PASS";"PASS"],repmat(-8,6,1), ...
    'VariableNames',{'NMSE_dB','ChannelNMSEReferenceAvailable','Status','ChannelNMSEThreshold_dB'});
original=T;
[s,d]=sixgr.report.summarizeSRSChannelReport(T);
expected=10*log10((0+.01+.1)/3);
assert(abs(s.NMSE_dB-expected)<1e-12&&s.MinNMSE_dB==-Inf&& ...
    s.P95NMSE_dB==-10&&s.MaxNMSE_dB==-10&&s.MeasuredTrials==3&& ...
    s.QualifiedTrials==2&&s.FailedTrials==1&&s.UnreferencedNumericTrials==1);
assert(~s.StatisticalIndependenceClaimed&&~s.ConfidenceIntervalAvailable&& ...
    ~d.CountsTowardCoverage&&d.SourceTrialCount==6&&~isfield(d,'NMSE_dB')&&isequaln(T,original));
unreferenced=removevars(T,'ChannelNMSEReferenceAvailable');
[q,qd]=sixgr.report.summarizeSRSChannelReport(unreferenced);
assert(~q.MeasurementAvailable&&q.QualifiedTrials==0&&isnan(q.NMSE_dB)&& ...
    isnan(q.P95NMSE_dB)&&qd.UnreferencedNumericTrials==4);
unknown=T; unknown.ChannelNMSEReferenceAvailable(:)=NaN;
q=sixgr.report.summarizeSRSChannelReport(unknown);
assert(~q.MeasurementAvailable&&q.QualifiedTrials==0);
unknown=T(2:3,:); unknown.Status(:)="PASS";
unknown.ChannelNMSEThreshold_dB=[NaN;Inf];
q=sixgr.report.summarizeSRSChannelReport(unknown);
assert(q.MeasurementAvailable&&q.MeasuredTrials==2&&q.QualifiedTrials==0);
zero=T(1:3,:); zero.NMSE_dB(:)=-Inf; zero.Status(:)="PASS";
[q,~]=sixgr.report.summarizeSRSChannelReport(zero);
assert(q.AllTrialsQualified&&q.NMSE_dB==-Inf&&q.P95NMSE_dB==-Inf&&q.MaxNMSE_dB==-Inf);
% The defined empirical power quantile is a real retained order statistic,
% not a dB-interpolated percentile and not an inferential confidence bound.
quantile=T(ones(100,1),:); quantile.NMSE_dB=(-100:-1).';
q=sixgr.report.summarizeSRSChannelReport(quantile);
assert(q.P95NMSE_dB==-6&&q.P95Definition== ...
    "empirical_inverse_CDF_of_normalized_error_power_rank_ceil_0p95_N");
text=T; text.NMSE_dB=cellstr(string(T.NMSE_dB));
text.ChannelNMSEReferenceAvailable=string(T.ChannelNMSEReferenceAvailable);
text.ChannelNMSEThreshold_dB=string(T.ChannelNMSEThreshold_dB);
assert(isequaln(s,sixgr.report.summarizeSRSChannelReport(text)), ...
    'Original CSV scalar representations must retain the same arithmetic and availability.');
bad=T; bad.ChannelNMSEReferenceAvailable(1)=2;
reject(@()sixgr.report.summarizeSRSChannelReport(bad),'sixgr:truth:InvalidSRSReferenceAuthority');
bad=T; bad.NMSE_dB=[T.NMSE_dB T.NMSE_dB];
reject(@()sixgr.report.summarizeSRSChannelReport(bad),'sixgr:report:InvalidSRSMeasurementColumn');
[q,qd]=sixgr.report.summarizeSRSChannelReport(table());
assert(~q.MeasurementAvailable&&q.MeasuredTrials==0&&isnan(q.NMSE_dB)&&qd.SourceTrialCount==0);
assert(isequal(savedRNG,rng),'Pure report statistics must not consume RNG draws.');
result=struct('ExporterExercised',false,'EvidenceRoot',"",'PHYExecutions',0);
if runExporter
    root=fullfile(pwd,'results','validation','srs_channel_reporting_integrity', ...
        char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
    scfg=sixgr.lls6g.config.loadScenarioConfig( ...
        'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
    manifest=struct('CodeVersion',"test",'CodeDetail',"declared_export_fixture_no_PHY_execution", ...
        'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
        'RunCompletion',"completed",'DeterministicMode',"test");
    publish(T,"mixed_referenced_and_diagnostic",expected,-10,-10,true,3,2);
    publish(zero,"exact_zero_error",-Inf,-Inf,-Inf,true,3,3);
    publish(unreferenced,"legacy_missing_authority",NaN,NaN,NaN,false,0,0);
    result.ExporterExercised=true; result.EvidenceRoot=string(root);
end
fprintf('SRS_CHANNEL_REPORT_INTEGRITY_PASS exporter=%d declared_fixture=1 PHY_executions=0 evidence=%s\n', ...
    result.ExporterExercised,result.EvidenceRoot);
ok=true;

    function publish(source,label,meanValue,p95Value,maxValue,available,measured,qualified)
        folder=fullfile(root,char(label)); layout=sixgr.report.resultLayout(folder);
        sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
        cfg=sixgr.lls6g.buildInternalConfig(scfg,folder);
        source.FixtureScope=repmat("declared_report_input_not_PHY_measurement",height(source),1);
        sourceFile=fullfile(layout.AirInterfaceCSVDir,'srs_trials.csv');
        sixgr.util.csvWriteTable(sourceFile,source,'PreserveSchema',true,'RoundTripNumericText',true);
        sourceHash=sixgr.util.sha256File(sourceFile);
        out=sixgr.truth.exportLLSReportingBundle(folder,scfg,cfg,struct('Ok',false), ...
            manifest,struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
        assert(string(sourceHash)==string(sixgr.util.sha256File(sourceFile)), ...
            'Report qualification must never rewrite original receiver evidence.');
        checkRows(out.CategoryRows);
        checkRows(sixgr.util.csvReadTable(out.DetailCSV,'TextType','string'));
        audit=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir, ...
            'srs_channel_qualification_diagnostics.csv'),'TextType','string');
        assert(height(audit)==1&&audit.SourceTrialCount==height(source)&& ...
            audit.MeasuredTrials==measured&&audit.QualifiedTrials==qualified&& ...
            ~audit.CountsTowardCoverage&&~audit.StatisticalIndependenceClaimed&& ...
            ~audit.ConfidenceIntervalAvailable&&~ismember('NMSE_dB',audit.Properties.VariableNames));
        report=string(fileread(out.ExecutiveSummary));
        if available
            assert(contains(report,'Reference-authorized SRS NMSE:')&& ...
                contains(report,'linear-power mean in dB='));
        else
            assert(~contains(report,'Reference-authorized SRS NMSE:'));
        end

        function checkRows(rows)
            for key=["ce_nmse","nmse","srs_port_scaling_impact"]
                r=rows(rows.MetricKey==key&rows.Entity=="SRS",:);
                values=r(ismember(r.Statistic,["mean","p95","max"]),:);
                if available
                    assert(height(values)==3&&all(values.CountsTowardCoverage)&& ...
                        all(contains(values.Notes,'measurement availability is not threshold qualification')));
                    assert(same(values.ValueNumeric(values.Statistic=="mean"),meanValue)&& ...
                        same(values.ValueNumeric(values.Statistic=="p95"),p95Value)&& ...
                        same(values.ValueNumeric(values.Statistic=="max"),maxValue));
                    if meanValue==-Inf
                        % CSV import may infer this all-numeric text column
                        % as double. Both representations retain exact -Inf.
                        assert(all(string(values.ValueText)=="-Inf"),'Zero error must remain numeric -Inf, not unavailable or floored.');
                    end
                else
                    assert(isempty(values)&&~isempty(r)&&~any(r.CountsTowardCoverage));
                end
            end
            dmrs=rows(rows.MetricKey=="dmrs_estimation_quality",:);
            assert(~any(dmrs.Entity=="SRS")&&~any(dmrs.CountsTowardCoverage), ...
                'SRS evidence cannot create DM-RS measurement coverage.');
        end
    end
end

function tf=same(actual,expected)
tf=isscalar(actual)&&(isequaln(actual,expected)|| ...
    (isfinite(actual)&&isfinite(expected)&&abs(actual-expected)<1e-12));
end
function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s.',id,cause.identifier); return;
end
error('test:MissingSRSReportGuard','Expected %s.',id);
end
