function ok = testLLSPublicOutputTableIntegrity()
%TESTLLSPUBLICOUTPUTTABLEINTEGRITY Guard public LLS table provenance fields.

setup6GRSimToolkit("Verbose", false);

meta = struct( ...
    "logical_run_id", "unit_public_output_integrity", ...
    "run_id", 17);
contract = sixgr.truth.llsOutputContract();

baseTables = struct();
baseTables.pdsch_table = table( ...
    [0; 1], [1e-3; NaN], [true; false], ...
    'VariableNames', {'Slot','NoiseVar','CRCPass'});
baseTables.pucch_table = table( ...
    2e-3, true, ...
    'VariableNames', {'NoiseVar','UCIContentMatch'});
baseTables.srs_table = table( ...
    3e-3, -25.0, ...
    'VariableNames', {'NoiseVar','NMSE_dB'});

publicTables = sixgr.truth.buildLLSPublicOutputTables(baseTables, contract, meta);

pdsch = publicTables.pdsch_runtime_event_table;
assert(strcmp(string(pdsch.NoiseVarStatus(1)), "OK"), ...
    "Positive noise variance must publish NoiseVarStatus=OK, not a source token.");
assert(strcmp(string(pdsch.NoiseVarSource(1)), "runtime_metadata"), ...
    "Positive noise variance must keep runtime_metadata as source provenance.");
assert(strcmp(string(pdsch.NoiseVarStatus(2)), "NOT_AVAILABLE"), ...
    "Missing noise variance must publish NoiseVarStatus=NOT_AVAILABLE.");
assert(strcmp(string(pdsch.NoiseVarSource(2)), "unavailable_missing"), ...
    "Missing noise variance must keep unavailable_missing as source provenance.");
assert(~any(logical(pdsch.DecodeAttempted)) && ~any(logical(pdsch.DecodeUsable)), ...
    "Public data runtime tables must not infer decode attempted/usable from row presence.");

pucch = publicTables.pucch_uci_table;
assert(~logical(pucch.DetectionAttempted(1)) && ~logical(pucch.ReceiverUsable(1)) && ~logical(pucch.DetectionUsable(1)), ...
    "Public PUCCH table must not infer detection attempted/usable from noise presence.");

srs = publicTables.srs_measurement_table;
assert(~logical(srs.MeasurementAttempted(1)) && ~logical(srs.MeasurementUsable(1)), ...
    "Public SRS table must not infer measurement attempted/usable from noise presence.");

noiseEvidence = publicTables.noise_variance_evidence_table;
badStatusTokens = ["RUNTIME_METADATA","UNAVAILABLE_MISSING","UNAVAILABLE_INVALID_NONPOSITIVE"];
assert(~isempty(noiseEvidence) && ~any(ismember(upper(string(noiseEvidence.NoiseVarStatus)), badStatusTokens)), ...
    "Noise evidence must keep status separate from source/reason tokens.");
assert(all(ismember(upper(string(noiseEvidence.NoiseVarStatus)), ["OK","NOT_AVAILABLE"])), ...
    "Noise evidence statuses must use the receiver status vocabulary.");
assert(all(string(noiseEvidence.RunId) == string(meta.logical_run_id)), ...
    "Noise evidence RunId must preserve the logical filesystem/WebGUI run identity.");
assert(all(double(noiseEvidence.run_id) == double(meta.run_id)), ...
    "Noise evidence run_id must preserve the numeric database identity separately.");

% Data SINR is a numeric/provenance tuple, not an arbitrary first finite
% SNR field. These are publisher fixtures, not receiver calibration evidence.
postSource="canonical_decision_directed_post_equalization_residual_bounded_equalizer_sinr";
postRole="measured_post_equalization_scheduling_input";
postStatus="OK_decision_residual_bounded";
data=table((1:8).',repmat(25.234113373871,8,1), ...
    repmat(postSource,8,1),repmat(postRole,8,1),repmat(postStatus,8,1), ...
    repmat(40,8,1),repmat(31,8,1),repmat(29,8,1), ...
    'VariableNames',{'Slot','PostEqSINR_dB','PostEqSINRSource','PostEqSINRValueRole', ...
    'PostEqSINRValueStatus','ConfiguredSNR_dB','SINR_dB','LargeScaleSINR_dB'});
data.PostEqSINRSource(2)="post_equalization_sinr_from_equalizer_channel_estimate";
data.PostEqSINRValueStatus(2)="OK";
data.PostEqSINRSource(3)="evm_proxy_not_true_post_equalization_sinr";
data.PostEqSINRValueStatus(4)="REJECTED";
data.PostEqSINRValueRole(5)="";
data.PostEqSINR_dB(6)=NaN;
data.PostEqSINRSource(7)="receiver_hest_reference_signal_measurement";
data.PostEqSINRValueRole(7)="estimated";
data.PostEqSINRSource(8)="configured_post_equalization_sweep_anchor";
baseTables.pdsch_table=data;
baseTables.pusch_table=data;
publicTables=sixgr.truth.buildLLSPublicOutputTables(baseTables,contract,meta);
for name=["pdsch_runtime_event_table","pusch_runtime_event_table"]
    T=publicTables.(name);
    assert(isequal(T.SINR_dB(1:2),data.PostEqSINR_dB(1:2)));
    assert(isequal(string(T.SINRSource(1:2)),data.PostEqSINRSource(1:2)));
    assert(all(string(T.SINRValueRole(1:2))==postRole));
    assert(isequal(string(T.SINRValueStatus(1:2)),data.PostEqSINRValueStatus(1:2)));
    assert(all(isnan(T.SINR_dB(3:8))) && all(string(T.SINRValueRole(3:8))=="unavailable") && ...
        all(string(T.SINRValueStatus(3:8))=="NOT_AVAILABLE"), ...
        'Public data tables must not substitute pilot, model, configured or proxy values.');
end
% A qualified legacy alias retains its own source/role/status. A missing
% canonical value is not permission to substitute a different SINR plane.
alias=table(23.5,postSource,postRole,postStatus, ...
    'VariableNames',{'MeasuredTrialSINR_dB','MeasuredTrialSINRSource', ...
    'MeasuredTrialSINRValueRole','MeasuredTrialSINRValueStatus'});
baseTables.pdsch_table=alias;
publicTables=sixgr.truth.buildLLSPublicOutputTables(baseTables,contract,meta);
assert(publicTables.pdsch_runtime_event_table.SINR_dB==23.5 && ...
    publicTables.pdsch_runtime_event_table.SINRSource==postSource);
disp('PUBLIC_DATA_SINR_PROVENANCE_PASS dl_ul_cases=16 qualified_alias=1');

ok = true;
end
