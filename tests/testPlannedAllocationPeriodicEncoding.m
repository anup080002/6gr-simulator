function ok = testPlannedAllocationPeriodicEncoding()
%TESTPLANNEDALLOCATIONPERIODICENCODING Prove lossless exact RE compaction.

setup6GRSimToolkit("Verbose",false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile( ...
    "simulator","configs","scenarios", ...
    "lls_causal_tdd_connected_feedback_fixture.yaml"));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.run.totalSlots=10;
targets=["PDCCH","PDSCH","CSI_RS","TRS","PUSCH","SRS"];

expandedCfg=sixgr.util.structSet(cfg, ...
    "outputs.plannedAllocationEncoding","expanded_per_slot");
[expanded,expandedChecks]=sixgr.truth.buildPlannedREAllocation( ...
    expandedCfg,"TargetChannels",targets);
sixgr.truth.assertAllocationPreflight(expandedChecks);

compactCfg=sixgr.util.structSet(cfg, ...
    "outputs.plannedAllocationEncoding","exact_periodic_templates");
[compact,compactChecks]=sixgr.truth.buildPlannedREAllocation( ...
    compactCfg,"TargetChannels",targets);
sixgr.truth.assertAllocationPreflight(compactChecks);

enabled=expandedChecks.enabled;
assert(isequal(expandedChecks.feature(enabled),compactChecks.feature(enabled)) && ...
    isequal(expandedChecks.exact_re_count(enabled), ...
    compactChecks.exact_re_count(enabled)), ...
    "Compact planning must preserve each enabled feature's exact RE count.");
assert(height(compact)<height(expanded), ...
    "Periodic-template encoding must eliminate repeated persisted rows.");
assert(all(compact.occurrence_count>=1) && ...
    any(compact.occurrence_count>1), ...
    "Compact planning must publish explicit repeated occurrence counts.");

reexpanded=localExpand(compact);
assert(isequaln(localComparable(reexpanded),localComparable(expanded)), ...
    ["Every compact PDCCH/PDSCH/CSI-RS/TRS/PUSCH/SRS template must " ...
     "expand to the identical exact per-slot coordinate table."]);

ok=true;
fprintf("PLANNED_PERIODIC_ENCODING_PASS expanded_rows=%d compact_rows=%d exact_re=%g\n", ...
    height(expanded),height(compact),sum(expandedChecks.exact_re_count(enabled)));
end

function expanded=localExpand(compact)
parts=cell(height(compact),1);
for rowIndex=1:height(compact)
    slots=str2double(split(string(compact.occurrence_slots(rowIndex)),"|"));
    assert(all(isfinite(slots)) && ...
        numel(slots)==compact.occurrence_count(rowIndex));
    part=compact(repmat(rowIndex,numel(slots),1),:);
    part.absolute_slot=slots(:);
    part.occurrence_slots=string(slots(:));
    part.occurrence_count=ones(numel(slots),1);
    parts{rowIndex}=part;
end
expanded=vertcat(parts{:});
end

function comparable=localComparable(rows)
variables=["absolute_slot","direction","channel","component", ...
    "subcarrier_start","subcarrier_count","symbol_index","port_index", ...
    "re_count","cell_id","ue_id","layer_count","authority","resolver", ...
    "grid_domain","grid_subcarrier_spacing_hz", ...
    "grid_subcarrier_count","grid_symbol_count"];
comparable=sortrows(rows(:,variables),variables);
end
