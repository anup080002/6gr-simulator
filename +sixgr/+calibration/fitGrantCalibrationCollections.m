function result=fitGrantCalibrationCollections(referenceFolder,targetFolder,referenceKey,targetKey,rvSequence,policy)
%FITGRANTCALIBRATIONCOLLECTIONS Fit from sealed, exactly matched grant trials.
% Independent AWGN validation and held-out fading validation are mandatory.
% A passing fit is not production installation or network/RF qualification.
arguments
    referenceFolder (1,1) string
    targetFolder (1,1) string
    referenceKey (1,1) struct
    targetKey (1,1) struct
    rvSequence (1,:) double
    policy (1,1) struct
end
assert(string(targetKey.EffectiveSINRMethod)=="calibrated_eesm" && ...
    string(referenceKey.EffectiveSINRMethod)=="calibrated_eesm", ...
    'sixgr:calibration:GrantFittingMethod', ...
    'This fitter executes EESM; it cannot produce a MIESM-labeled calibration.');
[reference,heldout,referenceProof]=sixgr.calibration.readGrantCalibrationReference( ...
    referenceFolder,referenceKey,targetKey,rvSequence);
[rows,targetProof]=sixgr.calibration.readGrantCalibrationFeatureRows( ...
    targetFolder,targetKey,numel(rvSequence));
assert(targetProof.AllPlannedEpisodesPresent && ~isempty(rows), ...
    'sixgr:calibration:TargetCollection','Complete the frozen target plan before fitting.');
assert(referenceProof.SourceIdentitySHA256==targetProof.SourceIdentitySHA256 && ...
    referenceProof.ChannelEvolution==targetProof.ChannelEvolution && ...
    isequal(referenceProof.HARQSlotOffsets0,targetProof.HARQSlotOffsets0), ...
    'sixgr:calibration:ReferenceSourceMismatch','Reference and target require the same frozen source and HARQ evolution policy.');
assert(isempty(intersect(referenceProof.ComponentSeeds,targetProof.ComponentSeeds)), ...
    'sixgr:calibration:ReferenceValidationLeakage','AWGN and fading populations must not reuse component seeds.');
assert(all(cellfun(@(v)isequal(v,rvSequence),rows.RVSequence)), ...
    'sixgr:calibration:ReferenceRV','Target trials use a different HARQ sequence.');
reference.SupportedMask=reference.TrialCount>=policy.minimum_conditional_trials & ...
    heldout.TrialCount>=policy.minimum_conditional_trials;
referenceCheck=sixgr.calibration.validateIndependentReference(reference,heldout,policy);
assert(referenceCheck.Passed,'sixgr:calibration:ReferenceValidation', ...
    'Independent waveform AWGN reference uncertainty exceeds the frozen tolerance.');
result=sixgr.calibration.fitEffectiveSINR(reference,rows(rows.Role=="fit",:), ...
    rows(rows.Role=="validation",:),policy);
result.Reference=reference;
result.ReferenceHeldout=heldout;
result.ReferenceValidation=referenceCheck;
result.ReferenceCollectionIdentity=referenceProof.CollectionIdentity;
result.TargetCollectionIdentity=targetProof.CollectionIdentity;
result.SourceIdentitySHA256=targetProof.SourceIdentitySHA256;
result.RuntimeKey=targetKey;
result.RVSequence=rvSequence;
result.ChannelEvolution=targetProof.ChannelEvolution;
result.HARQSlotOffsets0=targetProof.HARQSlotOffsets0;
result.ProductionPackageInstalled=false;
end
