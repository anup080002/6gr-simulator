function ok = testRAN1AI1032FTP3LoadCalibration()
% Algebraic union, measured-iteration persistence and frozen-comparator gates.
% Callback outputs below are local fixtures; no fixture receipt is published
% to the study result tree or accepted as a measured campaign result.
op=localResources([1;1;2],[1;2;1],{[0 2];[0 2];[0 2]},[0;0;0],[2;2;2]);
gr=localResources([1;1;1],[1;1;2],{0;0;2},[0;0;0],[2;2;1]);
u=sixgr.studies.ran1ai1032.measureSLSResourceUtilization(gr,op,"UL",1);
assert(u.AvailablePRBSymbols==12 && u.OccupiedPRBSymbols==3 && u.RUPercent==25, ...
    "Overlapping MU grants must occupy resources once; idle cell opportunities remain.");
late=sixgr.studies.ran1ai1032.measureSLSResourceUtilization(gr,op,"UL",2);
assert(late.OccupiedPRBSymbols==1 && late.AvailablePRBSymbols==4);
bad=gr; bad.PRBSet{1}=1; % hole in a noncontiguous configured allocation
localThrows(@() sixgr.studies.ran1ai1032.measureSLSResourceUtilization(bad,op,"UL",1), ...
    "sixgr:ran1ai1032:RUGrantOutsideOpportunity");
localThrows(@() sixgr.studies.ran1ai1032.measureSLSResourceUtilization( ...
    removevars(gr,"PRBSet"),op,"UL",1),"sixgr:ran1ai1032:RUAllocationSchema");

cases=localCases();
policy=struct("initial_arrival_rate_per_cell_s",1, ...
    "maximum_arrival_rate_per_cell_s",16,"bracket_expansion_factor",2, ...
    "maximum_iterations",10,"tolerance_percentage_points",0.1, ...
    "minimum_independent_drops",2,"warmup_tti",0);
folder=string(tempname); mkdir(folder);
cleanup=onCleanup(@() localRemove(folder)); %#ok<NASGU>
out=sixgr.studies.ran1ai1032.calibrateSLSFTP3Loads(cases,policy,@localExecute,folder);
assert(out.Ok && height(out.Rates)==1 && out.Rates.ArrivalRatePerCell_s==2);
assert(height(out.Iterations)==2 && out.Rates.MeasuredRUPercent==50);
assert(isfile(fullfile(folder,"frozen_ftp3_rates.csv")));
bound=sixgr.studies.ran1ai1032.bindSLSFTP3Calibration(cases,out.Rates,struct("Fixture",true));
assert(all(bound.FTP3ArrivalRatePerCell_s==2));
assert(isequaln(bound.ExecutionParameters,cases.ExecutionParameters));
assert(all(~bound.PrimaryResultEligible),"Load calibration cannot release unqualified PHY.");
for k=1:height(bound)
    assert(bound.ConfigDelta{k}.traffic.ftp3.arrivalRatePerCell_s==2);
end
tampered=out.Rates; tampered.ArrivalRatePerCell_s=3;
localThrows(@() sixgr.studies.ran1ai1032.bindSLSFTP3Calibration(cases,tampered,struct("Fixture",true)), ...
    "sixgr:ran1ai1032:FrozenLoadEvidence");
localThrows(@() sixgr.studies.ran1ai1032.bindSLSFTP3Calibration(cases,out.Rates,struct("ChangedPHY",true)), ...
    "sixgr:ran1ai1032:FrozenLoadRuntimeConfig");
localThrows(@() sixgr.studies.ran1ai1032.calibrateSLSFTP3Loads( ...
    cases,policy,@localProxy,fullfile(folder,"rejected")), ...
    "sixgr:ran1ai1032:LoadCalibrationEvidence");
assert(~isempty(dir(fullfile(folder,"rejected","**","failure.mat"))), ...
    "A rejected iteration must retain the failure and runtime output.");
abstractCases=cases;
abstractCases.PlannedExecutionArchitecture=repmat("calibrated_link_abstraction",height(cases),1);
estimate=sixgr.studies.ran1ai1032.calibrateSLSFTP3Loads(abstractCases,policy,@localCalibrated,fullfile(folder,'abstract_fixture'));
assert(estimate.Ok && estimate.Rates.PHYExecutionMode=="CALIBRATED_LINK_ABSTRACTION");
assert(estimate.Rates.LinkCalibrationSHA256==string(repmat('a',1,64)));
boundEstimate=sixgr.studies.ran1ai1032.bindSLSFTP3Calibration(abstractCases,estimate.Rates,localAbstractBase());
assert(all(boundEstimate.FTP3LinkCalibrationSHA256==estimate.Rates.LinkCalibrationSHA256));
assert(all(~boundEstimate.PrimaryResultEligible));
localThrows(@()sixgr.studies.ran1ai1032.bindSLSFTP3Calibration(abstractCases,out.Rates,struct("Fixture",true)), ...
    "sixgr:ran1ai1032:FrozenLoadBackend");
localThrows(@()sixgr.studies.ran1ai1032.calibrateSLSFTP3Loads( ...
    abstractCases,policy,@localUnqualified,fullfile(folder,'unqualified_fixture')), ...
    "sixgr:ran1ai1032:LoadCalibrationEvidence");
localThrows(@()sixgr.studies.ran1ai1032.calibrateSLSFTP3Loads( ...
    abstractCases,policy,@localChangedCalibration,fullfile(folder,'changed_calibration_fixture')), ...
    "sixgr:ran1ai1032:LoadCalibrationConfigChanged");
