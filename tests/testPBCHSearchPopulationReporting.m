function ok=testPBCHSearchPopulationReporting()
% Declared metadata regression for separate search and transmitted populations.
% Real CSV/live/final consumers; no waveform or independent-trial claim.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','pbch_search_population_reporting', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite original evidence.');
layout=sixgr.report.resultLayout(folder);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
data=scfg.toStruct(); data.output.artifact_contract_engine.enabled=false;
scfg=sixgr.lls6g.config.ScenarioConfig(data);
cfg=sixgr.lls6g.buildInternalConfig(scfg,folder);
n=257;
t=table(ones(n,1),ones(n,1),ones(n,1),repmat("FAIL",n,1), ...
    'VariableNames',{'Slot','Frame','UEIndex','Status'});
flags=["DetectionAttempted","PSSDetected","SSSDetected","NCellIDRecovered", ...
    "DecodeAttempted","BCHCRCValid","BCHCrcPass","CRCPass","MIBDecoded", ...
    "CandidateIdentityConsistent","SSBIdentityVerified","PBCHStrictReceiverEvidenceOk", ...
    "PSSDetectionDecisionAvailable","SSSDetectionDecisionAvailable", ...
    "PSSDetectionMetricValid","SSSDetectionMetricValid", ...
    "SSBRequestedCandidateTransmitted","BCHTransmittedBlockPopulationEligible"];
for name=flags, t.(name)=nan(n,1); end
for name=["PSSNormalizedMetric","SSSNormalizedMetric","PSSDetectionThreshold", ...
        "SSSDetectionThreshold","PSSDetectionHypothesisCount","SSSDetectionHypothesisCount", ...
        "BCHTransportBlockNumBits"]
    t.(name)=nan(n,1);
end
t.BCHTransportBlockHash=strings(n,1);
t.SSBReceiverSearchScope=strings(n,1);
t.SSBAcquisitionWindowSHA256=strings(n,1);
t.RequestedSSBOccasionIndex=nan(n,1); t.RequestedSSBOccasionIndex(1:8)=0:7;
t.SSBRequestedCandidateTransmitted(1:8)=[ones(4,1);zeros(4,1)];
t.BCHTransmittedBlockPopulationEligible(1:8)=[1;1;0;0;0;0;0;0];
t.SSBReceiverSearchScope(1:8)="all_receiver_case_lmax_candidates_not_TX_active_bitmap";
t.SSBAcquisitionWindowSHA256(1:8)=string(repmat('b',1,64));
t.SourceClassification=repmat("declared_population_fixture_not_PHY",n,1);
% Actual canonical producer text-column convention: quiet/unmeasured window
% vectors are unavailable sentinels, not malformed numeric measurements.
t.SSBWindowReferenceRSRQPerReceiveAntenna_dB=repmat("NaN",n,1);
t.SSBWindowReferenceRSRQPerReceiveAntenna_dB(1)="NaN|-10|-20";
unavailable=sixgr.truth.fillBlankCategoricalColumns(table(strings(4,1), ...
    'VariableNames',{'SSBWindowReferenceRSRQPerReceiveAntenna_dB'}),"pbch");
assert(all(unavailable.SSBWindowReferenceRSRQPerReceiveAntenna_dB=="not_applicable_for_active_pbch_runtime"));
t.SSBWindowReferenceRSRQPerReceiveAntenna_dB(5:8)=unavailable.SSBWindowReferenceRSRQPerReceiveAntenna_dB;
t.SSBWindowReferenceRSRQScope=repmat("ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI",n,1);
t.SSBWindowReferenceRSRQNumRB=repmat(20,n,1);
adjacentVectors=["SS_RSRPPerReceiveAntenna_dBm","SS_RSRPRawObservedPerReceiveAntenna_dBm", ...
    "SSBWindowRSSIPerReceiveAntenna_dBm","SS_SINRPerReceiveAntenna_dB", ...
    "SSSINRDesiredPowerPerReceiveAntenna_W","SSSINRNoiseInterferencePowerPerReceiveAntenna_W", ...
    "SS_RSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
    "SS_RSRPRawObservedPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
    "SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
    "ReferenceSignalTxEPREPerAntenna_dB_re_UnitOccupiedRE_Es", ...
    "SSSINRDesiredPowerPerReceiveAntenna_UnitOccupiedRE_Es", ...
    "SSSINRNoiseInterferencePowerPerReceiveAntenna_UnitOccupiedRE_Es"];
for name=adjacentVectors
    t.(name)=repmat("NaN",n,1); t.(name)(1)="-7"; t.(name)(257)="1|NaN|-3";
end
% Complete positive detector decisions: two transmitted, two quiet, one
% legacy observation with unknown transmission membership.
for k=[1 2 6 7 9]
    for name=flags(1:16), t.(name)(k)=1; end
    t.PSSNormalizedMetric(k)=0.75; t.SSSNormalizedMetric(k)=0.75;
    t.PSSDetectionThreshold(k)=0.5; t.SSSDetectionThreshold(k)=0.5;
    t.PSSDetectionHypothesisCount(k)=3; t.SSSDetectionHypothesisCount(k)=336;
    t.BCHTransportBlockNumBits(k)=24;
    t.BCHTransportBlockHash(k)=string(sixgr.util.sha256Hex("declared_block_"+k));
