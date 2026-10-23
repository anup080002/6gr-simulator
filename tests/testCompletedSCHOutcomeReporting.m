function [ok,result]=testCompletedSCHOutcomeReporting()
% Declared receiver/publication contract fixtures only: no PHY execution,
% radio-frame outcome, per-layer/CW decode or statistical qualification.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','validation','completed_sch_outcome_reporting', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(root),'Refuse to overwrite earlier reporting evidence.');
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
manifest=struct('CodeVersion',"test",'CodeDetail',"declared_receiver_contract_no_PHY", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
dl=fixture("DL"); ul=fixture("UL"); originals={dl,ul};
[report,audit,populations]=publish("mixed_original_outcomes",dl,ul);
assert(height(audit)==2*height(dl) && height(populations)==24);
assert(~any(audit.CountsTowardCoverage) && ~any(populations.CountsTowardCoverage) && ...
    ~any(audit.StatisticalIndependenceClaimed) && ~any(populations.StatisticalIndependenceClaimed));
for direction=["DL","UL"]
    a=audit(audit.Entity==direction,:); p=populations(populations.Entity==direction,:);
    assert(isequal(a.SourceRow,(1:height(dl)).') && nnz(a.CompletedReceiverOutcomeAvailable)==9);
    assert(isequaln(a.OriginalCRCPass,dl.CRCPass) && isequal(string(a.OriginalStatus),dl.Status));
    assert(nnz(a.ExecutionFailure)==2 && all(isnan(a.CRCError(a.ExecutionFailure==1))));
    assert(all(strlength(a.SourceSHA256)==64) && numel(unique(a.SourceSHA256))==1);
    assert(all(strlength(a.ReceiverEvidenceJSON)>0 & strlength(a.ObservationIdentityJSON)>0));
    first=p(p.PopulationID==a.PopulationID(1),:);
    assert(height(first)==1 && first.SourceRowCount==12 && first.CompletedDecodeAttemptCount==4 && ...
        first.CRCErrorCount==2 && first.CRCErrorRate==.5 && first.ExecutionFailureCount==1 && first.ExcludedRowCount==8);
    assert(a.CompletedReceiverOutcomeAvailable(3) && a.CRCError(3)==0, ...
        'Status FAIL with an original completed CRC pass must not create a CRC error.');
    assert(a.CompletedReceiverOutcomeAvailable(11) && ~a.CompletedReceiverOutcomeAvailable(12), ...
        'Generic CountsTowardCoverage must neither veto nor manufacture receiver outcomes.');
    empty=p(p.PopulationID==a.PopulationID(16),:);
    assert(empty.CompletedDecodeAttemptCount==0 && isnan(empty.CRCErrorRate) && empty.ExecutionFailureCount==1);
    retry=p(p.PopulationID==a.PopulationID(15),:);
    assert(retry.CompletedDecodeAttemptCount==1 && retry.CRCErrorRate==1 && ...
        contains(retry.PopulationJSON,'prior_plus_current'), ...
        'Original combining/retry scope must not pool with standalone attempts.');
    assert(a.PopulationID(17)~=a.PopulationID(18) && ...
        a.CompletedReceiverOutcomeAvailable(17) && a.CompletedReceiverOutcomeAvailable(18), ...
        'Actual UL HARQCombiningApplied must distinguish otherwise identical retry populations.');
    for index=17:18
        current=p(p.PopulationID==a.PopulationID(index),:);
        assert(current.CompletedDecodeAttemptCount==1 && current.CRCErrorRate==index-17);
    end
    assert(~any(a.SuppliedSourceContractCompatible(19:24)) && ...
        ~any(a.CompletedReceiverOutcomeAvailable(19:24)) && all(isnan(a.CRCError(19:24))), ...
        'Explicit proxy/fallback/placeholder or incompatible execution provenance cannot become receiver outcomes.');
    checkRows(report.CategoryRows,direction,p);
    checkRows(sixgr.util.csvReadTable(report.DetailCSV,'TextType','string'),direction,p);
end
assert(isequaln(originals,{dl,ul}),'Publication must not change input fixture values.');

% A historical Status/CRC/Layers row is not reconstructed into receiver
% authority. Unknown/absent CRC application remains unavailable, not zero.
legacy=removevars(dl,'CRCApplicable');
legacy.DecodeUsable=string(legacy.DecodeUsable);
legacy.DecodeUsable(5)=""; legacy.DecodeUsable(10)="NaN";
[legacyReport,legacyAudit,legacyPopulation]=publish("missing_receiver_authority",legacy,ul([],:));
assert(height(legacyAudit)==height(legacy) && ~any(legacyAudit.CompletedReceiverOutcomeAvailable) && ...
    all(isnan(legacyAudit.CRCError)) && all(legacyPopulation.CompletedDecodeAttemptCount==0));
for index=[5 10]
    evidence=jsondecode(legacyAudit.ReceiverEvidenceJSON(index));
    value=sixgr.truth.numericMeasurementColumn({evidence.DecodeUsable},"DecodeUsable");
    assert(isscalar(value) && isnan(value), ...
        'Original blank/NaN authority remains unavailable, never false or true.');
end
r=legacyReport.CategoryRows(legacyReport.CategoryRows.MetricKey=="fer_tb_error_rate",:);
assert(~isempty(r) && ~any(r.CountsTowardCoverage) && all(isnan(r.ValueNumeric)));

% Invalid scalar authority must fail before results are reduced. Numeric
% columns are intentionally double: assigning 2 into logical would coerce it.
bad=dl; bad.DecodeUsable(1)=2;
reject(@()publish("invalid_flag",bad,ul),'sixgr:report:SCHOutcomeFlagValue');
bad=dl; bad.CRCPass(1)=Inf;
reject(@()publish("invalid_crc",bad,ul),'sixgr:report:SCHOutcomeFlagValue');
bad=dl; bad.Direction(1)="UL";
reject(@()publish("transplanted_direction",bad,ul),'sixgr:report:SCHOutcomeDirection');
% CSV cannot preserve an in-memory matrix variable as one scalar column.
% Instead retain a literal malformed scalar token and require parser failure.
bad=dl; bad.DecodeAttempted=string(bad.DecodeAttempted); bad.DecodeAttempted(1)="[1 1]";
reject(@()publish("nonscalar_flag_token",bad,ul),'sixgr:truth:InvalidNumericMeasurementColumn');
bad=dl; bad.DecodeAttempted=string(bad.DecodeAttempted); bad.DecodeAttempted(end)="[1 1]";
reject(@()publish("late_nonscalar_flag_token",bad,ul),'sixgr:truth:InvalidNumericMeasurementColumn');
bad=dl; bad.DecodeAttempted=string(bad.DecodeAttempted); bad.DecodeAttempted(end)="2";
reject(@()publish("late_invalid_binary_token",bad,ul),'sixgr:report:SCHOutcomeFlagValue');
bad=dl; bad.DecodeAttempted=string(bad.DecodeAttempted); bad.DecodeAttempted(end)="Inf";
reject(@()publish("late_infinite_binary_token",bad,ul),'sixgr:report:SCHOutcomeFlagValue');
reject(@()publish("duplicate_authority_header",dl,ul,"duplicate"),'sixgr:report:SCHOutcomeHeader');
reject(@()publish("blank_authority_header",dl,ul,"blank"),'sixgr:report:SCHOutcomeHeader');
reject(@()publish("ambiguous_authority_header",dl,ul,"ambiguous"),'sixgr:report:SCHOutcomeHeader');

result=struct('EvidenceRoot',string(root),'PHYExecutions',0, ...
    'Scope',"declared_receiver_contract_to_actual_report_and_CSV", ...
    'OriginalRowsPerDirection',height(dl),'ExpectedQualifiedAttemptsPerDirection',9, ...
    'OutageQualified',false,'LayerBLERQualified',false,'CodewordBLERQualified',false);
ok=true;
fprintf('COMPLETED_SCH_OUTCOME_REPORTING_PASS declared_fixture=1 PHY_executions=0 root=%s\n',root);

    function [out,a,p]=publish(label,dlInput,ulInput,headerDefect)
        if nargin<4, headerDefect=""; end
        folder=fullfile(root,char(label));
        assert(~isfolder(folder),'Never overwrite an earlier case.');
        layout=sixgr.report.resultLayout(folder); sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
        cfg=sixgr.lls6g.buildInternalConfig(scfg,folder);
        inputs={dlInput,ulInput}; stems=["dl_pdsch_trials","ul_pusch_trials"];
        hashes=strings(2,1);
        for k=1:2
            path=fullfile(layout.AirInterfaceCSVDir,stems(k)+".csv");
            sixgr.util.csvWriteTable(path,inputs{k},'PreserveSchema',true,'RoundTripNumericText',true);
            if k==1 && strlength(headerDefect)>0, damageDeclaredFixtureHeader(path,headerDefect); end
            hashes(k)=sixgr.util.sha256File(path);
        end
        out=sixgr.truth.exportLLSReportingBundle(folder,scfg,cfg,struct('Ok',false),manifest, ...
            struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
        a=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir, ...
            'completed_sch_decode_attempt_observations.csv'),'TextType','string');
        p=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir, ...
            'completed_sch_decode_attempt_populations.csv'),'TextType','string');
        validateBinaryColumns(a,["CompletedReceiverOutcomeAvailable", ...
            "SuppliedSourceContractCompatible","ExecutionFailure", ...
            "CountsTowardCoverage","StatisticalIndependenceClaimed"]);
        validateBinaryColumns(p,["CountsTowardCoverage","StatisticalIndependenceClaimed"]);
        for k=1:2
            path=fullfile(layout.AirInterfaceCSVDir,stems(k)+".csv");
            assert(hashes(k)==string(sixgr.util.sha256File(path)), ...
                'Do not rewrite original source bytes while repairing report populations.');
        end
        for key=["outage_probability","per_layer_bler","per_codeword_bler"]
            r=out.CategoryRows(out.CategoryRows.MetricKey==key,:);
            assert(~isempty(r) && ~any(r.CountsTowardCoverage) && all(isnan(r.ValueNumeric)) && ...
                ~any(startsWith(r.Entity,["layer_","codeword_"])), ...
                'Unsupported outage/layer/CW evidence must not acquire synthesized observations.');
            c=out.Coverage(out.Coverage.MetricKey==key,:);
            assert(~isempty(c) && ~any(c.CountsTowardCoverage));
        end
    end
