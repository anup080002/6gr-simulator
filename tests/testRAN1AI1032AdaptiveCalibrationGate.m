function ok = testRAN1AI1032AdaptiveCalibrationGate()
%TESTRAN1AI1032ADAPTIVECALIBRATIONGATE Reject guessed/proxy SLS thresholds.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.studies.ran1ai1032.loadStudyConfig();
h = sixgr.studies.ran1ai1032.MCSCatalog.optionA();
h = h(ismember(h.entry_id, ["H0";"H1";"H2";"H3"]), :);
ranks = double(cfg.sls.adaptive_selection.required_calibration_ranks(:));
n = height(h) * numel(ranks);
EntryID = strings(n,1); MCSIndex = zeros(n,1); Qm = zeros(n,1);
TargetCodeRateX1024 = zeros(n,1); Rank = zeros(n,1);
BLERTarget = repmat(0.1,n,1); RequiredSINRdB = zeros(n,1);
SourceCaseID = strings(n,1); SourceChannel = strings(n,1);
TransportBlockCount = repmat(4000,n,1); ErrorCount = repmat(400,n,1);
Censored = false(n,1); ExecutionBackend = repmat("coded_waveform_PHY",n,1);
SourceClassification = repmat("executed_phy_truth",n,1);
row = 0;
for rank = ranks.'
    for i = 1:height(h)
        row = row + 1;
        EntryID(row)=h.entry_id(i); MCSIndex(row)=h.indication_index(i);
        Qm(row)=h.Qm(i); TargetCodeRateX1024(row)=h.target_code_rate_x1024(i);
        Rank(row)=rank; RequiredSINRdB(row)=20+i+rank;
        SourceCaseID(row)="test_fixture_"+h.entry_id(i)+"_r"+string(rank);
        SourceChannel(row)="AWGN";
    end
end
T = table(EntryID,MCSIndex,Qm,TargetCodeRateX1024,Rank,BLERTarget, ...
    RequiredSINRdB,SourceCaseID,SourceChannel,TransportBlockCount,ErrorCount, ...
    Censored,ExecutionBackend,SourceClassification);
T.DelaySpread_ns=zeros(n,1);
T.AntennaCaseID=repmat("mimo_4x4_r1_r4",n,1);
T.TxChains=repmat(4,n,1); T.RxChains=repmat(4,n,1);
T.RFBranch=repmat("ideal_debug",n,1);
T.RFProfileID=repmat("fixture_ideal_not_physical_calibration",n,1);
T.PowerPlane=repmat("normalized_total_UE_power_occupied_RE_reference",n,1);
out = sixgr.studies.ran1ai1032.validateAdaptiveCalibrationTable(T,cfg);
assert(out.Ok && out.Status == "PASS" && out.RowCount == n, ...
    "Complete executed-waveform calibration evidence must pass.");

bad = T; bad.ExecutionBackend(1) = "logistic_proxy";
threw = false;
try
    sixgr.studies.ran1ai1032.validateAdaptiveCalibrationTable(bad,cfg);
catch ME
    threw = ME.identifier == "sixgr:ran1ai1032:CalibrationEvidenceRejected";
end
assert(threw, "Proxy calibration must be rejected.");

bad = T; bad.Censored(1) = true;
threw = false;
try
    sixgr.studies.ran1ai1032.validateAdaptiveCalibrationTable(bad,cfg);
catch ME
    threw = ME.identifier == "sixgr:ran1ai1032:CalibrationEvidenceRejected";
end
assert(threw, "Censored rows cannot define an adaptive required-SINR threshold.");
second=T; second.SourceChannel(:)="CDL-C"; second.DelaySpread_ns(:)=300;
out=sixgr.studies.ran1ai1032.validateAdaptiveCalibrationTable([T;second],cfg);
assert(out.PhysicalGroupCount==2,'Different physical profiles must not be pooled.');
bad=[T;second(2:end,:)];
threw=false;
try
    sixgr.studies.ran1ai1032.validateAdaptiveCalibrationTable(bad,cfg);
catch ME
    threw=ME.identifier=="sixgr:ran1ai1032:CalibrationCoverage";
end
assert(threw,'An AWGN threshold must not fill missing fading-channel calibration.');
ok = true;
end