end
for k=[2 7]
    t.BCHCRCValid(k)=0; t.BCHCrcPass(k)=0; t.CRCPass(k)=0;
    t.MIBDecoded(k)=0; t.CandidateIdentityConsistent(k)=0;
    t.PBCHStrictReceiverEvidenceOk(k)=0;
end
% Completed PSS miss is a TX miss at row3, quiet non-detection at row5;
% neither is a completed BCH block. Rows4/8 have no completed decision.
for k=[3 5]
    t.DetectionAttempted(k)=1; t.PSSDetected(k)=0;
    t.PSSDetectionDecisionAvailable(k)=1; t.PSSDetectionMetricValid(k)=1;
    t.PSSNormalizedMetric(k)=0.25; t.PSSDetectionThreshold(k)=0.5;
    t.PSSDetectionHypothesisCount(k)=3; t.DecodeAttempted(k)=0;
    t.BCHCrcPass(k)=0; % Initialized raw flag must NOT enter a block denominator.
end
% Late malformed decision is not silently logical(2), nor a missing block.
t.DecodeAttempted(257)=2; t.BCHCRCValid(257)=1;
t.BCHTransportBlockNumBits(257)=24;
t.BCHTransportBlockHash(257)=string(repmat('c',1,64));
original=t;
p=sixgr.report.pbchStagePopulations(t);
assert(isequal(find(p.TransmittedDecodeEligible),[1;2]) && ...
    isequal(find(p.QuietDecodeEligible),[6;7]) && ~p.PopulationKnown(9));
bad=t; bad.SSBRequestedCandidateTransmitted=string(bad.SSBRequestedCandidateTransmitted);
q=sixgr.report.pbchStagePopulations(bad);
assert(~any(q.PopulationKnown) && isequal(q.DecodeEligible,p.DecodeEligible));
bad=t; bad.BCHTransmittedBlockPopulationEligible(6)=1;
q=sixgr.report.pbchStagePopulations(bad);
assert(~q.QuietDecodeEligible(6) && ~q.TransmittedDecodeEligible(6) && q.DecodeEligible(6));
bad=t; bad.SSBAcquisitionWindowSHA256(1)="invalid";
q=sixgr.report.pbchStagePopulations(bad); assert(~q.PopulationKnown(1));
legacy=removevars(t,["SSBRequestedCandidateTransmitted","BCHTransmittedBlockPopulationEligible", ...
    "SSBReceiverSearchScope","SSBAcquisitionWindowSHA256"]);
q=sixgr.report.pbchStagePopulations(legacy);
assert(~any(q.PopulationKnown) && isequal(q.DecodeEligible,p.DecodeEligible));
path=fullfile(layout.AirInterfaceCSVDir,'pbch_trials.csv');
sixgr.util.csvWriteTable(path,t,'PreserveSchema',true,'RoundTripNumericText',true);
digest=string(sixgr.util.sha256File(path));
% Exact production import, before report construction: singleton and sparse
% late multi-branch tokens remain text, without loss of original branch NaN.
read=sixgr.report.readPBCHMeasurementTrials(path);
assert(isstring(read.SSBWindowReferenceRSRQPerReceiveAntenna_dB) && ...
    read.SSBWindowReferenceRSRQPerReceiveAntenna_dB(1)=="NaN|-10|-20" && ...
    all(read.SSBWindowReferenceRSRQPerReceiveAntenna_dB(5:8)=="not_applicable_for_active_pbch_runtime"));
for name=adjacentVectors
    assert(isstring(read.(name)) && read.(name)(1)=="-7" && read.(name)(257)=="1|NaN|-3", ...
        'Original producer vector tokens changed at the CSV boundary.');
end
assert(digest==string(sixgr.util.sha256File(path)),'Read-only preflight changed source bytes.');
% These are unjoined procedure outcomes, not a shared access lifecycle.
prach=table(["PASS";"FAIL"],'VariableNames',{'Status'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'prach_trials.csv'),prach);
live=sixgr.truth.exportLLSLiveDerivedTables(cfg,folder,struct('PBCH',t));
rates=sixgr.util.csvReadTable(live.BeamP1AcquisitionStatsPath,'TextType','string');
bch=rates(rates.Metric=="P1PBCHCRCPassRate",:);
assert(height(bch)==1 && bch.SampleCount==2 && bch.MeanValue==0.5, ...
    'Quiet, unattempted and unknown-legacy rows cannot enter the transmitted BCH rate.');
quiet=rates(rates.Metric=="P1PBCHQuietAttemptCRCPassRate",:);
receiver=rates(rates.Metric=="P1PBCHReceiverAttemptCRCPassRate",:);
assert(height(quiet)==1 && quiet.SampleCount==2 && quiet.MeanValue==0.5 && ...
    height(receiver)==1 && receiver.SampleCount==5 && abs(receiver.MeanValue-0.6)<1e-12);
