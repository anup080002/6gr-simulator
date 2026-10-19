function ok=testMeasurementAvailabilityEvidence()
T=table(["not_recorded_by_active_test_runtime";"[0 1]"], ...
    ["available";"measured"],[NaN;0],["available";"measured"], ...
    ["explicit_matrix";"type1"], ...
    'VariableNames',{'AppliedBeamIndexSet','AppliedBeamValueStatus', ...
    'AppliedPrecoderPMI','AppliedPrecoderValueStatus','AppliedPrecoderPMIType'});
out=sixgr.truth.canonicalizeLLSLiveSignalChainTable('tx_rx_stage_trace',T);
assert(out.AppliedBeamValueStatus(1)=="unavailable");
assert(out.AppliedPrecoderValueStatus(1)=="unavailable");
assert(out.AppliedBeamValueStatus(2)=="measured" && out.AppliedPrecoderValueStatus(2)=="measured");
assert(isnan(out.AppliedPrecoderPMI(1)) && out.AppliedPrecoderPMI(2)==0);
out2=sixgr.truth.canonicalizeLLSLiveSignalChainTable('tx_rx_stage_trace',out);
assert(isequaln(out,out2),'Canonicalization must be idempotent.');
assert(~any(sixgr.truth.measurementValuePresent(["not_emitted_by_active_x";"NaN";missing])));
T.AppliedPrecoderMatrixSHA256=[string(repmat('a',1,64));""];
T.SINR_dB=[12;NaN]; T.SINRValueDefinition=["not_emitted_by_active_x";"measured_dmrs_residual"];
T.SINRValueStatus=["available";"available"];
out=sixgr.truth.canonicalizeLLSLiveSignalChainTable('tx_rx_stage_trace',T);
assert(out.AppliedPrecoderScalarPMIStatus(1)=="not_applicable_explicit_matrix");
assert(out.AppliedPrecoderMatrixStatus(1)=="available_hash_bound_matrix");
assert(out.SINRValueStatus(1)=="unavailable_definition_not_recorded" && out.SINRValueStatus(2)=="unavailable");
assert(out.SINR_dB(1)==12 && isnan(out.SINR_dB(2)));
ok=true;
end