end

function T=fixture(direction)
n=24;
T=table(repmat(direction,n,1),repmat("PASS",n,1),ones(n,1), ...
    zeros(n,1),(1:n).',repmat(4,n,1),repmat(7,n,1),zeros(n,1), ...
    'VariableNames',{'Direction','Status','CRCPass','Frame','Slot','Layers','MCS','ConfiguredSNR_dB'});
for field=["FinalizedFlag","DecodeAttempted","DecodeUsable","CRCApplicable"]
    T.(field)=ones(n,1);
end
for field=["PartialRowFlag","Crash","IsWarmupFrame","CountsTowardCoverage","IsRetransmission", ...
        "HARQRound","HARQCombiningApplied","FallbackFlag","PlaceholderFlag"]
    T.(field)=zeros(n,1);
end
T.DLSCHDecodeAttempted=repmat(double(direction=="DL"),n,1);
T.DLSCHDecodeAvailable=T.DLSCHDecodeAttempted;
T.ULSCHDecodeAttempted=repmat(double(direction=="UL"),n,1);
T.ULSCHDecodeAvailable=T.ULSCHDecodeAttempted;
T.DecoderCRCInputDomain=repmat("current_attempt_only",n,1);
T.ApproximationMode=repmat("none",n,1);
T.ExecutionBackend=repmat("scheduler_shared_stream_receiver",n,1);
T.RuntimeEvidenceSource=repmat("sixgr.link.runDLPDSCHThroughput_returned_receiver",n,1);
T.RuntimeMaterializationStatus=repmat("active_waveform_pdsch_runtime",n,1);
if direction=="UL"
    T.RuntimeEvidenceSource(:)="sixgr.link.runULPUSCHThroughput_returned_receiver";
    T.RuntimeMaterializationStatus(:)="active_waveform_pusch_runtime";
