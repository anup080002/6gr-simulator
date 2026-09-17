function ok=testResearchCalibrationLibrary(calibrationPath)
% Reuse immutable executed calibration; no invented CRC rows or PHY shortcuts.
assert(nargin==1 && isfile(calibrationPath),'An existing completed coded calibration is required.');
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
folder=fileparts(calibrationPath); s=jsondecode(fileread(fullfile(folder,'resolved_config.json')));
s.research_adaptation.calibration_file=char(calibrationPath);
if isfield(s.research_adaptation,'calibration_files')
    s.research_adaptation=rmfield(s.research_adaptation,'calibration_files');
end
base=sixgr.phy.research.loadAWGNCalibration(s,"DL");
assert(all(isfinite(base.ThresholdDb)),'Use a calibration fixture with all modes qualified.');
assert(base.SHA256==sixgr.util.sha256File(calibrationPath));
% Menu ordering is not the identity of a physical candidate.
order=numel(s.research_adaptation.candidate_layers):-1:1;
reordered=s;
for name=["candidate_modulations","candidate_layers","candidate_code_rates"]
    reordered.research_adaptation.(name)=s.research_adaptation.(name)(order);
end
reordered.research_adaptation.bootstrap_candidate=find(order==s.research_adaptation.bootstrap_candidate);
other=sixgr.phy.research.loadAWGNCalibration(reordered,"DL");
assert(isequal(other.ThresholdDb,base.ThresholdDb(order)));
bad=s; bad.research_dl.num_prbs=s.research_dl.num_prbs+1;
localThrows(@()sixgr.phy.research.loadAWGNCalibration(bad,"DL"),'sixgr:research:CalibrationProfileMismatch');
bad=s; bad.research_adaptation.calibration_files={char(calibrationPath)};
localThrows(@()sixgr.phy.research.loadAWGNCalibration(bad,"DL"),'sixgr:research:DuplicateCalibrationEvidence');
tag="calibration_library_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
root=fullfile(pwd,'results','component_validation',tag,'audit_test_inputs'); mkdir(root);
T=readtable(calibrationPath,'TextType','string');
% Split real candidate evidence across sources: no rows or hashes rewritten.
one=localSubset(T(T.Candidate~=s.research_adaptation.bootstrap_candidate,:),root,'modes_a',folder);
two=localSubset(T(T.Candidate==s.research_adaptation.bootstrap_candidate,:),root,'modes_b',folder);
split=s; split.research_adaptation.calibration_file=char(one);
split.research_adaptation.calibration_files={char(two)};
joined=sixgr.phy.research.loadAWGNCalibration(split,"DL");
assert(isequal(joined.ThresholdDb,base.ThresholdDb));
assert(numel(joined.SourceSHA256)==2 && numel(joined.Evidence)==numel(base.Evidence));
% Splitting thirty real trials into two short sources must NOT pool into a pass.
one=localSubset(T(mod(T.TrialIndex,2)==1,:),root,'odd_trials',folder);
two=localSubset(T(mod(T.TrialIndex,2)==0,:),root,'even_trials',folder);
split.research_adaptation.calibration_file=char(one);
split.research_adaptation.calibration_files={char(two)};
localThrows(@()sixgr.phy.research.loadAWGNCalibration(split,"DL"),'sixgr:research:UnqualifiedAdaptationCandidates');
% An incomplete producer cannot be consumed even if some points look good.
mkdir(fullfile(fileparts(one),'meta'));
sixgr.util.jsonWrite(fullfile(fileparts(one),'meta','manifest.json'),struct('Status',"running"));
localThrows(@()sixgr.phy.research.loadAWGNCalibration(split,"DL"),'sixgr:research:IncompleteCalibration');
ok=true; fprintf('RESEARCH_CALIBRATION_LIBRARY_PASS audit_inputs=%s\n',root);
end

function path=localSubset(T,root,name,originalFolder)
folder=fullfile(root,name); mkdir(folder); path=fullfile(folder,'trials.csv');
sixgr.util.csvWriteTable(path,T);
for file=["provenance.json","resolved_config.json"]
    copyfile(fullfile(originalFolder,file),fullfile(folder,file));
end
end

function localThrows(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection %s.',id);
end
