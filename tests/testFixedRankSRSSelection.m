function ok=testFixedRankSRSSelection()
% Independent codebook/MMSE algebra at the SRS-estimator input boundary.
% This is not physical SRS acquisition or waveform qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.rankPolicy='fixed_rank';
cfg.phy.pusch.numLayers=4; cfg.phy.pusch.nLayers=4;
cfg.phy.pusch.maxRankDefault=4;
cfg.phy.pusch.NumAntennaPorts=4; cfg.phy.pusch.numAntennaPorts=4;
cfg.phy.pusch.transmissionScheme='codebook';
cfg.phy.pusch.transformPrecoding=false;
% This poorly conditioned channel favors lower rank if adaptation is
% allowed. Fixed rank must expose its weak layers, not silently drop them.
channel=ones(4)/2+.01*eye(4); noise=.1;
H=repmat(reshape(complex(channel),1,1,4,4),24,2,1,1);
fixed=sixgr.phy.ul.estimateSRSRITPMI(H,noise,cfg);
assert(fixed.Valid && fixed.RI==4 && fixed.AllowedRanks==4 && ...
    fixed.RankCandidateCount==1 && numel(fixed.SelectedPostEqSINRPerLayer_dB)==4);
assert(fixed.RISource=="ul_srs_configured_fixed_rank_measured_tpmi");
catalog=sixgr.phy.ul.puschCodebookCatalog(4,4,false);
bestMI=-Inf; bestTPMI=NaN; bestSINR=[];
for tpmi=reshape(double(catalog.ValidTPMISet),1,[])
    W=double(nrPUSCHCodebook(4,4,tpmi,false)).';
    effective=channel*W;
    mmse=(eye(4)+(effective'*effective)/noise)\eye(4);
    sinr=1./real(diag(mmse))-1;
    mutualInformation=sum(log2(1+sinr));
    if mutualInformation>bestMI
        bestMI=mutualInformation; bestTPMI=tpmi; bestSINR=10*log10(sinr);
    end
end
assert(fixed.TPMI==bestTPMI && ...
    abs(fixed.TPMIMutualInformation-bestMI)<1e-10 && ...
    max(abs(fixed.SelectedPostEqSINRPerLayer_dB(:)-bestSINR))<1e-8);
adaptiveCfg=cfg; adaptiveCfg.phy.linkAdaptation.rankPolicy='measured_ri';
adaptive=sixgr.phy.ul.estimateSRSRITPMI(H,noise,adaptiveCfg);
assert(adaptive.Valid && adaptive.RI<4 && isequal(adaptive.AllowedRanks,1:4));
% No silent clamping of a fixed-rank request to too few receive dimensions.
try
    sixgr.phy.ul.estimateSRSRITPMI(H(:,:,1:2,:),noise,cfg);
    error('test:MissingRejection','Fixed rank four cannot use two receive dimensions.');
catch cause
    assert(string(cause.identifier)=="sixgr:phy:ul:UnsupportedFixedSRSRank");
end
latest=sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRowRuntime();
latest.Valid=true; latest.RI=4; latest.PMI=bestTPMI; latest.SourceSlot=9;
state=struct('CfgMobility',cfg,'LatestULFeedback',latest);
wrongRank=struct('EstimatedRI',adaptive.RI,'EstimatedTPMI',adaptive.TPMI);
held=sixgr.truth.CoupledTruthRuntime.updateLatestULFeedbackFromSRSTrialRuntime( ...
    state,1,wrongRank,14);
assert(isequaln(state,held),'Incompatible SRS must not refresh or overwrite a prior rank-four decision.');
fprintf('FIXED_RANK_SRS_SELECTION_PASS fixed_RI=%g adaptive_RI=%g TPMI=%g native_MMSE_agrees=1\n', ...
    fixed.RI,adaptive.RI,fixed.TPMI);
ok=true;
end
