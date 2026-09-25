function assertMeasuredEVMTrialEvidence(T)
% Reconcile primary waveform trial operands, including zero-error cases.
required=["EVMErrorEnergy","EVMReferenceEnergy","EVMSymbolCount", ...
    "EVMStatus","EVMComputationDomain","EVMEnergyUnit"];
assert(all(ismember(required,string(T.Properties.VariableNames))));
measured=isfinite(T.EVM_rms);
assert(any(measured),'The physical fixture must produce measured EVM.');
Q=T(measured,:);
assert(all(Q.EVMReferenceEnergy>0 & Q.EVMErrorEnergy>=0));
assert(all(Q.EVMSymbolCount>0 & Q.EVMSymbolCount==fix(Q.EVMSymbolCount)));
assert(all(abs(Q.EVM_rms-sqrt(Q.EVMErrorEnergy./Q.EVMReferenceEnergy))<1e-10));
assert(all(Q.EVMComputationDomain== ...
    "receiver_equalized_symbols_average_reference_power_no_payload_fit"));
assert(all(Q.EVMEnergyUnit=="sum_squared_complex_symbol_amplitude_not_joules"));
assert(all(strlength(Q.EVMStatus)>0));
end
