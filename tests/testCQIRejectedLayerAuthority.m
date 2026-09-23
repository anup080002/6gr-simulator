function ok = testCQIRejectedLayerAuthority()
% Rejected wideband evidence must not re-enter CQI through its layer vector.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg = sixgr.config.defaultConfig();
base = struct('WidebandSINR_dB',20,'RankIndicator',2, ...
    'PostEqSINRPerLayer_dB',[20 20], ...
    'SINRSource',"receiver_post_equalization_sinr", ...
    'SINRValueRole',"measured_post_equalization_scheduling_input", ...
    'SINRValueStatus',"OK");
for direction = ["DL" "UL"]
    valid = sixgr.link.resolveWidebandCQI(base,cfg,direction);
    assert(valid.SINRInputAccepted && isfinite(valid.WidebandCQI));
    assert(isscalar(valid.PerCodewordCQI) && isfinite(valid.PerCodewordCQI));
    for reason = ["configured" "proxy" "failed" "cross_direction"]
        input = base;
        switch reason
            case "configured", input.SINRSource="configured_operating_point_metadata";
            case "proxy", input.SINRValueRole="evm_proxy";
            case "failed", input.SINRValueStatus="FAILED";
            case "cross_direction", input.SINRSource="measured_srs_reciprocity";
        end
        rejected = sixgr.link.resolveWidebandCQI(input,cfg,direction);
        assert(~rejected.SINRInputAccepted && isnan(rejected.WidebandCQI), ...
            'test:CQIRejectedLayerRescue', ...
            '%s %s rejected evidence re-entered CQI through per-layer values.',direction,reason);
        assert(isempty(rejected.PerCodewordCQI) && isempty(rejected.PerCodewordSINR_dB), ...
            'Rejected evidence must not publish codeword scheduling quality.');
    end
end
ok=true;
fprintf('CQI_REJECTED_LAYER_AUTHORITY_PASS directions=2 rejection_cases=8\n');
end