% Real spatial configurations contain complex beam/PMI matrices. Retain both
% quadratures in load identity; a phase-only edit must invalidate binding.
complexRun=sixgr.studies.ran1ai1032.calibrateSLSFTP3Loads(abstractCases,policy, ...
    @localComplex,fullfile(folder,'complex_beam_fixture'));
base=localComplexBase();
boundComplex=sixgr.studies.ran1ai1032.bindSLSFTP3Calibration(abstractCases,complexRun.Rates,base);
assert(all(~boundComplex.PrimaryResultEligible));
base.phy.csirs.precoderMatrices=conj(base.phy.csirs.precoderMatrices);
localThrows(@()sixgr.studies.ran1ai1032.bindSLSFTP3Calibration(abstractCases,complexRun.Rates,base), ...
    'sixgr:ran1ai1032:FrozenLoadRuntimeConfig');
ok=true;
end

function out=localComplex(request)
out=localCalibrated(request);
out.Details.LoadCalibrationBaseConfigSHA256=string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(localComplexBase())),'UTF-8'))));
out.Details.SchedulerGrants.Precoder=repmat({[1;1i]/sqrt(2)},height(out.Details.SchedulerGrants),1);
end
function base=localComplexBase()
base=localAbstractBase(); base.phy.csirs.precoderMatrices=[1;1i]/sqrt(2);
end

function out=localCalibrated(request)
% Contract fixture, never persisted to primary study results.
out=localExecute(request); d=out.Details;
d.WaveformBacked=false; d.ProxyPHYActive=true;
d.ExecutionBackend="CALIBRATED_LINK_ABSTRACTION";
d.SourceClassification="calibrated_sls_estimate_not_waveform_truth";
d.CalibrationQualified=true; d.CalibrationSHA256=string(repmat('a',1,64));
d.LoadCalibrationBaseConfigSHA256=string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(jsonencode(localAbstractBase()),'UTF-8'))));
out.Details=d;
end
function base=localAbstractBase()
base=struct('Fixture',true,'system',struct('phyBackend','calibrated_link_abstraction', ...
    'linkAbstraction',struct('calibrationSHA256',repmat('a',1,64))));
end
function out=localUnqualified(request)
out=localCalibrated(request); out.Details.CalibrationQualified=false;
end
function out=localChangedCalibration(request)
out=localCalibrated(request);
if request.Iteration>1, out.Details.CalibrationSHA256=string(repmat('b',1,64)); end
end

function out=localExecute(request)
n=round(2*request.ArrivalRatePerCell_s);
op=localResources(1,1,{0:7},0,1);
gr=localResources(1,1,{0:n-1},0,1);
d=struct("WaveformBacked",true,"ProxyPHYActive",false,"FallbackUsed",false, ...
    "SeedBundle",request.Case.ExecutionParameters{1}.SeedBundle, ...
    "SchedulerGrants",gr,"ResourceOpportunityTable",op, ...
    "TrafficArrivalEvents",table(1,'VariableNames',{'FixtureArrival'}),"TrafficModel","ftp3", ...
    "TrafficArrivalRatePerCell_s",request.ArrivalRatePerCell_s, ...
    "DecodeUnavailableUL",0, ...
    "LoadCalibrationBaseConfigSHA256",string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(jsonencode(struct("Fixture",true)),"UTF-8")))));
out=struct("Ok",true,"Details",d);
end

function out=localProxy(request)
out=localExecute(request); out.Details.ProxyPHYActive=true;
end

function cases=localCases()
cases=table(repmat("UMa",4,1),repmat("Profile-1",4,1),repmat(50,4,1), ...
    repmat("ue_2tx",4,1),repmat("mu_mimo_main",4,1),repmat("main_31dbm",4,1), ...
    ["S0";"S0";"S1";"S1"],["d1";"d2";"d1";"d2"], ...
    ["s0d1";"s0d2";"s1d1";"s1d2"], ...
    'VariableNames',{'Scenario','Population','TargetRUPercent','UETxCase', ...
    'SpatialMode','PowerCase','ComparatorID','IndependentDropID','CaseID'});
cases.ConfigDelta=repmat({struct("traffic",struct("ftp3",struct()))},4,1);
cases.ExecutionParameters={struct("SeedBundle",struct("TrafficSeed",1)); ...
    struct("SeedBundle",struct("TrafficSeed",2)); ...
    struct("SeedBundle",struct("TrafficSeed",1)); ...
    struct("SeedBundle",struct("TrafficSeed",2))};
cases.ConfigDeltaSHA256=strings(4,1);
cases.CasePairKey=["p1";"p2";"p1";"p2"];
cases.BasePairKey=cases.CasePairKey;
cases.SeedBundleID=["seed1";"seed2";"seed1";"seed2"];
cases.ArrivalStreamID=["arrival1";"arrival2";"arrival1";"arrival2"];
cases.PrimaryResultEligible=false(4,1);
end

function T=localResources(cellID,tti,prbs,symbolStart,numSymbols)
T=table(tti,cellID,repmat("UL",numel(tti),1),prbs,symbolStart,numSymbols, ...
    'VariableNames',{'TTI','CellID','Direction','PRBSet','SymbolStart','NumSymbols'});
end

function localThrows(f,id)
try
    f();
catch ME
    assert(string(ME.identifier)==id,"Unexpected error: %s",ME.message);
    return
end
error("Expected exception %s",id);
end

function localRemove(folder)
if isfolder(folder), rmdir(folder,"s"); end
end
