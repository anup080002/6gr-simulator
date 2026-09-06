function verifyLLSObservedEVM(runRoot, reviewRoot)
%VERIFYLLSOBSERVEDEVM Cross-check saved-sample CSV aggregates against comm.EVM.
% Read-only verification of an observed-data review, not a new PHY execution.
arguments
    runRoot (1,1) string
    reviewRoot (1,1) string
end
files = ["pdsch_evm_per_symbol", "pusch_evm_per_symbol", ...
    "evm_per_symbol", "evm_per_subcarrier", "evm_per_layer"];
evm = comm.EVM("Normalization", "Average reference signal power", ...
    "ReferenceSignalSource", "Input port", "MaximumEVMOutputPort", true);
cached = containers.Map("KeyType", "char", "ValueType", "any");
total = 0;
for name = files
    reportPath = fullfile(reviewRoot, name + ".csv");
    if ~isfile(reportPath)
        continue;
    end
    report = readtable(reportPath, "TextType", "string", "VariableNamingRule", "preserve");
    for ri = 1:height(report)
        row = report(ri,:);
        source = char(row.source_table_logical_path);
        if ~isKey(cached, source)
            cached(source) = readtable(fullfile(runRoot, source), ...
                "TextType", "string", "VariableNamingRule", "preserve");
        end
        samples = cached(source);
        keep = true(height(samples),1);
        keys = {"ue_index", ["UEIndex", "UEID", "ue_id"]; ...
            "frame", "Frame"; "sfn", "SFN"; "slot", ["RuntimeSlot", "Slot"]; ...
            "tb_id", ["TBId", "tb_id"]; "layer_index", "LayerIndex"; ...
            "codeword_index", "CodewordIndex"; ...
            "cell_id", ["CellID", "ServingCell", "BaseStationID"]};
        for ki = 1:size(keys,1)
            expected = string(row.(keys{ki,1}));
            if ismissing(expected) || strlength(expected)==0 || expected=="NaN"
                continue;
            end
            candidates = keys{ki,2};
            matched = candidates(ismember(candidates,string(samples.Properties.VariableNames)));
            assert(~isempty(matched), "Missing source identity field for %s", keys{ki,1});
            keep = keep & string(samples.(matched(1))) == expected;
        end
        axes = ["OFDMSymbolIndex", "SubcarrierIndex", "LayerIndex"];
        axis = axes(ismember(axes,string(report.Properties.VariableNames)));
        assert(isscalar(axis), "Expected one declared EVM aggregation axis.");
        keep = keep & double(samples.(axis)) == double(row.(axis));
        selected = samples(keep,:);
        assert(height(selected)==double(row.sample_count), "Sample count mismatch for %s row %d", name, ri);
        reference = complex(double(selected.ReferenceSymbolReal), double(selected.ReferenceSymbolImag));
        equalized = complex(double(selected.EqualizedReal), double(selected.EqualizedImag));
        [rmsPct, peakPct] = evm(reference, equalized);
        assert(abs(rmsPct-double(row.rms_evm_pct)) < 1e-9*max(1,abs(rmsPct)), ...
            "RMS mismatch against comm.EVM for %s row %d", name, ri);
        assert(abs(peakPct-double(row.peak_evm_pct)) < 1e-9*max(1,abs(peakPct)), ...
            "Peak mismatch against comm.EVM for %s row %d", name, ri);
        total = total+1;
    end
    fprintf("PASS %s: %d captured-sample buckets\n", name, height(report));
end
assert(total>0, "No EVM measurement buckets were checked.");
fprintf("LLS_OBSERVED_EVM_TOOLBOX_MATCH_PASS buckets=%d\n", total);
end
