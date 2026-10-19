function ok=testPDCCHJointQualification()
% Numerical acceptance fixtures only, never exported as PHY observations.
setup6GRSimToolkit('Verbose',false);
h0=localRows("independent_noise_only_waveform",2);
h1=localRows("independent_signal_present_waveform",3);
[accepted,status]=sixgr.phy.pdcch.summarizeDetectorQualification(h0,h1);
assert(accepted && status=="PASS");
[accepted,status]=sixgr.phy.pdcch.summarizeDetectorQualification(h0,table());
assert(~accepted && status=="NOT_EVALUATED",'H0 alone must never qualify detection.');
[accepted,status]=sixgr.phy.pdcch.summarizeDetectorQualification(table(),h1);
assert(~accepted && status=="NOT_EVALUATED");
bad=h1; bad.StatisticalQualification(2)="FAIL";
[accepted,status]=sixgr.phy.pdcch.summarizeDetectorQualification(h0,bad);
assert(~accepted && status=="FAIL",'Decisive H1 failure is not acceptance.');
bad=h0; bad.StatisticalQualification(1)="FAIL";
[accepted,status]=sixgr.phy.pdcch.summarizeDetectorQualification(bad,table());
assert(~accepted && status=="FAIL",'Missing H1 must not erase a retained H0 failure.');
for k=1:6
    bad=h1;
    switch k
        case 1, bad=bad(1:2,:);
        case 2, bad.SweepId(2)=bad.SweepId(1);
        case 3, bad.QualificationContextHash(1)="different_receiver_context";
        case 4, bad.EvidenceUnit(:)="correlated_candidate_decision";
        case 5, bad.StatisticallyQualified(1)=false;
        case 6, bad.WaveformTrialCount(1)=NaN;
    end
    [accepted,status]=sixgr.phy.pdcch.summarizeDetectorQualification(h0,bad);
    assert(~accepted && status=="NOT_EVALUATED");
end
[accepted,status]=sixgr.phy.pdcch.summarizeDetectorQualification(h0,h1,"installed_runtime");
assert(~accepted && status=="NOT_EVALUATED:component_context_not_installed_runtime");
runner=fileread(which('sixgr.lls6g.runners.runSingle'));
contract=fileread(which('sixgr.truth.evaluateLLSRuntimeTruthContract'));
assert(contains(runner,'ArtifactTables.pdcch_missed_detection_sweep') && ...
    contains(runner,'"installed_runtime"') && ...
    contains(contract,'localPDCCHStatisticalCampaignOk(falseT, missedT, scfg, cfg)') && ...
    contains(contract,'summarizeDetectorQualification(falseT,missedT,"installed_runtime")'));
ok=true;
fprintf('PDCCH_JOINT_QUALIFICATION_PASS numerical_policy_only=1 H0_alone_rejected=1 component_not_runtime=1\n');
end

function T=localRows(unit,n)
T=table(true(n,1),repmat("PASS",n,1),"point_"+string((1:n)'), ...
    repmat(n,n,1),repmat("numerical_fixture_context",n,1), ...
    repmat("awgn_component_not_nr_conformance",n,1),repmat(unit,n,1),repmat(2000,n,1), ...
    'VariableNames',{'StatisticallyQualified','StatisticalQualification','SweepId', ...
    'PlannedOperatingPointCount','QualificationContextHash','QualificationScope','EvidenceUnit','WaveformTrialCount'});
end
