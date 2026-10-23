function ok=testLDPCRateMatchReportEvidence()
% Actual coding-component operands plus bounded exporter fixtures. These are
% not waveform performance, independence, RF robustness or conformance runs.
setup6GRSimToolkit('Verbose',false);
state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(60604,'twister');
short=fixture(384,.3,400,0,1000);
repeated=fixture(384,.3,50000,3,1000);
secondPoint=short; secondPoint.SweepPointIndex=2; secondPoint.RandomSeed=902;
secondPoint.ExecutionID="coding_component_point_2";
source="declared_coding_component_trials.csv";
input=[short;repeated;secondPoint]; before=input;
[a,b]=sixgr.report.collectLDPCRateMatchEvidence(input,"DL",source);
assert(isequaln(input,before),'The collector must not mutate retained operands.');
assert(height(a)==3 && all(a.SelectionAvailable) && numel(unique(a.EvidenceID))==3);
assert(a.UnselectedEligiblePositions(1)>0 && a.RepeatedSelections(2)>0);
assert(all(b.BufferPositions==b.BufferFillerPositions+b.EligibleBufferPositions));
assert(all(b.SelectedPositions==b.UniqueSelectedPositions+b.RepeatedSelections));
assert(all(b.EligibleBufferPositions==b.UniqueSelectedPositions+b.UnselectedEligiblePositions));
assert(all(b.Nref==1000) && isequal(b.RV,[0;3;0]));
assert(contains(a.InputIdentityJSON(3),'"SweepPointIndex":2') && ...
    contains(a.InputIdentityJSON(3),'"RandomSeed":902'));
% Whole-row duplicates are retained as source records, not pooled into an
% independent-trial count or an aggregate rate.
[duplicates,~]=sixgr.report.collectLDPCRateMatchEvidence([short;short],"DL",source);
assert(height(duplicates)==2 && numel(unique(duplicates.EvidenceID))==2);

multi=fixture([384 4104],[.3 .15],[400 26712],[0 2],[1000 NaN]);
[m,cb]=sixgr.report.collectLDPCRateMatchEvidence(multi,"UL",source);
assert(m.NumCodewords==2 && m.NumCodeBlocks==3 && height(cb)==3);
assert(isequal(cb.CodewordOrdinal,[1;2;2]) && isequal(cb.CodeBlockOrdinal,[1;1;2]));
assert(isequal(cb.RV,[0;2;2]) && cb.Nref(1)==1000 && all(isnan(cb.Nref(2:3))));
assert(m.CBCRCBits==48 && m.CodeBlockInputBits== ...
    m.TBLengthWithCRC_bits+m.CBCRCBits+m.SegmentationPaddingBits);
unknown=removevars(short,{'RV','Nref'});
[~,unknownBlocks]=sixgr.report.collectLDPCRateMatchEvidence(unknown,"DL",source);
assert(all(isnan(unknownBlocks.RV)) && all(isnan(unknownBlocks.Nref)), ...
    'RV/Nref history cannot be recovered from a current buffer length.');
% Actual absence of v2 evidence is different from corruption of declared v2.
legacy=removevars(short,{'CodingAccountingVersion','RateMatchAccountingJSON'});
[missing,none]=sixgr.report.collectLDPCRateMatchEvidence(legacy,"DL",source);
assert(~missing.SelectionAvailable && isnan(missing.SelectedPositions) && isempty(none));
[emptyA,emptyB]=sixgr.report.collectLDPCRateMatchEvidence(input([],:),"DL",source);
assert(isempty(emptyA) && isempty(emptyB) && isstring(emptyA.Status) && isstring(emptyB.NrefStatus));
bad=short; bad.RateMatchAccountingJSON="{"; reject(bad);
bad=short; bad.RateMatchPunctureBits=bad.RateMatchPunctureBits+1; reject(bad);
bad=short; bad.SegmentationPaddingBits=bad.SegmentationPaddingBits+24; reject(bad);
bad=short; bad.InherentLDPCPuncturedBits=bad.InherentLDPCPuncturedBits+2; reject(bad);
bad=short; bad.Nref=999; reject(bad);
bad=short; raw=jsondecode(bad.RateMatchAccountingJSON);
if iscell(raw), raw=raw{1}; end
raw.UniqueSelectedPositions=raw.UniqueSelectedPositions+1;
bad.RateMatchAccountingJSON=string(jsonencode({raw})); reject(bad);
bad=short; bad.CodingAccountingVersion="legacy"; reject(bad);

