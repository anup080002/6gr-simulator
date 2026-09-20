function ok = testLLSCausalWiringYAMLAuthority()
%TESTLLSCAUSALWIRINGYAMLAUTHORITY Guard the self-contained causal PHY gate.

setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioPath = fullfile(root, "simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");

raw = sixgr.lls6g.config.readConfigFile(scenarioPath);
assert(~isfield(raw, "inherits"), ...
    "The causal gate must be self-contained; inherited defaults hide authority defects.");
assert(isfield(raw, "config_inheritance") && ...
    isempty(sixgr.util.structGet(raw, "config_inheritance.parents", [])), ...
    "The causal gate must declare an empty parent set.");
leafPaths = localLeafPaths(raw, "");
assert(numel(leafPaths) >= 500, ...
    "The causal gate lost its explicit parameter surface (%d leaves).", numel(leafPaths));

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tempdir, ...
    "sixgr_causal_wiring_yaml_authority"));
sixgr.config.assertRuntimeFeatureAuthority(cfg);

% A self-contained scenario must not depend on the standalone receiver's
% fallback catalog at shared-stream execution. Preserve the authored values.
detectorCatalog=sixgr.lls6g.config.readConfigFile(fullfile(root,'simulator', ...
    'configs','control','pucch_receiver_thresholds.yaml'));
for detectorField=string(fieldnames(detectorCatalog.pucch)).'
    assert(isfield(raw.pucch,detectorField), ...
        'Self-contained FDD YAML is missing pucch.%s.',detectorField);
    assert(isequal(raw.pucch.(detectorField),detectorCatalog.pucch.(detectorField)) && ...
        isequal(cfg.phy.pucch.receiverDetectionThresholds.(detectorField),raw.pucch.(detectorField)), ...
        'FDD detector policy must retain the unchanged explicit catalog value for %s.',detectorField);
end
bad=scfg.toStruct();
bad.pucch=rmfield(bad.pucch,'detection_threshold_format2');
rejected=false;
try
    sixgr.lls6g.buildInternalConfig(bad,tempname);
catch cause
    if ~strcmp(cause.identifier,'sixgr:lls6g:config:InvalidPUCCHDetectionThreshold'), rethrow(cause); end
    rejected=true;
end
assert(rejected,'A partially installed PUCCH detector policy must fail, not fill a default.');

assert(double(sixgr.util.structGet(cfg, "run.totalSlots", NaN)) == 12);
strictEvidence = sixgr.util.structGet(cfg, ...
    "validation.strict_component_evidence", struct());
assert(logical(sixgr.util.structGet(strictEvidence, "enabled", false)));
assert(string(sixgr.util.structGet(strictEvidence, "execution_scope", "")) == "in_path");
assert(all(ismember(["prach","pdcch","srs","trs","sib1","channel_rf"], ...
    string(sixgr.util.structGet(strictEvidence, "required_components", strings(0,1))))));
assert(logical(sixgr.util.structGet(cfg, "run.strictMode", false)));
assert(~logical(sixgr.util.structGet(cfg, "phy.rx.useIdealTimingSync", true)));
assert(string(sixgr.util.structGet(cfg, "channel.model", "")) == "CDL");
assert(string(sixgr.util.structGet(cfg, "channel.cdlProfile", "")) == "CDL-A");
% This causal scenario intentionally exercises the absolute receive-power
% plane.  The self-contained YAML explicitly enables pathloss, and the
% resolved runtime must preserve that authority so SS/CSI RSRP and UL power
% control are derived from the same physical link budget.
assert(logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false)));

