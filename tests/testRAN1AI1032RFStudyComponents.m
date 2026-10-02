function ok=testRAN1AI1032RFStudyComponents()
%TESTRAN1AI1032RFSTUDYCOMPONENTS Sample-level measurements and rejection gates.
setup6GRSimToolkit('Verbose',false);
study=sixgr.studies.ran1ai1032.loadStudyConfig();
out=sixgr.studies.ran1ai1032.runRFComponentQualification(study);
assert(out.ComponentChecksPassed,'RF component measurements failed.');
assert(out.QualificationConfig.SampleCount==study.rf.component_qualification.sample_count, ...
    'RF qualification must use the study YAML configuration.');
assert(~out.DecodedPHYQualified && ~out.ArrayPolarizationQualified && ...
    ~out.PhaseNoiseAt7GHzQualified && ~out.PrimaryResultEligible, ...
    'Component checks must not imply integrated PHY or array qualification.');
x=ones(256,2)/sqrt(2);
b=struct('Endpoint',"rx",'SampleRateHz',122.88e6, ...
    'CarrierFrequencyHz',7e9,'SCSHz',30e3,'NormalizedCFO',0.01, ...
    'SampleOffset',0,'EVMPercent',3,'EVMCorrelation',[1 1;1 1], ...
    'EVMReferencePowerPerChain',[0.5 0.5],'Seed',5,'PhaseNoiseEnabled',false);
y=sixgr.studies.ran1ai1032.applyRFStudyBranch(x,b);
assert(max(abs(y(:,1)-y(:,2)))<1e-12,'Fully correlated equal-power EVM must match across chains.');
a=sixgr.studies.ran1ai1032.applyRFStudyBranch(x(1:97,:),b);
b.SampleOffset=97;
c=sixgr.studies.ran1ai1032.applyRFStudyBranch(x(98:end,:),b);
assert(max(abs(y-[a;c]),[],'all')<1e-12,'EVM innovations and CFO phase must remain invariant to chunk boundaries.');
b.SampleOffset=0; b.EVMCorrelation=[1 2;2 1];
localReject(@()sixgr.studies.ran1ai1032.applyRFStudyBranch(x,b), ...
    'sixgr:ran1ai1032:RFInvalidCovariance');
b.EVMCorrelation=eye(2); b.PhaseNoiseEnabled=true;
localReject(@()sixgr.studies.ran1ai1032.applyRFStudyBranch(x,b), ...
    'sixgr:ran1ai1032:RFPhaseNoiseProfileMissing');
bad=study; bad.rf.additive_evm.reference_power="noisy_received_power";
localReject(@()sixgr.studies.ran1ai1032.runRFComponentQualification(bad), ...
    'sixgr:ran1ai1032:RFQualificationAssumptionMismatch');
ok=true;
end

function localReject(f,id)
caught=false;
try, f(); catch ME, caught=strcmp(ME.identifier,id); end
assert(caught,'Expected error %s.',id);
end
