function ok=testFixedRankCSISelection()
% Declared-channel CSI boundary test; not waveform or BLER qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=sixgr.config.defaultConfig();
cfg.mimo.strict=false; cfg.phy.mimo.strict=false;
cfg.phy.nTxAnt=4; cfg.phy.nRxAnt=4;
cfg.phy.pdsch.numLayers=4; cfg.phy.pdsch.nLayers=4;
cfg.phy.csi.maxRank=4;
cfg.phy.linkAdaptation.rankPolicy='fixed_rank';
cfg.phy.linkAdaptation.rankThreshold=.5;
cfg.phy.linkAdaptation.minSINRForRank2_dB=10;
cfg.phy.csi.reportCSI=true; cfg.phy.csi.reportRI=true;
cfg.phy.csi.reportPMI=true; cfg.phy.csi.reportCQI=true;
H=diag([1 .01 .01 .01]); noise=.1;
fixed=sixgr.phy.dl.CSI_Feedback(H,noise,cfg,'MaxRank',4);
assert(fixed.RI==4 && fixed.AllowedRanks==4 && ...
    size(fixed.SelectedPrecoder,2)==4);
% Independent linear MMSE reference for the actual chosen precoder.
W=fixed.SelectedPrecoder;
effective=H*W;
mmse=(eye(4)+(effective'*effective)/noise)\eye(4);
expectedSINR=1./real(diag(mmse))-1;
expectedMI=sum(log2(1+expectedSINR));
assert(abs(fixed.SelectedMutualInformation_bpcu-expectedMI)<1e-9 && ...
    max(abs(fixed.SelectedLayerSINR_dB(:)-10*log10(expectedSINR)))<1e-8);
assert(min(expectedSINR)<1, ...
    'The fixed-rank test must retain genuinely weak layers, not boost their power.');
adaptiveCfg=cfg; adaptiveCfg.phy.linkAdaptation.rankPolicy='measured_ri';
adaptive=sixgr.phy.dl.CSI_Feedback(H,noise,adaptiveCfg,'MaxRank',4);
assert(adaptive.RI==1 && isequal(adaptive.AllowedRanks,1:4));
% An explicit restriction cannot be ignored in favor of the rank-one
% fallback. An adaptive search with no eligible candidate remains failed.
restricted=adaptiveCfg; restricted.phy.csi.rankDomain=[2 4];
reject(@()sixgr.phy.dl.CSI_Feedback(H,noise,restricted,'MaxRank',4), ...
    'sixgr:phy:csi:NoEligibleRankCandidate');
reject(@()sixgr.phy.dl.CSI_Feedback(H,noise,cfg, ...
    'ReportConfiguration',struct('AllowedRanks',[1 2])), ...
    'sixgr:phy:csi:UnsupportedFixedCSIRank');
limited=cfg; limited.phy.csi.reportConfiguration=struct('MaxRank',2);
reject(@()sixgr.phy.dl.CSI_Feedback(H,noise,limited,'MaxRank',4), ...
    'sixgr:phy:csi:UnsupportedFixedCSIRank');
short=cfg; short.phy.nRxAnt=2;
reject(@()sixgr.phy.dl.CSI_Feedback(H(1:2,:),noise,short,'MaxRank',4), ...
    'sixgr:phy:csi:UnsupportedFixedCSIRank');
fprintf('FIXED_RANK_CSI_SELECTION_PASS configured=4 fixed_RI=%g adaptive_RI=%g weak_layers_retained=1\n', ...
    fixed.RI,adaptive.RI);
ok=true;
end

function reject(call,id)
try, call(); catch cause, assert(string(cause.identifier)==id,cause.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