assert(isequal(double(sixgr.util.structGet(cfg, "phy.bsArray", [])), [1 2 1 1 1]));
assert(isequal(double(sixgr.util.structGet(cfg, "phy.ueArray", [])), [1 2 1 1 1]));
assert(double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", NaN)) == 2);
assert(double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", NaN)) == 2);
assert(double(sixgr.util.structGet(cfg, ...
    "initial_access.type0.monitoring_occasion_ordinal", NaN)) == 1);
% pdcch-ConfigSIB1=2 encodes CORESET0 index 0 and SearchSpace0 index 2.
% For this 5 MHz/15 kHz profile that moves the first Type-0 monitoring
% occasion out of the slot-0/1 four-beam SS/PBCH burst.  Guard the actual
% decoded-MIB authority rather than the obsolete colliding value 0.
assert(double(sixgr.util.structGet(cfg, "phy.mib.pdcchConfigSIB1", NaN)) == 2);
assert(double(sixgr.util.structGet(cfg, "phy.mib.dmrsTypeAPosition", NaN)) == 2);

timing = sixgr.util.structGet(cfg, "phy.schedulingTiming", struct());
assert(double(timing.pdcchToPDSCHK0) == 0);
assert(double(timing.pdcchToPUSCHK2) == 1);
assert(double(timing.ulGrantK2) == 1);
assert(double(timing.dlHARQFeedbackK1) == 4);
assert(isequal(double(timing.dlHARQFeedbackK1Candidates(:).'), 1:8));
assert(~isfield(cfg.phy, "tddTiming"), ...
    "An FDD runtime configuration must not expose a TDD timing authority.");
assert(double(sixgr.util.structGet(cfg, "mac.harq.numProcesses", NaN)) == 8);
assert(double(sixgr.util.structGet(cfg, "mac.harq.maxRetx", NaN)) == 3);
assert(double(sixgr.util.structGet(cfg, "mac.harq.k1", NaN)) == 4);
assert(double(sixgr.util.structGet(cfg, "mac.harq.k2", NaN)) == 1);
rvSequence = double(sixgr.util.structGet(cfg, "phy.harq.rvSequence", []));
assert(isequal(rvSequence(:).', [0 2 3 1]));

causalAudit = sixgr.util.structGet(cfg, ...
    "validation.causal_phy_chain_audit", struct());
assert(logical(sixgr.util.structGet(causalAudit, "enabled", false)));
assert(logical(sixgr.util.structGet(causalAudit, "required", false)));
stages = localStructList(sixgr.util.structGet(causalAudit, "stages", []));
bindings = localStructList(sixgr.util.structGet(causalAudit, ...
    "parameter_bindings", []));
assert(numel(stages) == 28, ...
    "The causal registry must cover all 28 access-to-data and export stages.");
assert(numel(bindings) >= 35, ...
    "The causal registry lost detailed YAML-to-runtime parameter bindings.");
stageIds = string(arrayfun(@(x) string(x.stage_id), stages));
assert(numel(unique(stageIds)) == numel(stageIds));
assert(all(ismember(["ssb_beam_sweep","msg1_prach_tx_rx", ...
    "connected_pdcch_grant_binding","pdsch_tx_rx","pusch_tx_rx", ...
    "harq_state_and_soft_combining","cqi_inner_loop_link_adaptation", ...
    "olla_outer_loop","antenna_pattern_channel_application", ...
    "final_tx_iq_export"], stageIds)));
antennaStage = stages(stageIds == "antenna_pattern_channel_application");
assert(numel(antennaStage) == 1 && ...
    strcmpi(string(antennaStage.success_field), "AntennaChannelConsistencyOk") && ...
    any(strcmpi(string(antennaStage.measured_fields), "ElementPatternChannelApplicability")), ...
    "The antenna/channel stage must use explicit applicability and consistency evidence rather than requiring shared runtime-array assumptions for AWGN.");
parameterIds = string(arrayfun(@(x) string(x.parameter_id), bindings));
assert(all(ismember(["k0_pdcch_to_pdsch","k1_dl_harq_candidates", ...
    "k2_pdcch_to_pusch","harq_rv_sequence", ...
    "prach_configuration_index","dl_layers","ul_layers", ...
    "olla_step_down","olla_step_up","bs_element_model", ...
    "ue_element_model","raw_iq_capture_enabled", ...
    "save_raw_waveforms"], parameterIds)));
preflightAudit = sixgr.truth.exportCausalPHYChainAudit( ...
    fullfile(tempdir, "sixgr_causal_wiring_yaml_authority"), ...
    scfg, cfg, "RunId", "authority_preflight", "WriteArtifacts", false);
assert(all(preflightAudit.DetailTable.ConfigMappingMatch), ...
    "One or more stage enable flags did not map exactly into runtime authority.");
assert(all(preflightAudit.ParameterBindingTable.ConfiguredPresent & ...
    preflightAudit.ParameterBindingTable.ResolvedPresent & ...
    preflightAudit.ParameterBindingTable.ValueMatch), ...
    "One or more configured PHY parameters did not map exactly into runtime config.");

featureNames = ["ssb","pbch","pdcch","pucch","prach","sib1", ...
    "ptrs","csi_rs","srs","trs","tracking_rs","csi_reporting", ...
    "cqi_reporting","pmi_reporting","ri_reporting","cri_reporting", ...
    "harq","beam_sweep","link_adaptation_inner_loop", ...
    "link_adaptation_outer_loop"];
for featureName = featureNames
    assert(logical(sixgr.util.structGet(cfg, ...
        "runtime.features." + featureName + ".Enabled", false)), ...
        "Required YAML feature %s did not reach runtime authority.", featureName);
end

ssbWeights = sixgr.util.structGet(cfg, "phy.ssb.precoderMatrices", []);
assert(isequal(size(ssbWeights), [4 2]), ...
    "Four SSB beams must be materialized on the two-element array.");
assert(string(sixgr.util.structGet(cfg, "phy.ssb.waveformDomain", "")) == ...
    "physical_element_domain", ...
    "The SSB waveform must be emitted in the configured physical-element domain.");
assert(max(abs(sum(abs(ssbWeights).^2, 2) - 1)) < 1e-12, ...
    "Every SSB steering vector must have unit power.");
beamSimilarity = abs(ssbWeights * ssbWeights');
beamSimilarity(1:5:end) = 0;
assert(max(beamSimilarity, [], "all") < 1 - 1e-12, ...
    "The configured SSB sweep contains duplicate steering vectors.");

ra = sixgr.mac.ra.RAConfig(cfg);
assert(double(ra.PRACHConfigurationIndex) == 95);
assert(string(ra.PRACHFormat) == "A1");
assert(double(ra.PRACHOccasionFrame) == 0);
assert(double(ra.PRACHOccasionSlot) == 1);
assert(double(ra.PRACHOccasionSymbol) == 0);
assert(double(ra.PRACHFrequencyIndex) == 0);
assert(double(ra.RARNTI) == 15);
slots=double([ra.Msg2Slot ra.Msg3Slot ra.Msg4Slot ra.SetupCompleteSlot]);
fprintf('FDD_RA_AUTHORITY slots=[%g %g %g %g] allocation_plan_only=1\n',slots);
% The authored Type-0 occasion reserves slot 2 for SIB1; TRS reserves slots
% 7/8. Match the existing duplex-allocation regression, retaining an exact
% calendar assertion and independently checking why the old slots are illegal.
assert(isequal(slots,[3 6 9 10]), ...
    'FDD RA must avoid SIB1 slot 2 and TRS slots 7/8; got [%g %g %g %g].',slots);
ownership=sixgr.phy.frame.CommonDLResourcePlan(cfg);
[available,evidence]=ownership.checkPDSCH(ra.Msg2PDSCH,2);
assert(~available && any(evidence.ConflictingOwners=="SIB1_PDSCH_and_Type0_PDCCH"));
for reservedSlot=[7 8]
    [available,evidence]=ownership.checkPDSCH(ra.Msg4PDSCH,reservedSlot);
    assert(~available && any(evidence.ConflictingOwners=="TRS"));
end
assert(ownership.checkPDSCH(ra.Msg2PDSCH,ra.Msg2Slot));
assert(ownership.checkPDSCH(ra.Msg4PDSCH,ra.Msg4Slot));
assert(ra.TimingSchedule.Msg3K2Slots == 1 && ra.TimingSchedule.Msg3AdditionalDelaySlots == 2);

assert(logical(sixgr.util.structGet(cfg, "outputs.rawIQCaptureEnabled", false)));
assert(logical(sixgr.util.structGet(cfg, "outputs.rawGridCaptureEnabled", false)));
assert(logical(sixgr.util.structGet(cfg, "outputs.saveRawWaveforms", false)));
assert(logical(sixgr.util.structGet(cfg, "outputs.saveChannelSnapshots", false)));
assert(logical(sixgr.util.structGet(cfg, "outputs.saveConstellations", false)));

assert(string(sixgr.util.structGet(cfg, "antenna.bs.element.model", "")) == ...
    "3gpp_tr38901");
assert(string(sixgr.util.structGet(cfg, "antenna.ue.element.model", "")) == ...
    "3gpp_tr38901");
assert(isequal(double(sixgr.util.structGet(cfg, ...
    "antenna.bs.element.beamwidthDeg", [])), [65 65]));
assert(isequal(double(sixgr.util.structGet(cfg, ...
    "antenna.ue.element.sidelobeLevelDb", [])), [30 30]));
assert(double(sixgr.util.structGet(cfg, ...
    "antenna.bs.element.maximumAttenuationDb", NaN)) == 30);
assert(double(sixgr.util.structGet(cfg, ...
    "antenna.bs.element.maximumGainDbi", NaN)) == 8);
assert(isequal(double(sixgr.util.structGet(cfg, ...
    "antenna.bs.boresightAzElSlant_deg", [])), [0 0 0]));
assert(logical(sixgr.util.structGet(cfg, ...
    "antenna.bs.requireElementPatternInChannel", false)));
assert(string(sixgr.util.structGet(cfg, ...
    "lls6g.users.beam_selection_strategy", "")) == "runtime_best_beam_per_link");
bsAntenna = sixgr.rf.AntennaArrayFactory.build(cfg, "bs");
ueAntenna = sixgr.rf.AntennaArrayFactory.build(cfg, "ue");
assert(bsAntenna.HasPhased && ueAntenna.HasPhased);
assert(isa(bsAntenna.ElementObj, "phased.NRAntennaElement") && ...
    isa(ueAntenna.ElementObj, "phased.NRAntennaElement"));
assert(isa(bsAntenna.ArrayObj, "phased.NRRectangularPanelArray") && ...
    isa(ueAntenna.ArrayObj, "phased.NRRectangularPanelArray"));

fprintf(['Causal YAML authority: %d explicit leaves, K0=%d, K1=%d, K2=%d, ' ...
    '%d HARQ processes, %d unique normalized SSB beams.\n'], ...
    numel(leafPaths), timing.pdcchToPDSCHK0, timing.dlHARQFeedbackK1, ...
    timing.pdcchToPUSCHK2, cfg.mac.harq.numProcesses, size(ssbWeights, 1));
ok = true;
end

function values = localStructList(raw)
if isstruct(raw)
    values = raw(:);
    return;
end
assert(iscell(raw) && all(cellfun(@(x) isstruct(x) && isscalar(x), raw(:))));
fields = strings(0,1);
for index = 1:numel(raw)
    fields = union(fields, string(fieldnames(raw{index})), "stable");
end
for index = 1:numel(raw)
    for fieldName = fields(:).'
        if ~isfield(raw{index}, char(fieldName))
            raw{index}.(char(fieldName)) = [];
        end
    end
    raw{index} = orderfields(raw{index}, cellstr(fields));
end
values = vertcat(raw{:});
end

function paths = localLeafPaths(value, prefix)
paths = strings(0, 1);
if isstruct(value)
    names = fieldnames(value);
    for index = 1:numel(names)
        name = string(names{index});
        childPrefix = name;
        if strlength(prefix) > 0
            childPrefix = prefix + "." + name;
        end
        child = value.(names{index});
        if isstruct(child) && ~isscalar(child)
            for ordinal = 1:numel(child)
                paths = [paths; localLeafPaths(child(ordinal), ...
                    childPrefix + "[" + ordinal + "]")]; %#ok<AGROW>
            end
        else
            paths = [paths; localLeafPaths(child, childPrefix)]; %#ok<AGROW>
        end
    end
elseif iscell(value)
    for ordinal = 1:numel(value)
        paths = [paths; localLeafPaths(value{ordinal}, ...
            prefix + "[" + ordinal + "]")]; %#ok<AGROW>
    end
else
    paths(end+1, 1) = prefix;
end
end
