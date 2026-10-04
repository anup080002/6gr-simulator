function receipt=buildGrantCalibrationPackage(spec,policy,outputFile)
%BUILDGRANTCALIBRATIONPACKAGE Install only requalified sealed grant evidence.
% Caller supplies locations/keys/policy, never beta, CRC counts or a pass flag.
arguments
    spec (1,1) struct
    policy (1,1) struct
    outputFile (1,1) string
end
assert(~isfile(outputFile),'sixgr:abstraction:CalibrationOutputExists','Never overwrite a frozen calibration.');
assert(all(isfield(spec,{'CalibrationID','Collections'})) && ...
    isstruct(spec.Collections) && ~isempty(spec.Collections) && ...
    isscalar(string(spec.CalibrationID)) && strlength(strtrim(string(spec.CalibrationID)))>0, ...
    'sixgr:abstraction:GrantCalibrationSpecification','Require identifiable grant-backed collection specifications.');
root=string(fileparts(outputFile)); if strlength(root)==0, root=string(pwd); end
assert(isfolder(root),'sixgr:abstraction:GrantCalibrationSource','Create the retained package root first.');
curves=cell(1,numel(spec.Collections));
for k=1:numel(curves)
    curves{k}=sixgr.system.abstraction.reconstructGrantCalibrationCurve(spec.Collections(k),policy,root);
end
calibration=struct('Schema',"sixgr.grant_calibrated_sls_link/v1", ...
    'CalibrationID',string(spec.CalibrationID),'SourceClassification',"executed_waveform_calibration", ...
    'Curves',[curves{:}],'Collections',spec.Collections,'PrimaryStudyAccepted',false);
sixgr.system.abstraction.validateGrantCalibrationPackage(calibration,outputFile,policy);
staging=string(tempname(root))+".mat";
save(staging,'calibration','-v7.3');
sixgr.calibration.commitFile(staging,outputFile);
receipt=struct('CalibrationFile',outputFile,'SHA256',sixgr.csi.studyFileSHA256(outputFile), ...
    'CurveCount',numel(curves),'SourceClassification',"executed_waveform_calibration", ...
    'StatisticalPolicyPassed',true,'PrimaryStudyAccepted',false);
end
