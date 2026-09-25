function out=measureCSISINRFromResourceGrid(carrier,csirs,receivedGrid,cfg,execution)
% TS 38.215 5.1.6: port 3000, linear reference-RE power, branch diversity.
% One identified resource and one received reference plane per invocation.
% The disturbance estimate uses this resource's actual CDM reference, not
% configured SNR, channel truth, another port's power or a data equalizer.
validateattributes(receivedGrid,{'single','double'},{'nonempty','finite'});
if nargin<4, cfg=struct(); end
if nargin<5, execution=struct(); end
assert(numel(csirs.RowNumber)==1 && string(csirs.CSIRSType)=="nzp", ...
    'sixgr:refsig:CSISINRResourceIdentity','Measure one NZP-CSI-RS resource at a time.');
indices=nrCSIRSIndices(carrier,csirs);
symbols=nrCSIRS(carrier,csirs);
K=size(receivedGrid,1); L=size(receivedGrid,2); nRx=size(receivedGrid,3);
assert(K==12*carrier.NSizeGrid && L==carrier.SymbolsPerSlot, ...
    'sixgr:refsig:CSISINRGridDimensions','CSI-SINR requires the received carrier slot grid.');
if isempty(indices)
    % A configured periodic resource need not transmit in this slot. This
    % is an explicit applicability result, never a synthetic measurement.
    out=struct('Available',false,'Status',"not_transmitted_in_slot", ...
        'CSI_SINR_dB',NaN,'ReferencePort',3000,'ReferenceRECount',0, ...
        'MeasurementDomain',"csi_rs_port3000_reference_re_received_plane");
    return;
end
nPorts=double(csirs.NumCSIRSPorts);
reference=nrResourceGrid(carrier,nPorts);
reference(indices)=symbols;
port0=double(indices(indices<=K*L));
assert(~isempty(port0),'sixgr:refsig:CSISINRPort3000Missing','CSI-SINR requires antenna port 3000 REs.');
cdm=sixgr.phy.refsig.csirsCDMLengths(csirs.CDMType);
power=nan(1,nRx); noise=nan(1,nRx);
estimatorNoise=nan(1,nRx);
estimator=string(sixgr.util.structGet(cfg,'phy.csirs.runtimeChannelEstimator','nr_channel_estimate'));
assert(isscalar(estimator) && any(estimator==["nr_channel_estimate","flat_static_awgn_ls"]), ...
    'sixgr:refsig:InvalidCSIRSEstimator','CSI-SINR must not silently replace an unknown estimator.');
flat=estimator=="flat_static_awgn_ls";
powerEvidence=struct();
im=sixgr.phy.refsig.measureCSIIM(carrier,cfg,receivedGrid);
if im.Plan.Enabled
    assert(im.Available,'sixgr:phy:csiim:MissingObservation', ...
        'CSI-RS measurement requires its configured CSI-IM occasion in the same slot.');
    assert(isempty(intersect(unique(mod(double(indices(:))-1,K*L)+1),im.Plan.PhysicalIndices1Based)), ...
        'sixgr:phy:csiim:ReferenceCollision','NZP CSI-RS and CSI-IM cannot own the same physical REs.');
end
if flat
    [~,~,fit]=sixgr.phy.refsig.estimateCSIRSResourceChannel( ...
        carrier,receivedGrid,indices,symbols,cfg,nPorts,cdm,execution);
    pilotEnergy=mean(abs(reference(port0)).^2);
    rawPower=abs(fit.GainPerPortReceiveBranch(1,:)).^2*pilotEnergy;
    bias=fit.CoefficientErrorVarianceEstimatePerPortReceiveBranch(1,:)*pilotEnergy;
    power=rawPower-bias; % Signed; never clip a noise-only estimate upward.
    noise=fit.NoiseVariancePerReceiveBranch;
    estimatorNoise=noise;
    powerEvidence=struct('RawPort3000PowerPerBranch',rawPower, ...
        'EstimatedNoiseBiasPerBranch',bias,'SignedPort3000PowerPerBranch',power, ...
        'CoefficientErrorVariancePerPortReceiveBranch',fit.CoefficientErrorVarianceEstimatePerPortReceiveBranch, ...
        'PilotCount',fit.PilotRECount,'ResidualComplexDOF',fit.ResidualComplexDegreesOfFreedomPerBranch, ...
        'ClippedToNonnegative',false,'ObservationEligibility',fit.ObservationEligibility);
