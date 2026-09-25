function ok=testEVMDiagnosticDynamicRange()
% Exact mathematical diagnostics, deliberately not receiver SINR authority.
for evm=[0,realmin,1e-200,1e-12,0.1,1,10,realmax]
    [primary,meta]=sixgr.link.deriveDecoderTruthProxySINR(struct('EVM_rms',evm));
    assert(isnan(primary) && meta.ValueRole=="unavailable");
    value=meta.DiagnosticEVMProxySINR_dB;
    assert(isequal(value,-20*log10(evm)));
    if evm==0
        assert(isinf(value) && value>0 && startsWith(meta.DiagnosticValueStatus,"zero_error"));
    else
        assert(isfinite(value) && meta.DiagnosticValueStatus=="diagnostic_available_primary_unavailable");
    end
end
for bad={-1,NaN,Inf,[0.1 0.2],1i,[]}
    [primary,meta]=sixgr.link.deriveDecoderTruthProxySINR(struct('EVM_rms',bad{1}));
    assert(isnan(primary) && isnan(meta.DiagnosticEVMProxySINR_dB));
end
fprintf('EVM_DIAGNOSTIC_DYNAMIC_RANGE_PASS zero_to_realmax no_epsilon_cap no_primary_SINR\n');
ok=true;
end