manifest=struct('CodeVersion',"test",'CodeDetail',"declared_metadata_no_PHY", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
out=sixgr.truth.exportLLSReportingBundle(folder,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
for candidate={out.CategoryRows,sixgr.util.csvReadTable(out.DetailCSV,'TextType','string')}
    rows=candidate{1};
    check(rows,"pbch_decode_success","PBCH_completed_decoder",[1 2 6 7 9],[1 6 9],digest);
    check(rows,"pbch_decode_success","PBCH_transmitted_completed_block",[1 2],1,digest);
    check(rows,"pbch_decode_success","PBCH_quiet_completed_decoder",[6 7],6,digest);
    check(rows,"one_shot_ssb_detection_probability","SSB_receiver_detection",[1 2 3 5 6 7 9],[1 2 6 7 9],digest);
    check(rows,"one_shot_ssb_detection_probability","SSB_transmitted_detector",[1 2 3],[1 2],digest);
    check(rows,"one_shot_ssb_detection_probability","SSB_quiet_detector",[5 6 7],[6 7],digest);
    check(rows,"miss_detection_probability","SSB_transmitted_miss_detection",[1 2 3],3,digest);
    assert(~any(rows.MetricKey=="miss_detection_probability" & rows.Entity=="PBCH"), ...
        'Generic FAIL/CRASH must not become PBCH missed-detection evidence.');
    window=rows(rows.MetricKey=="ss_rsrq" & rows.Statistic=="mean",:);
    assert(height(window)==2 && isequal(sort(window.ValueNumeric),[-20;-10]) && ...
        sum(contains(window.Entity,"@RxBranch1Based=2"))==1 && ...
        sum(contains(window.Entity,"@RxBranch1Based=3"))==1, ...
        'Unavailable text must not become a branch measurement or renumber original NaN branches.');
    joint=rows(rows.MetricKey=="access_success_probability",:);
    assert(~isempty(joint) && all(isnan(joint.ValueNumeric)) && ...
        ~any(ismember(string(joint.Availability),["available","observed"])), ...
        'Unjoined marginal procedure rates cannot become access-success probability or coverage.');
end
assert(isequaln(t,original) && digest==string(sixgr.util.sha256File(path)), ...
    'Population summaries must not rewrite original outcomes, missing fields or source bytes.');
% Late malformed populated tokens must still fail; test each in a distinct
% child artifact folder, preserving the original positive CSV byte-for-byte.
tokens=["not_applicable_for_active_pbch_runtime_typo","1||2"];
for negativeIndex=1:numel(tokens)
    token=tokens(negativeIndex);
    badFolder=fullfile(folder,"negative_"+negativeIndex);
    badLayout=sixgr.report.resultLayout(badFolder);
    sixgr.util.ensureFolder(badLayout.AirInterfaceCSVDir);
    bad=t; bad.SSBWindowReferenceRSRQPerReceiveAntenna_dB(257)=token;
    sixgr.util.csvWriteTable(fullfile(badLayout.AirInterfaceCSVDir,'pbch_trials.csv'),bad, ...
        'PreserveSchema',true,'RoundTripNumericText',true);
    caught=false;
    try
        sixgr.truth.exportLLSReportingBundle(badFolder,scfg,cfg,struct('Ok',false),manifest, ...
            struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
    catch exception
        caught=string(exception.identifier)=="sixgr:report:InvalidSSBMeasurementVector";
        if ~caught, rethrow(exception); end
    end
    assert(caught,'Malformed populated vectors must not be hidden as unavailable.');
end
assert(digest==string(sixgr.util.sha256File(path)),'Original source CSV changed during negative checks.');
ok=true;
end

function check(rows,key,entity,included,success,digest)
r=rows(rows.MetricKey==key & rows.Entity==entity & rows.Statistic=="rate",:);
assert(height(r)==1 && r.Availability=="observed" && ...
    abs(r.ValueNumeric-numel(success)/numel(included))<1e-12);
p=jsondecode(r.PopulationJSON);
assert(isequal(p.IncludedSourceRows(:),double(included(:))) && ...
    isequal(p.SuccessSourceRows(:),double(success(:))) && ...
    string(p.SourceSHA256)==digest && p.SourceRowCount==257 && ...
    ~p.StatisticallyQualified && ~p.StandardizedAccuracyQualified);
assert(string(sixgr.util.sha256Hex(char(r.PopulationJSON)))==r.PopulationID);
operands=jsondecode(p.OriginalOperandsJSON);
assert(isfield(operands,'SSBRequestedCandidateTransmitted') && ...
    isfield(operands,'BCHTransmittedBlockPopulationEligible') && ...
    isfield(operands,'RequestedSSBOccasionIndex') && ...
    isfield(operands,'SSBAcquisitionWindowSHA256'), ...
    'The exact classification operands must survive the source-to-public projection.');
end