else
for r=1:nRx
    [h,n]=nrChannelEstimate(carrier,double(receivedGrid(:,:,r)),double(reference), ...
        'CDMLengths',cdm);
    assert(isscalar(n) && isfinite(n) && n>=0, ...
        'sixgr:refsig:CSISINRDisturbanceUnavailable','Received CSI-RS disturbance must be nonnegative and measured.');
    portChannel=h(:,:,1,1);
    power(r)=mean(abs(portChannel(port0).*reference(port0)).^2);
    noise(r)=double(n);
    estimatorNoise(r)=double(n);
end
end
if im.Available, noise=im.PowerPerReceiveAntenna; end
assert(all(isfinite(power)) && (flat || all(power>=0)), ...
    'sixgr:refsig:CSISINRSignalUnavailable','Every receive branch must retain its finite port-3000 power estimate.');
source="nrChannelEstimate_port3000_reference_RE_power_per_receive_branch";
disturbanceSource="nrChannelEstimate_received_reference_residual";
if flat, disturbanceSource="received_flat_joint_LS_residual_with_degrees_of_freedom"; end
estimatorDisturbanceSource=disturbanceSource;
if im.Available, disturbanceSource=string(im.Source); end
if flat
    linear=nan(1,nRx);
    if im.Available
        % Muted REs are disjoint from the pilots: independent denominator.
        % For M complex samples E(1/noisehat)=M/((M-1)*noise).
        d=im.SampleCount;
        if d>1, linear=(d-1)/d*power./noise; end
    else
        d=fit.ResidualComplexDegreesOfFreedomPerBranch;
        if d>1
            linear=(d-1)/d*rawPower./noise- ...
                real(fit.UnitNoiseCoefficientCovariance(1,1))*pilotEnergy;
        end
    end
    ratios=nan(1,nRx); positive=linear>0;
    ratios(positive)=10*log10(linear(positive));
    powerEvidence.SignedPort3000SNRLinearPerBranch=linear;
    powerEvidence.RatioInterpretation="signed_unbiased_linear_per_branch_not_unbiased_dB_or_selected_max";
    source="received_flat_LS_noise_debiased_port3000_reference_RE_power";
else
    ratios=10*log10(power./noise);
end
[reported,branch]=max(ratios,[],'omitnan');
status="measured";
if isnan(reported)
    branch=NaN;
    if flat
        status="unavailable_logarithmic_sinr_retained_signed_linear_estimate";
    else
        status="unavailable_zero_signal_and_disturbance";
    end
end
out=struct('Available',~isnan(reported),'Status',status,'CSI_SINR_dB',reported, ...
    'ZeroSignalAndDisturbancePerBranch',power==0 & noise==0, ...
    'CSI_SINRPerReceiveAntenna_dB',ratios,'ReceiveBranch1Based',branch, ...
    'DesiredPowerPerReceiveAntenna',power,'NoiseInterferencePowerPerReceiveAntenna',noise, ...
    'ChannelEstimatorDisturbancePerReceiveAntenna',estimatorNoise, ...
    'DisturbanceSource',disturbanceSource, ...
    'ChannelEstimatorDisturbanceSource',estimatorDisturbanceSource, ...
    'InterferenceMeasurement',im, ...
    'SignalPowerEstimation',powerEvidence, ...
    'ReferencePort',3000,'ReferenceRECount',numel(port0), ...
    'CDMLengths',cdm,'AntennaAggregation',"maximum_individual_receive_branch", ...
    'MeasurementDomain',"csi_rs_port3000_reference_re_received_plane", ...
    'Source',source);
end