end
T.Source=repmat("",n,1);
T.FixtureScope=repmat("declared_report_boundary_not_executed_PHY",n,1);
T.ObservationID="declared_"+direction+"_"+string((1:n).');
T.Seed=(101:100+n).'; % Per-trial seeds must not singleton-fragment cohorts.
T.Status([2,3,11,15])="FAIL"; T.CRCPass([2,11,15])=0;
T.Status([4,16])="CRASH"; T.CRCPass([4,16])=0; T.Crash([4,16])=1;
T.FinalizedFlag([4,6,16])=0;
T.Status(5)="NA"; T.CRCPass(5)=NaN; T.DecodeAttempted(5)=0;
T.PartialRowFlag(6)=1; T.IsWarmupFrame(7)=1;
T.DecodeAttempted(8)=0; T.CRCApplicable(9)=0; T.DecodeUsable(10)=NaN;
T.CountsTowardCoverage(12)=1;
if direction=="DL", T.DLSCHDecodeAvailable(12)=0; else, T.ULSCHDecodeAvailable(12)=0; end
T.ConfiguredSNR_dB(13:15)=10;
T.IsRetransmission(15)=1; T.DecoderCRCInputDomain(15)="prior_plus_current";
T.ConfiguredSNR_dB(16)=20;
% These two original rows differ only in the actual UL producer field;
% neither a missing CRC-input-domain token nor equal retry count may pool it.
T.ConfiguredSNR_dB(17:18)=10; T.IsRetransmission(17:18)=1; T.HARQRound(17:18)=1;
T.DecoderCRCInputDomain(17:18)=""; T.HARQCombiningApplied(18)=1;
T.Status(18)="FAIL"; T.CRCPass(18)=0;
T.FallbackFlag(19)=1; T.PlaceholderFlag(20)=1;
T.ApproximationMode(21)="fast_proxy";
T.ExecutionBackend(22)="scheduler_coded_transmitter_pre_node_rf";
T.RuntimeEvidenceSource(23)="unsupported_new_receiver_contract";
T.Source(24)="synthetic_from_fast_kernel_fixture";
end

function checkRows(rows,direction,populations)
validateBinaryColumns(rows,"CountsTowardCoverage");
r=rows(rows.MetricKey=="fer_tb_error_rate" & rows.Entity==direction,:);
assert(all(r.MetricName=="Completed SCH decode-attempt aggregate CRC error rate") && ...
    all(contains(r.Notes,'not radio-frame FER')));
rates=r(r.Statistic=="rate",:);
assert(height(rates)==height(populations) && numel(unique(rates.PopulationID))==height(populations));
for k=1:height(populations)
    p=populations(k,:); x=r(r.PopulationID==p.PopulationID,:);
    if p.CompletedDecodeAttemptCount>0
        assert(height(x)==3 && all(x.CountsTowardCoverage) && ...
            x.ValueNumeric(x.Statistic=="rate")==p.CRCErrorRate && ...
            x.ValueNumeric(x.Statistic=="error_count")==p.CRCErrorCount && ...
            x.ValueNumeric(x.Statistic=="decoded_attempt_count")==p.CompletedDecodeAttemptCount);
    else
        assert(height(x)==1 && ~x.CountsTowardCoverage && isnan(x.ValueNumeric));
    end
end
end

function damageDeclaredFixtureHeader(path,defect)
% Only a newly authored negative fixture is altered, before its source hash
% is recorded. Never modify an original execution artifact or data values.
text=fileread(path); boundary=find(text==newline,1);
assert(~isempty(boundary)); header=text(1:boundary-1);
needle=',DecodeUsable,';
assert(numel(strfind(header,needle))==1);
switch defect
    case "duplicate", replacement=',DecodeAttempted,';
    case "blank", replacement=',,';
    case "ambiguous", replacement=',"DecodeUsable"unexpected,';
    otherwise, error('test:UnknownHeaderDefect','Unknown declared header negative.');
end
header=strrep(header,needle,replacement);
fid=fopen(path,'w','n','UTF-8'); assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',[header,text(boundary:end)]);
end

function validateBinaryColumns(T,fields)
% CSV may faithfully return logical flags as numeric 0/1. Validate their
% values before assertions; never coerce NaN or use numeric flags as indices.
for field=fields
    value=T.(field);
    assert((isnumeric(value) || islogical(value)) && isreal(value) && ...
        isequal(size(value),[height(T),1]) && all(isfinite(value)) && ...
        all(value==0 | value==1), ...
        'test:InvalidBinaryReadback','Expected exact finite scalar 0/1 values in %s.',field);
end
end

function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, received %s.',id,cause.identifier); return;
end
error('test:MissingSCHOutcomeGuard','Expected %s.',id);
end
