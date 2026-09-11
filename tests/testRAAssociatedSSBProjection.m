function ok = testRAAssociatedSSBProjection()
% Actual SSB waveform mapping plus common-DL association negatives.
setup6GRSimToolkit('Verbose',false);
scenario = sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml');
cfg = sixgr.lls6g.buildInternalConfig(scenario,tempname);
indices = double(cfg.phy.ssb.activeCandidateIndices0Based);
selected = indices(end);
assert(selected>0,'Exercise a nonzero associated SSB index.');
cfg.phy.ssb.runtimeSSBIndex = selected;
cfg.random_access.associated_ssb_index = selected;
cfg.random_access.associated_ssb_selection_source = ...
    'component_association_fixture_not_rf_measurement';
cfg.phy.ssb.waveformDomain = 'physical_element_domain';
bitmap = false(1,cfg.phy.ssb.Lmax); bitmap(selected+1) = true;
cfg.phy.ssb.activeBitmap = bitmap;
% Complex weights make an erroneous conjugation observable.
row = [1 1i -1 -1i]/2;
cfg.phy.ssb.precoderIDs = "same_actual_SSB_weights";
forms = {row,repmat(row,cfg.phy.ssb.Lmax,1), ...
    repmat({row},1,cfg.phy.ssb.Lmax)};
for k=1:numel(forms)
    cfg.phy.ssb.precoderMatrices = forms{k};
    [projection,id,evidence] = sixgr.phy.ra.resolveAssociatedSSBProjection(cfg,4);
    assert(isequal(projection,row.') && id=="same_actual_SSB_weights");
    assert(evidence.SourceReferenceSignalId==selected && evidence.SourceReferenceSignal=="SSB");
    assert(evidence.ProjectionMatrixSHA256==string(sixgr.phy.mimo.MatrixContract.digest(row.')));
end
cfg.phy.ssb.precoderMatrices = row;
previousRNG = rng; restoreRNG = onCleanup(@()rng(previousRNG)); %#ok<NASGU>
rng(1021,'twister');
[mapped,~,actual] = sixgr.phy.dl.SSB_Tx(cfg,'SSBIndex',selected,'NumSubframes',5);
referenceCfg=cfg; referenceCfg.phy.ssb.precoderMatrices=1;
rng(1021,'twister');
[reference,~,~] = sixgr.phy.dl.SSB_Tx(referenceCfg,'SSBIndex',selected,'NumSubframes',5);
[projection,~,evidence] = sixgr.phy.ra.resolveAssociatedSSBProjection(cfg,4);
expected=reference*projection.';
assert(isequal(size(mapped),size(expected)) && ...
    norm(mapped-expected,'fro')<=1e-12*max(1,norm(expected,'fro')), ...
    'Common-DL projection must match the actual transmitted SSB coefficients, without conjugation.');
assert(evidence.SSBPrecoderMatrixSHA256==actual.SSBBurstPlan.PrecoderMatrixSHA256(selected+1));
bad=cfg; bad.phy.ssb.runtimeSSBIndex=0;
localReject(@()sixgr.phy.ra.resolveAssociatedSSBProjection(bad,4), ...
    'sixgr:phy:ra:CommonDownlinkSSBAssociationMismatch');
bad=cfg; bad.random_access.associated_ssb_selection_source="";
localReject(@()sixgr.phy.ra.resolveAssociatedSSBProjection(bad,4), ...
    'sixgr:phy:ra:CommonDownlinkSSBAssociationMismatch');
bad=cfg; bad.phy.ssb.activeBitmap=false(1,cfg.phy.ssb.Lmax);
bad.phy.ssb.activeBitmap(1)=true;
localReject(@()sixgr.phy.ra.resolveAssociatedSSBProjection(bad,4), ...
    'sixgr:phy:ia:InactiveAssociatedSSB');
localReject(@()sixgr.phy.ra.resolveAssociatedSSBProjection(cfg,2), ...
    'sixgr:phy:ra:StagePortProjectionDimensionMismatch');
for malformed=[NaN Inf -1 2]
    bad=cfg; bad.phy.ssb.activeBitmap=double(bitmap);
    bad.phy.ssb.activeBitmap(selected+1)=malformed;
    localReject(@()sixgr.phy.ra.resolveAssociatedSSBProjection(bad,4), ...
        'sixgr:phy:ia:InvalidSSBBitmap');
end
ok=true;
end

function localReject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s',id,cause.identifier);
    return;
end
error('sixgr:test:MissingExpectedFailure','Expected %s',id);
end
