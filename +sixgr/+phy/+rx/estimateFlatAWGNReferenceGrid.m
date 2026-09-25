function [Hest,nVar,info]=estimateFlatAWGNReferenceGrid(carrier,rxGrid,refInd,refSym,numPorts)
% Practical joint LS for an explicitly established constant AWGN operator.
% The caller MUST establish flat/static channel and clean/compensated RF
% eligibility. Never choose this estimator merely because a fade is weak.
% Only received samples and installed known pilots enter the fit. In
% particular, no true channel, configured SNR or injected noise is accepted.
K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
validateattributes(numPorts,{'numeric'},{'scalar','integer','positive','finite'});
assert(isfloat(rxGrid) && size(rxGrid,1)==K && size(rxGrid,2)==L && ...
    ndims(rxGrid)<=3 && all(isfinite(rxGrid),'all'), ...
    'sixgr:phy:rx:InvalidFlatReferenceGrid','Require one finite received carrier-slot grid.');
indices=double(refInd(:)); symbols=refSym(:);
assert(~isempty(indices) && numel(indices)==numel(symbols) && ...
    all(isfinite(indices) & indices==fix(indices) & indices>=1 & indices<=K*L*numPorts) && ...
    numel(unique(indices))==numel(indices) && all(isfinite(symbols)) && ...
    all(abs(symbols)>0), ...
    'sixgr:phy:rx:InvalidFlatReferencePilots', ...
    'Require unique one-based logical-port indices and matching nonzero known pilots.');
reference=zeros(K*L,numPorts,'like',rxGrid);
reference(indices)=cast(symbols,'like',rxGrid);
physical=unique(mod(indices-1,K*L)+1);
received=reshape(rxGrid,K*L,[]);
fit=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(received(physical,:),reference(physical,:));
% Port-domain references are solved together, including their actual CDM
% signs. Treating each port as a separate scalar pilot fit is incorrect.
gain=fit.GainPerPortReceiveBranch.'; % Nonconjugating transpose: RX-by-port.
Hest=repmat(reshape(gain,1,1,size(gain,1),numPorts),K,L,1,1);
nVar=fit.NoiseVariance;
info=fit;
info.EngineUsed="received_known_pilot_flat_static_joint_least_squares";
info.InterpolationMethod="constant_grid_expansion_explicit_flat_static_awgn_only";
info.EffectiveChannelConvention="resource_grid_rx_antenna_by_reference_port";
info.InferredReferencePortCount=numPorts;
info.NumRxAnt=size(rxGrid,3);
info.PilotRECount=numel(physical);
info.PhysicalPilotIndices1Based=physical;
info.PilotMask=false(K,L); info.PilotMask(physical)=true;
% Publish the same received-pilot reconstruction diagnostics as the
% general channel-estimation path.  The joint LS fit already owns the
% exact received grid, installed pilot indices/symbols and estimated
% effective channel, so leaving these fields absent made CSI-RS residual
% plots empty despite a valid physical observation.  This is measured
% residual evidence; it does not use configured SNR or channel truth.
metrics=sixgr.phy.rx.referenceSignalMetrics(rxGrid,Hest,refInd,refSym, ...
    'NoiseVariance',nVar,'ContextLabel','flat_static_awgn_reference_grid');
info.PilotResidualPower=double(metrics.ResidualPower);
info.PilotSignalPower=double(metrics.SignalPower);
info.PilotResidualNMSE_dB=double(metrics.NMSEdB);
info.PilotNoiseVarianceEstimate=double(metrics.ResidualPower);
info.PilotNoiseVarianceFromEstimator=double(nVar);
% The common LS fit retains signed noise-debiased coefficient/reference
% powers. These are not replacement channel coefficients for RI/PMI/CQI.
end
