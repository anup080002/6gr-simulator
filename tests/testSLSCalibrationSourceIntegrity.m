function ok=testSLSCalibrationSourceIntegrity()
% File/row authentication CONTRACT fixture, not executed PHY qualification.
% These small invented rows exercise rejection only; no study calibration
% package is produced and no physical statistics are claimed by this test.
folder=string(tempname); mkdir(folder);
key=struct('FixtureOnly',true);
keySHA=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(key),'UTF-8'))));
curve=struct('CurveID',"contract_fixture",'Key',key,'RVSequence',0,'TrialCount',[2;2], ...
    'ErrorCount',[1;2],'ValidationTrialCount',[2;2],'ValidationErrorCount',[1;2]);
data=struct('Curves',curve);
fit=table(repmat("contract_fixture",4,1),[1;1;2;2],"fit_"+(1:4)',ones(4,1), ...
    [0;1;1;1],false(4,1),true(4,1),repmat(keySHA,4,1), ...
    'VariableNames',{'CurveID','GridPointIndex','TrialID','AttemptIndex','CRCError', ...
    'PriorAttemptsFailed','WaveformExecuted','CalibrationKeySHA256'});
heldout=fit; heldout.TrialID="heldout_"+(1:4)';
writetable(fit,fullfile(folder,'fit.csv')); writetable(heldout,fullfile(folder,'heldout.csv'));
data=localSources(data,folder);
matPath=fullfile(folder,'contract_fixture_not_a_calibration.mat');
sixgr.system.abstraction.validateCalibrationSources(data,matPath);
% Packaging must derive counts from retained rows, then reject this tiny
% fixture population under the production statistical policy. No file may
% appear when any gate fails.
fragment=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
spec=data; spec.CalibrationID="not_production";
spec.SourceClassification="executed_waveform_calibration";
spec.Curves.Key.EffectiveSINRMethod="calibrated_eesm";
spec.Curves.RVSequence=0; spec.Curves.SINRAxes_dB={[-10;10]}; spec.Curves.BetaLinear=1;
localReject(@()sixgr.system.abstraction.buildCalibrationFromTrials(spec,fragment.system.linkAbstraction,matPath), ...
    'sixgr:abstraction:CalibrationStatistics');
assert(~isfile(matPath));
production=data; production.SourceClassification="executed_waveform_calibration";
localReject(@()sixgr.system.abstraction.validateCalibrationSources(production,matPath), ...
    'sixgr:abstraction:CalibrationSources');
bad=data; bad.Curves.ErrorCount(1)=2;
localReject(@()sixgr.system.abstraction.validateCalibrationSources(bad,matPath), ...
    'sixgr:abstraction:CalibrationPopulation');
bad=data; bad.Curves.Key.FixtureOnly=false;
localReject(@()sixgr.system.abstraction.validateCalibrationSources(bad,matPath), ...
    'sixgr:abstraction:CalibrationPopulation');
bad=data; bad.Sources.RelativePath(2)="fit.csv"; bad.Sources.SHA256(2)=bad.Sources.SHA256(1);
localReject(@()sixgr.system.abstraction.validateCalibrationSources(bad,matPath), ...
    'sixgr:abstraction:CalibrationSources');
% Editing a retained file invalidates the digest, even with unchanged counts.
edited=heldout; edited.TrialID(1)="changed"; writetable(edited,fullfile(folder,'heldout.csv'));
localReject(@()sixgr.system.abstraction.validateCalibrationSources(data,matPath), ...
    'sixgr:abstraction:CalibrationDigest');
% Rehashing cannot conceal overlap between fit and held-out trial identities.
edited=heldout; edited.TrialID(1)=fit.TrialID(1); writetable(edited,fullfile(folder,'heldout.csv'));
bad=localSources(data,folder);
localReject(@()sixgr.system.abstraction.validateCalibrationSources(bad,matPath), ...
    'sixgr:abstraction:CalibrationPopulation');
edited=heldout; edited.PriorAttemptsFailed(1)=true; writetable(edited,fullfile(folder,'heldout.csv'));
bad=localSources(data,folder);
localReject(@()sixgr.system.abstraction.validateCalibrationSources(bad,matPath), ...
    'sixgr:abstraction:CalibrationRawSchema');
ok=true; fprintf('SLS_CALIBRATION_SOURCE_INTEGRITY_PASS contract_fixture_only=1\n');
end
function data=localSources(data,folder)
data.Sources=table(["fit";"validation"],["fit.csv";"heldout.csv"], ...
    [sixgr.csi.studyFileSHA256(fullfile(folder,'fit.csv')); ...
     sixgr.csi.studyFileSHA256(fullfile(folder,'heldout.csv'))], ...
    repmat("waveform_contract_fixture_only",2,1), ...
    'VariableNames',{'Role','RelativePath','SHA256','ExecutionBackend'});
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:ExpectedError','Expected %s.',id);
end
