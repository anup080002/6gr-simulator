function out=measureCSISINRFromResourceGrid(carrier,csirs,receivedGrid)
% TS 38.215 5.1.6: port 3000, linear reference-RE power, branch diversity.
% One identified resource and one received reference plane per invocation.
% The disturbance estimate uses this resource's actual CDM reference, not
% configured SNR, channel truth, another port's power or a data equalizer.
validateattributes(receivedGrid,{'single','double'},{'nonempty','finite'});
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
for r=1:nRx
    [h,n]=nrChannelEstimate(carrier,double(receivedGrid(:,:,r)),double(reference), ...
        'CDMLengths',cdm);
    assert(isscalar(n) && isfinite(n) && n>=0, ...
        'sixgr:refsig:CSISINRDisturbanceUnavailable','Received CSI-RS disturbance must be nonnegative and measured.');
    portChannel=h(:,:,1,1);
    power(r)=mean(abs(portChannel(port0).*reference(port0)).^2);
    noise(r)=double(n);
end
assert(all(isfinite(power) & power>=0),'sixgr:refsig:CSISINRSignalUnavailable', ...
    'Every receive branch must retain a finite nonnegative port-3000 power estimate.');
ratios=10*log10(power./noise);
[reported,branch]=max(ratios,[],'omitnan');
out=struct('Available',~isnan(reported),'Status',"measured",'CSI_SINR_dB',reported, ...
    'ZeroSignalAndDisturbancePerBranch',power==0 & noise==0, ...
    'CSI_SINRPerReceiveAntenna_dB',ratios,'ReceiveBranch1Based',branch, ...
    'DesiredPowerPerReceiveAntenna',power,'NoiseInterferencePowerPerReceiveAntenna',noise, ...
    'ReferencePort',3000,'ReferenceRECount',numel(port0), ...
    'CDMLengths',cdm,'AntennaAggregation',"maximum_individual_receive_branch", ...
    'MeasurementDomain',"csi_rs_port3000_reference_re_received_plane", ...
    'Source',"nrChannelEstimate_port3000_reference_RE_power_per_receive_branch");
end
