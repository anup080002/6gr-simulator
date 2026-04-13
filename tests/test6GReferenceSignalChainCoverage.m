function test6GReferenceSignalChainCoverage()
%TEST6GREFERENCESIGNALCHAINCOVERAGE Verify the shipped reference-signal pack exposes DMRS/PTRS/SRS/TRS and the exact chains bind them.

repoRoot = fileparts(fileparts(mfilename("fullpath")));
packPath = fullfile(repoRoot, "simulator", "configs", "reference_signals", "csi_tracking_baseline.yaml");
pack = sixgr.lls6g.config.readConfigFile(packPath);

assert(isfield(pack, "reference_signals"), ...
    "sixgr:test:6GReferenceSignals:MissingPackSection", ...
    "Reference-signal pack must contain a reference_signals section.");

rs = pack.reference_signals;
requiredObjects = ["pdsch_dmrs","pdcch_dmrs","pbch_dmrs","pusch_dmrs","ptrs","srs","trs","tracking_rs"];
for i = 1:numel(requiredObjects)
    name = requiredObjects(i);
    assert(isfield(rs, name), ...
        "sixgr:test:6GReferenceSignals:MissingRSObject", ...
        "Reference-signal pack must expose reference_signals.%s explicitly.", name);
    obj = rs.(name);
    assert(isfield(obj, "enabled") && islogical(obj.enabled) && isscalar(obj.enabled), ...
        "sixgr:test:6GReferenceSignals:MissingEnabled", ...
        "reference_signals.%s must define an explicit enabled flag.", name);
    assert(isfield(obj, "purpose") && strlength(string(obj.purpose)) > 0, ...
        "sixgr:test:6GReferenceSignals:MissingPurpose", ...
        "reference_signals.%s must define a purpose.", name);
end

scenarioPath = fullfile(repoRoot, "simulator", "configs", "scenarios", "dl_4ghz_baseline.yaml");
s = sixgr.lls6g.config.loadScenarioConfig(scenarioPath).toStruct();
pc = s.processing_chains;

localAssertChainHasPath(pc.dl_common_signal_initial_access_tx, "reference_signals.pbch_dmrs");
localAssertChainHasPath(pc.dl_common_signal_initial_access_rx, "reference_signals.pbch_dmrs");
localAssertChainHasPath(pc.pdcch_tx, "reference_signals.pdcch_dmrs");
localAssertChainHasPath(pc.pdcch_rx, "reference_signals.pdcch_dmrs");
localAssertChainHasPath(pc.pdsch_tx, "reference_signals.pdsch_dmrs");
localAssertChainHasPath(pc.pdsch_tx, "reference_signals.ptrs");
localAssertChainHasPath(pc.pdsch_rx, "reference_signals.pdsch_dmrs");
localAssertChainHasPath(pc.pdsch_rx, "reference_signals.ptrs");
localAssertChainHasPath(pc.pusch_tx, "reference_signals.pusch_dmrs");
localAssertChainHasPath(pc.pusch_tx, "reference_signals.ptrs");
localAssertChainHasPath(pc.pusch_rx, "reference_signals.pusch_dmrs");
localAssertChainHasPath(pc.reference_signal_chains, "reference_signals.srs");
localAssertChainHasPath(pc.reference_signal_chains, "reference_signals.trs");
localAssertChainHasPath(pc.reference_signal_chains, "reference_signals.tracking_rs");
localAssertChainHasPath(pc.reference_signal_chains, "reference_signals.ptrs");
end

function localAssertChainHasPath(chainStruct, requiredPath)
blocks = chainStruct.ordered_blocks;
hasPath = false;
for i = 1:numel(blocks)
    cfgPaths = string(blocks(i).config_paths);
    if any(strcmp(cfgPaths, requiredPath))
        hasPath = true;
        break;
    end
end
assert(hasPath, ...
    "sixgr:test:6GReferenceSignals:MissingChainBinding", ...
    "Processing chain '%s' must bind %s in one of its blocks.", string(chainStruct.chain_label), requiredPath);
end
