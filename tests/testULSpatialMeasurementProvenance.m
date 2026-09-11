function ok=testULSpatialMeasurementProvenance()
% Analytical spatial fixture: configuration cannot create RX/TX evidence.
cfg=sixgr.config.defaultConfig();
cfg.phy.nRxAnt=2; cfg.phy.nTxAnt=2;
cfg.phy.pusch.transmissionScheme='codebook';
cfg.phy.pusch.transformPrecoding=false;
cfg.phy.pusch.NumAntennaPorts=2; cfg.phy.pusch.numAntennaPorts=2;
cfg.phy.pusch.maxRankDefault=2;
cfg.phy.pusch.nLayers=1;
cfg.phy.pusch.TPMI=0;
H=repmat(reshape(eye(2),1,1,2,2),[24 14 1 1]);
dmrs=@(channel,prec) sixgr.phy.ul.measureULLinkState(channel,0.01,cfg, ...
    'PrecoderInfo',prec,'ChannelEstimateDomain','pusch_dmrs_effective_layer_domain');
measured=dmrs(H,struct());
assert(measured.RankEstimate==2 && measured.RI==2, ...
    'Measured effective-channel rank must not be clamped to a configuration hint.');
assert(measured.ConfiguredPMI==0 && isnan(measured.RuntimeAppliedPMI) && isnan(measured.PMI), ...
    'Configured TPMI must not become applied or measured TPMI without transmitter evidence.');
zero=dmrs(zeros(size(H)),struct());
assert(zero.RankEstimate==0 && isnan(zero.RI), ...
    'A zero-rank channel cannot manufacture positive RI from configuration.');
for bad={NaN,-1,0.5,[0 1]}
    absent=dmrs(H,struct('AppliedPrecoderPMI',bad{1}));
    assert(isnan(absent.RuntimeAppliedPMI) && isnan(absent.PMI));
end
applied=dmrs(H,struct('AppliedPrecoderPMI',1,'AppliedBeamIndexSet','[1 2]'));
assert(applied.RuntimeAppliedPMI==1 && applied.PMI==1 && applied.ConfiguredPMI==0);
assert(isempty(applied.SelectedBeamIndices) && isnan(applied.BeamCandidateCount), ...
    'A codebook port set does not prove measured spatial beams or candidate count.');
assert(strcmp(applied.CSIReportMode,'ul_pusch_dmrs_effective_channel_no_tpmi_recommendation'));
srs=sixgr.phy.ul.measureULLinkState(H,0.01,cfg,'ChannelEstimateDomain','srs_port_domain');
assert(srs.SRSRITPMIValid && isfinite(srs.PMI) && isnan(srs.RuntimeAppliedPMI), ...
    'An SRS recommendation is available independently of an applied PUSCH TPMI.');
estimate=sixgr.phy.ul.estimateSRSRITPMI(H,0.01,cfg);
[~,~,W]=sixgr.phy.ul.puschCodebookProjectionMatrix(estimate.RI,2,estimate.TPMI,false);
ports=find(sum(abs(W).^2,1)>0);
assert(isequal(srs.SelectedCodebookPortIndices1Based,ports) && ...
    isequal(estimate.SelectedCodebookPortIndices1Based,ports) && ...
    isempty(estimate.SelectedBeamIndices) && isempty(srs.SelectedBeamIndices), ...
    'Selected codebook support must remain port-domain, not fabricated spatial beam IDs.');
ok=true;
end
