function prepared=prepareSharedPDCCHTransmission(cfg,varargin)
% Materialize a control contribution, not a separate physical transmission.
% Keep logical IQ/grid for decoder reference and physical pre-RF IQ for the
% node compositor. RF/PA/channel/noise must be executed only by that owner.
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSignalFamily',"PDCCH");
cfg=sixgr.util.structSet(cfg,'phy.runtimeSignalFamily',"PDCCH");
prepared=sixgr.link.preparePDCCHTransmission(cfg,varargin{:});
validateattributes(prepared.RuntimeStartSample,{'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'});
[ports,power]=sixgr.rf.applyPowerContext(prepared.TransmitSamples,cfg,"DL", ...
    prepared.TxInfo,'ApplyPA',false);
array=sixgr.rf.AntennaArrayFactory.build(cfg,'bs','signal','PDCCH', ...
    'numPorts',size(ports,2));
matrix=array.PortToElementMatrix;
assert(isequal(size(matrix),[array.NumElements size(ports,2)]) && ...
    all(isfinite(matrix),'all') && ...
    norm(matrix'*matrix-eye(size(ports,2)),'fro')<1e-9, ...
    'sixgr:link:PDCCHPhysicalProjection', ...
    'The resolved PDCCH port map must preserve power and match the physical array.');
assert(~power.PAApplied && (~power.PAEnabled || power.PAExecutionDeferred), ...
    'sixgr:link:PDCCHPreparationAppliedRF','Apply node PA only after composition.');
assert(string(power.WaveformAmplitudeUnit)=="sqrt_mW", ...
    'sixgr:link:PDCCHPhysicalPowerUnit','Shared node IQ requires a physical sqrt(mW) power reference.');
prepared.TransmitSamples=ports*cast(matrix.','like',ports);
prepared.PowerContext=power;
prepared.PhysicalPortMapping=matrix;
prepared.PhysicalPortMappingSHA256=string(sixgr.phy.mimo.MatrixContract.digest(matrix));
prepared.SampleDomain="physical_antenna_sqrt_mW_before_shared_tx_rf";
prepared.PowerExecutionDeferred=false;
prepared.ReceiverConfig=sixgr.util.structSet(cfg,'lls6g.runtimePowerContext',power);
end
