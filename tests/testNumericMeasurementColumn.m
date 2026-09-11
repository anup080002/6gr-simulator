function ok=testNumericMeasurementColumn()
% Report decoding only; these are not PHY observations or qualification data.
read=@(raw)sixgr.truth.numericMeasurementColumn(raw,'fixture');
assert(isequaln(read({[];'';"";NaN;string(missing)}),nan(5,1)));
assert(isequaln(read({'0';'1';'0.25';'-12.3';'NaN'}),[0;1;.25;-12.3;NaN]));
assert(isequaln(read({2;false;"3.5";''}),[2;0;3.5;NaN]));
assert(isequaln(read([2 NaN 4]),[2;NaN;4]));
canonicalMissing={ ...
    'not_recorded_by_active_ul_pusch_trials_runtime'; ...
    'not_emitted_by_active_dl_pdsch_trials_runtime'; ...
    'field_not_emitted_by_active_csi_rs_trials_runtime'; ...
    'not_applicable_for_active_prach_runtime'; ...
    'not_applicable'};
assert(isequaln(read(canonicalMissing),nan(numel(canonicalMissing),1)));
for bad={{'not_measured_but_not_a_missing_numeric_cell'}, {[1 2]}, ...
        {'not_applicable_because_fixture_said_so'}, {'unavailable'}, ...
        {'1+2i'}, {struct()}, [1 2;3 4]}
    rejected=false;
    try
        read(bad{1});
    catch cause
        assert(strcmp(cause.identifier,'sixgr:truth:InvalidNumericMeasurementColumn'));
        rejected=true;
    end
    assert(rejected,'Malformed evidence was silently accepted.');
end
ok=true; disp('NUMERIC_MEASUREMENT_COLUMN_PASS');
end