root=fullfile(pwd,'results','validation','ldpc_rate_match_report_evidence', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
layout=sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir); sixgr.util.ensureFolder(layout.ReportCSVDir);
base=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(base,root);
data=base.toStruct(); data.output.artifact_contract_engine.enabled=true;
data.ai_ml.enabled=false;
scfg=sixgr.lls6g.config.ScenarioConfig(data);
manifest=struct('CodeVersion',"test",'CodeDetail',"coding_component_and_export_fixture_not_waveform", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
out=publish(input);
rows=out.CategoryRows;
counts=rows(rows.MetricKey=="puncturing_shortening_statistics" & ...
    rows.Statistic=="RepeatedSelections",:);
assert(height(counts)==3 && isequal(counts.ValueNumeric,a.RepeatedSelections) && ...
    all(counts.CountsTowardCoverage) && numel(unique(counts.Entity))==3);
fractions=rows(rows.MetricKey=="rate_matching_overhead",:);
assert(height(fractions)==6 && ~any(ismember(fractions.Statistic,["mean_ratio","p95_ratio"])));
saved=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'ldpc_rate_match_attempts.csv'),'TextType','string');
assert(height(saved)==3 && isequal(saved.RateMatchAccountingJSON,input.RateMatchAccountingJSON));
digest=string(sixgr.util.sha256File(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv')));
assert(all(saved.SourceArtifactSHA256==digest));
noInventedDeltas(rows);

% Arbitrary benchmark metadata and configured mode do not supply a pair.
meta=table(.75,100,100,'VariableNames',{'BaselineDelta','FLOPs','FLOPsBudget'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir,'ai_benchmark_metadata.csv'),meta);
data.ai_ml.enabled=true; data.ai_ml.csi_feedback_mode="none";
data.csi_acquisition_and_reporting.compression_mode="sscc";
data.csi_acquisition_and_reporting.sscc_mode=true;
scfg=sixgr.lls6g.config.ScenarioConfig(data);
out=publish(legacy); rows=out.CategoryRows;
noInventedDeltas(rows);
mode=rows(rows.MetricKey=="analog_jscc_jscm_robustness_metrics" & rows.Statistic=="mode",:);
assert(height(mode)==1 && mode.ValueText=="sscc" && mode.Availability=="config_only");
for key=["puncturing_shortening_statistics","rate_matching_overhead"]
    selected=rows(rows.MetricKey==key,:);
    assert(~any(selected.CountsTowardCoverage) && ~any(isfinite(selected.ValueNumeric)), ...
        'Historical scalar counts cannot create exact v2 reporting coverage.');
end
fprintf('LDPC_RATE_MATCH_REPORT_EVIDENCE_PASS actual_coding_components=1 waveform_execution=0 evidence=%s\n',root);
ok=true;

    function out=publish(trials)
        sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'), ...
            trials,'PreserveSchema',true,'RoundTripNumericText',true);
        out=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false), ...
            manifest,struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
    end
    function reject(trials)
        failed=false;
        try
            sixgr.report.collectLDPCRateMatchEvidence(trials,"DL",source);
        catch cause
            if ~strcmp(cause.identifier,'sixgr:report:LDPCAccountingInvalid'), rethrow(cause); end
            failed=true;
        end
        assert(failed,'Corrupt retained LDPC accounting must fail closed.');
    end
end

function noInventedDeltas(rows)
selected=rows(ismember(rows.Statistic,["robustness_delta","reported_delta","delta_per_flop"]),:);
assert(height(selected)==3 && ~any(selected.CountsTowardCoverage) && ...
    ~any(isfinite(selected.ValueNumeric)),'No unpaired numeric AI delta is permitted.');
end

function T=fixture(A,R,G,RV,Nref)
layouts=cell(1,numel(A)); accounts=cell(size(layouts));
crcLength=zeros(size(A)); withCRC=zeros(size(A));
for k=1:numel(A)
    sch=nrDLSCHInfo(A(k),R(k));
    tb=int8(randi([0 1],A(k),1)); codedTB=nrCRCEncode(tb,sch.CRC);
    [cbs,seg]=sixgr.phy.tb.segmentLDPC(codedTB,sch.BGN);
    enc=nrLDPCEncode(cbs,sch.BGN);
    limit=[]; if isfinite(Nref(k)), limit=Nref(k); end
    [bits,rm]=sixgr.phy.phycode.rateMatchLDPC(enc,G(k),RV(k),'QPSK',1,limit);
    assert(isequal(bits,enc(double(rm.PositionMap.MotherCodeLinearIndex))));
    layouts{k}=sixgr.phy.phycode.resolveCodingLayout('TransportBlockSize',A(k), ...
        'TargetCodeRate',R(k),'RateMatchedBitCount',G(k),'RV',RV(k),'Nref',limit);
    accounts{k}=rm.Accounting;
    assert(isequal(layouts{k}.RateMatchAccounting,accounts{k}), ...
        'Layout accounting must reproduce the actual random payload selection.');
    crcLength(k)=sch.L; withCRC(k)=numel(codedTB);
end
tx=struct('TransportBlockSizePerCodeword',A,'TransportBlockCRCLengthPerCodeword',crcLength, ...
    'TransportBlockLenWithCRCPerCodeword',withCRC,'GPerCodeword',G,'CodingLayouts',{layouts});
m=sixgr.link.deriveCodingTrialMetrics(tx,struct('Segmentation',seg),struct(),struct());
r=sixgr.link.codingAccountingExport(m);
for name=["EncodedBits","RateMatchedBits","RateMatchPunctureBits","RateMatchRepetitionBits", ...
        "NumCodeBlocks","SegmentationPaddingBits","TBLengthWithCRC_bits"]
    r.(name)=m.(name);
end
r.BaseGraph=NaN;
if numel(A)==1
    r.RV=RV; r.Nref=Nref; r.BaseGraph=double(layouts{1}.BaseGraph);
else
    r.RVPerCodeword=RV; r.NrefPerCodeword=Nref;
end
r.ExecutionID="coding_component_point_1"; r.RunID="component_fixture";
r.SweepPointIndex=1; r.RandomSeed=901; r.ChannelSeed=902;
r.LogicalTBID="tb_local_1"; r.TransmissionAttemptID="attempt_local_1";
r.UEIndex=1; r.RNTI=7; r.ServingCell=1; r.Slot=1;
r.ExecutionBackend="actual_coding_component_not_waveform"; r.ApproximationMode="none";
T=struct2table(r,'AsArray',true);
end
