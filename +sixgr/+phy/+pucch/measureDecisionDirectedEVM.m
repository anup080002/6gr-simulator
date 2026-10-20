function evidence=measureDecisionDirectedEVM(symbols,applicable,modulation)
% Diagnostic on actual nrPUCCHDecode constellation output, not RF conformance.
% Never consumes transmitted bits, injected noise, gain/phase fitting or CRC.
arguments
    symbols {mustBeNumeric}
    applicable (1,1) logical
    modulation (1,1) string {mustBeMember(modulation,["QPSK","pi/2-BPSK"])}
end
evidence=struct('EVMPercent',NaN,'EVMApplicable',applicable, ...
    'EVM_rms',NaN,'EVMReferenceSource',"not_applicable_sequence_detection", ...
    'EVMValueStatus',"NOT_APPLICABLE_SEQUENCE_DETECTION", ...
    'EVMReferenceModulation',modulation,'EVMSymbolCount',0, ...
    'EVMErrorEnergy',NaN,'EVMReferenceEnergy',NaN);
if ~applicable, return; end
evidence.EVMReferenceSource="nearest_"+modulation+"_receiver_symbols_no_transmitted_payload_reference";
evidence.EVMValueStatus="UNAVAILABLE_NO_RECEIVER_CONSTELLATION";
if isempty(symbols), return; end
validateattributes(symbols,{'single','double'},{'finite','vector'});
actual=symbols(:);
decisions=nrSymbolDemodulate(actual,modulation,'DecisionType','hard');
reference=nrSymbolModulate(decisions,modulation);
evidence.EVMErrorEnergy=sum(abs(double(actual)-double(reference)).^2);
evidence.EVMReferenceEnergy=sum(abs(double(reference)).^2);
evidence.EVM_rms=sqrt(evidence.EVMErrorEnergy/evidence.EVMReferenceEnergy);
evidence.EVMPercent=100*evidence.EVM_rms;
evidence.EVMSymbolCount=numel(actual);
evidence.EVMValueStatus="MEASURED_DECISION_DIRECTED";
end
