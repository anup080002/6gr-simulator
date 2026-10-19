function [qualified,status,details]=summarizeDetectorQualification(falseT,missT,scope)
% Both independently executed H0 and H1 populations are necessary.
% This reducer never upgrades component evidence to installed-runtime or NR
% conformance evidence. Each population retains its own exact bound verdict.
arguments
    falseT table
    missT table
    scope (1,1) string {mustBeMember(scope,["component","installed_runtime"])} = "component"
end
[h0,q0]=sixgr.stats.summarizeBinomialQualifications(falseT);
[h1,q1]=sixgr.stats.summarizeBinomialQualifications(missT);
complete0=localCoverage(falseT,"independent_noise_only_waveform");
complete1=localCoverage(missT,"independent_signal_present_waveform");
sameContext=false;
if complete0 && complete1
    contexts=unique([string(falseT.QualificationContextHash);string(missT.QualificationContextHash)]);
    sameContext=numel(contexts)==1 && ~ismissing(contexts) && strlength(contexts)>0;
end
qualified=h0 && h1 && q0=="PASS" && q1=="PASS" && complete0 && complete1 && sameContext;
status="NOT_EVALUATED";
if q0=="FAIL" || q1=="FAIL", status="FAIL";
elseif qualified, status="PASS";
end
details=struct('H0Status',q0,'H1Status',q1,'H0Complete',complete0, ...
    'H1Complete',complete1,'SameContext',sameContext, ...
    'Scope',"component_detector_not_runtime_or_NR_conformance");
if qualified && scope=="installed_runtime"
    % This producer's direct AWGN trials bypass installed fading/RF/spatial
    % execution. Shared run identity alone cannot establish context equality.
    qualified=false;
    status="NOT_EVALUATED:component_context_not_installed_runtime";
end
end

function complete=localCoverage(T,unit)
required=["SweepId","PlannedOperatingPointCount","QualificationContextHash", ...
    "QualificationScope","EvidenceUnit","WaveformTrialCount"];
complete=false;
if isempty(T) || ~all(ismember(required,string(T.Properties.VariableNames))), return; end
n=T.PlannedOperatingPointCount; trials=T.WaveformTrialCount;
complete=isnumeric(n)&&isnumeric(trials)&&all(isfinite(n))&&all(n==height(T)) && ...
    all(isfinite(trials)&trials>=1&trials==fix(trials)) && ...
    ~any(ismissing(string(T.SweepId))) && all(strlength(string(T.SweepId))>0) && ...
    numel(unique(string(T.SweepId)))==height(T) && ...
    all(string(T.EvidenceUnit)==unit) && ...
    all(string(T.QualificationScope)=="awgn_component_not_nr_conformance");
end
