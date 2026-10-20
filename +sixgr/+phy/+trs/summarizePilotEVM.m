function out=summarizePilotEVM(pairs)
% Direct complex paired-RE arithmetic, not a conversion of an SINR/NMSE.
% Same-execution desired pilots include propagation; no receiver equalizer
% or gain/phase fit uses this post-reception scoring reference.
out=struct('EVM_rms',NaN,'EVMErrorEnergy',NaN,'EVMReferenceEnergy',NaN, ...
    'EVMSymbolCount',0,'EVMEnergyUnit',"sum_squared_complex_symbol_amplitude_not_joules", ...
    'EVMReferenceSource',"unavailable",'EVMReferencePlane',"unavailable",'EVMValueStatus',"NOT_AVAILABLE", ...
    'EVMComputationDomain',"received_resource_elements",'ControlEVMSamplesJSON',"");
if nargin==0 || isempty(pairs), return; end
errorEnergy=0; referenceEnergy=0; count=0;
for p=reshape(pairs,1,[])
    assert(p.SignalName=="TRS" && ~p.ReceiverUsesScoringReference && ~p.GainOrPhaseFitted && ...
        p.MeasurementDomain=="received_resource_elements" && ...
        p.ReferenceSource=="same_executed_desired_link_received_pilot_grid", ...
        'sixgr:phy:trs:InvalidEVMAuthority','Retain same-execution independent received-pilot pairs.');
    ref=complex(p.ReferenceReal,p.ReferenceImag); measured=complex(p.MeasuredReal,p.MeasuredImag);
    assert(isequal(size(ref),size(measured)) && numel(ref)==numel(p.SampleIndex) && ...
        ~isempty(ref) && all(isfinite(ref),'all') && all(isfinite(measured),'all'), ...
        'sixgr:phy:trs:InvalidEVMPairs','No missing, truncated or synthesized TRS pairs.');
    errorEnergy=errorEnergy+sum(abs(measured-ref).^2,'all');
    referenceEnergy=referenceEnergy+sum(abs(ref).^2,'all'); count=count+numel(ref);
end
assert(referenceEnergy>0,'sixgr:phy:trs:ZeroEVMReference','A nonzero measured reference is required.');
planes=unique(string({pairs.ReferencePlane}));
assert(numel(planes)==1 && strlength(planes)>0, ...
    'sixgr:phy:trs:MixedEVMPlanes','Do not pool different independent reference planes.');
out.EVMReferencePlane=planes;
out.EVM_rms=sqrt(errorEnergy/referenceEnergy);
out.EVMErrorEnergy=errorEnergy; out.EVMReferenceEnergy=referenceEnergy; out.EVMSymbolCount=count;
out.EVMReferenceSource="same_executed_desired_link_received_pilot_grid";
out.EVMValueStatus="MEASURED_PAIRED_RECEIVED_PILOT_GRID_NOT_RF_CONFORMANCE";
out.ControlEVMSamplesJSON=string(jsonencode(pairs));
end
