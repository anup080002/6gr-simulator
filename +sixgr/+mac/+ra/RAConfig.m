function ra = RAConfig(cfg, varargin)
%RACONFIG Resolve strict four-step RA configuration from explicit inputs.
%
% Strict runs must provide the random_access subtree. The only accepted
% non-SIB1 source for the AUD-RA-001 anchor is an explicit scenario config
% tagged as scenario_config_pending_sib1.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end

p = inputParser;
p.addParameter("RunId", "ra_anchor", @(x)ischar(x) || isstring(x));
p.addParameter("ScenarioName", "", @(x)ischar(x) || isstring(x));
p.addParameter("UEId", 1, @(x)isnumeric(x) && isscalar(x));
p.addParameter("CellId", [], @(x)isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("AttemptId", 1, @(x)isnumeric(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

strict = logical(sixgr.util.structGet(cfg, "run.strictMode", false));
raNode = sixgr.util.structGet(cfg, "random_access", struct());
if ~(isstruct(raNode) && ~isempty(fieldnames(raNode)))
    error("sixgr:mac:ra:MissingRandomAccessConfig", ...
        "Strict four-step RA requires an explicit random_access config subtree.");
end
if strict && ~logical(sixgr.util.structGet(raNode, "enabled", false))
    error("sixgr:mac:ra:DisabledStrictRA", ...
        "Strict four-step RA was requested but random_access.enabled is false.");
end

mandatory = [ ...
    "prach_format"
    "configuration_index"
    "subcarrier_spacing_khz"
    "root_sequence_index"
    "zero_correlation_zone"
    "restricted_set"
    "frequency_start"
    "preamble_index"
    "occasion.frame"
    "occasion.slot"
    "occasion.symbol"
    "occasion.frequency_index"
    "ra_response_window_slots"
    "ra_contention_resolution_timer_slots"
    "preamble_trans_max"
    "power_ramping_step_db"
    "preamble_received_target_power_dbm"
    "temp_crnti"
    "final_crnti"
    "timing.rar_processing_delay_slots"
    "timing.msg3_k2_slots"
    "timing.msg4_processing_delay_slots"
    "timing.setup_complete_k2_slots"
    "msg2_pdsch.prb_start"
    "msg2_pdsch.num_prb"
    "msg2_pdsch.symbol_start"
    "msg2_pdsch.num_symbols"
    "msg2_pdsch.modulation"
    "msg2_pdsch.target_code_rate"
    "msg3_pusch.prb_start"
    "msg3_pusch.num_prb"
    "msg3_pusch.symbol_start"
    "msg3_pusch.num_symbols"
    "msg3_pusch.mcs"
    "msg3_pusch.modulation"
    "msg3_pusch.target_code_rate"
    "msg4_pdsch.prb_start"
    "msg4_pdsch.num_prb"
    "msg4_pdsch.symbol_start"
    "msg4_pdsch.num_symbols"
    "msg4_pdsch.modulation"
    "msg4_pdsch.target_code_rate"];
missing = strings(0, 1);
for ii = 1:numel(mandatory)
    if isempty(sixgr.util.structGet(raNode, mandatory(ii), []))
        missing(end + 1, 1) = mandatory(ii); %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("sixgr:mac:ra:MissingMandatoryRACHFields", ...
        "Strict four-step RA config missing mandatory fields: %s", strjoin(missing, ", "));
end

restrictedSet = string(sixgr.util.structGet(raNode, "restricted_set", ""));
allowedRestrictedSets = [ ...
    "UnrestrictedSet", "RestrictedSetTypeA", "RestrictedSetTypeB"];
match = find(strcmpi(restrictedSet, allowedRestrictedSets), 1);
if isempty(match)
    error("sixgr:mac:ra:InvalidRestrictedSet", ...
        "random_access.restricted_set must be one of: %s.", ...
        strjoin(allowedRestrictedSets, ", "));
end
restrictedSet = allowedRestrictedSets(match);

cellId = opt.CellId;
if isempty(cellId)
    cellId = sixgr.util.structGet(cfg, "phy.carrier.NCellID", ...
        sixgr.util.structGet(cfg, "scenario.NCellID", 1));
end

scenarioName = string(opt.ScenarioName);
if strlength(strtrim(scenarioName)) == 0
    scenarioName = string(sixgr.util.structGet(cfg, "scenario.name", ...
        sixgr.util.structGet(cfg, "scenario_id", "lls_ra_four_step_strict_mini_anchor")));
end

bindingSource = string(sixgr.util.structGet(raNode, "binding_source", "scenario_config_pending_sib1"));
if strlength(strtrim(bindingSource)) == 0
    bindingSource = "scenario_config_pending_sib1";
end
if strict && ~(bindingSource == "decoded_sib1_rach_config_common" || bindingSource == "scenario_config_pending_sib1")
    error("sixgr:mac:ra:InvalidBindingSource", ...
        "RABindingSource must be decoded_sib1_rach_config_common or scenario_config_pending_sib1.");
end

ra = struct();
ra.RunId = string(opt.RunId);
ra.ScenarioName = scenarioName;
ra.CellId = double(cellId);
ra.UEId = double(opt.UEId);
ra.AttemptId = double(opt.AttemptId);
ra.RAProcedureType = "contention_based_four_step";
ra.BindingSource = bindingSource;
ra.StrictMode = logical(strict);
ra.NCellID = double(cellId);
ra.NSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", ...
    sixgr.util.structGet(cfg, "carrier.n_size_grid", 52)));
ra.CarrierSCSkHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "carrier.subcarrier_spacing_khz", 30)));
ra.PreambleIndex = double(sixgr.util.structGet(raNode, "preamble_index", 0));
ra.PRACHFormat = string(sixgr.util.structGet(raNode, "prach_format", "0"));
ra.PRACHConfigurationIndex = double(sixgr.util.structGet(raNode, "configuration_index", 16));
ra.PRACHSubcarrierSpacing = double(sixgr.util.structGet(raNode, "subcarrier_spacing_khz", 1.25));
ra.RootSequenceIndex = double(sixgr.util.structGet(raNode, "root_sequence_index", 0));
ra.ZeroCorrelationZoneConfig = double(sixgr.util.structGet(raNode, "zero_correlation_zone", 8));
ra.RestrictedSetType = restrictedSet;
ra.PreambleReceivedTargetPower_dBm = double(sixgr.util.structGet(raNode, "preamble_received_target_power_dbm", -100));
ra.PowerRampingStep_dB = double(sixgr.util.structGet(raNode, "power_ramping_step_db", 2));
ra.PreambleTransMax = double(sixgr.util.structGet(raNode, "preamble_trans_max", 1));
ra.P0PUSCH_dBm = double(sixgr.util.structGet(cfg, "phy.pusch.powerControl.p0PUSCH_dBm", ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.p0_pusch_dbm", ...
    sixgr.util.structGet(cfg, "power_control.p0_pusch_dBm", NaN))));
ra.AlphaPUSCH = double(sixgr.util.structGet(cfg, "phy.pusch.powerControl.alpha", ...
    sixgr.util.structGet(cfg, "phy.pusch.power_control.alpha", ...
    sixgr.util.structGet(cfg, "power_control.alpha_pusch", NaN))));
ra.Pcmax_dBm = double(sixgr.util.structGet(cfg, "phy.pusch.powerControl.pcmax_dBm", ...
    sixgr.util.structGet(cfg, "powerAndRF.uePcmax_dBm", ...
    sixgr.util.structGet(cfg, "power_control.pcmax_dBm", NaN))));
ra.FrequencyStart = double(sixgr.util.structGet(raNode, "frequency_start", 0));
ra.PRACHOccasionFrame = double(raNode.occasion.frame);
ra.PRACHOccasionSlot = double(raNode.occasion.slot);
ra.PRACHOccasionSymbol = double(raNode.occasion.symbol);
ra.PRACHFrequencyIndex = double(raNode.occasion.frequency_index);
ra.RAResponseWindowSlots = double(sixgr.util.structGet(raNode, "ra_response_window_slots", 8));
ra.RAContentionResolutionTimerSlots = double(sixgr.util.structGet(raNode, "ra_contention_resolution_timer_slots", 64));
timingNode = raNode.timing;
ra.TimingSchedule = sixgr.phy.ia.RAEventScheduler.resolve( ...
    "PRACHOccasionEndSlot", ra.PRACHOccasionSlot, ...
    "RAResponseWindowSlots", ra.RAResponseWindowSlots, ...
    "RARProcessingDelaySlots", ...
        double(timingNode.rar_processing_delay_slots), ...
    "Msg3K2Slots", double(timingNode.msg3_k2_slots), ...
    "Msg4ProcessingDelaySlots", ...
        double(timingNode.msg4_processing_delay_slots), ...
    "ContentionResolutionTimerSlots", ...
        ra.RAContentionResolutionTimerSlots, ...
    "SetupCompleteK2Slots", ...
        double(timingNode.setup_complete_k2_slots));
ra.Msg2Slot = double(ra.TimingSchedule.Msg2Slot);
ra.Msg3Slot = double(ra.TimingSchedule.Msg3Slot);
ra.Msg4Slot = double(ra.TimingSchedule.Msg4Slot);
rrcNode = sixgr.util.structGet(cfg, "initial_access.rrc", struct());
ra.RequireRRCSetupComplete = logical(sixgr.util.structGet( ...
    rrcNode, "require_setup_complete", false));
ra.RRCTransactionID = double(sixgr.util.structGet( ...
    rrcNode, "transaction_id", NaN));
ra.SRB1LCID = double(sixgr.util.structGet(rrcNode, "srb1_lcid", NaN));
if ra.RequireRRCSetupComplete
    requiredRRC = ["transaction_id","srb1_lcid"];
    missingRRC = requiredRRC(arrayfun(@(name) ...
        isempty(sixgr.util.structGet(rrcNode, name, [])), requiredRRC));
    if ~isempty(missingRRC)
        error("sixgr:mac:ra:MissingMandatoryRRCFields", ...
            "Strict setup completion requires initial_access.rrc fields: %s", ...
            strjoin(missingRRC, ", "));
    end
    if isempty(sixgr.util.structGet(raNode, "setup_complete_pusch", []))
        error("sixgr:mac:ra:MissingMandatoryRRCFields", ...
            "Strict setup completion requires random_access.setup_complete_pusch.");
    end
    ra.SetupCompletePUSCH = localSched( ...
        raNode.setup_complete_pusch, 0, ...
        logical(sixgr.util.structGet( ...
        raNode.setup_complete_pusch, "transform_precoding", false)));
else
    ra.SetupCompletePUSCH = localSched(raNode.msg3_pusch, 0, ...
        logical(sixgr.util.structGet( ...
        raNode.msg3_pusch, "transform_precoding", false)));
end
ra.SetupCompleteSlot = double( ...
    ra.TimingSchedule.SetupCompleteSlot);
localValidateProcedureSlots(ra);
ra.TempCRNTI = double(sixgr.util.structGet(raNode, "temp_crnti", 4660));
ra.FinalCRNTI = double(sixgr.util.structGet(raNode, "final_crnti", ra.TempCRNTI));
ra.DCIPayloadBits = double(sixgr.util.structGet(raNode, "dci_payload_bits", 32));
ptrsEnabled = logical(sixgr.util.structGet(cfg, ...
    "phy.pdsch.enablePTRS", false));
ulPTRSEnabled = logical(sixgr.util.structGet(cfg, ...
    "phy.pusch.enablePTRS", ptrsEnabled));
sixgr.config.assertRuntimeFeatureUse(cfg, "ptrs", ptrsEnabled, ...
    "RAConfig.Msg2/Msg4.PDSCH.PTRS");
sixgr.config.assertRuntimeFeatureUse(cfg, "ptrs", ulPTRSEnabled, ...
    "RAConfig.Msg3/SetupComplete.PUSCH.PTRS");
ra.Msg2PDSCH = localSched(raNode.msg2_pdsch, 0, false);
ra.Msg2PDSCH.EnablePTRS = ptrsEnabled;
ra.Msg3PUSCH = localSched(raNode.msg3_pusch, ...
    double(sixgr.util.structGet(raNode.msg3_pusch, "mcs", 0)), ...
    logical(sixgr.util.structGet(raNode.msg3_pusch, ...
    "transform_precoding", sixgr.util.structGet(cfg, ...
    "phy.pusch.transformPrecoding", false))));
ra.Msg3PUSCH.EnablePTRS = ulPTRSEnabled;
ra.Msg4PDSCH = localSched(raNode.msg4_pdsch, 0, false);
ra.Msg4PDSCH.EnablePTRS = ptrsEnabled;
ra.SetupCompletePUSCH.EnablePTRS = ulPTRSEnabled;
ra.RARNTI = double(sixgr.phy.ra.computeRARNTI( ...
    "SymbolIndex", ra.PRACHOccasionSymbol, ...
    "SlotIndex", ra.PRACHOccasionSlot, ...
    "FrequencyIndex", ra.PRACHFrequencyIndex));

hashSource = jsonencode(localSerializableRAConfig(raNode));
ra.RACHConfigHash = sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(hashSource, "UTF-8")));
ra.ConfigSourceSummary = struct( ...
    "RunId", ra.RunId, ...
    "ScenarioName", ra.ScenarioName, ...
    "BindingSource", ra.BindingSource, ...
    "RACHConfigHash", ra.RACHConfigHash, ...
    "StrictMode", ra.StrictMode);
end

function s = localSched(node, defaultMCS, transformPrecoding)
s = struct();
s.PRBStart = double(sixgr.util.structGet(node, "prb_start", 0));
s.NumPRB = double(sixgr.util.structGet(node, "num_prb", 24));
s.SymbolStart = double(sixgr.util.structGet(node, "symbol_start", 0));
s.NumSymbols = double(sixgr.util.structGet(node, "num_symbols", 14));
s.MCS = double(sixgr.util.structGet(node, "mcs", defaultMCS));
s.Modulation = string(sixgr.util.structGet(node, "modulation", "QPSK"));
s.TargetCodeRate = double(sixgr.util.structGet(node, "target_code_rate", 120/1024));
s.RV = double(sixgr.util.structGet(node, "rv", 0));
s.NLayers = double(sixgr.util.structGet(node, "n_layers", 1));
s.TransformPrecoding = logical(transformPrecoding);
end

function localValidateProcedureSlots(ra)
names = ["PRACH occasion frame","PRACH occasion slot", ...
    "PRACH occasion symbol","PRACH frequency index", ...
    "Msg2 slot","Msg3 slot","Msg4 slot"];
values = [ra.PRACHOccasionFrame, ra.PRACHOccasionSlot, ...
    ra.PRACHOccasionSymbol, ra.PRACHFrequencyIndex, ...
    ra.Msg2Slot, ra.Msg3Slot, ra.Msg4Slot];
if any(~isfinite(values)) || any(values < 0) || ...
        any(values ~= round(values))
    error("sixgr:mac:ra:InvalidProcedureTiming", ...
        "%s must be explicit nonnegative integer coordinates.", ...
        strjoin(names, ", "));
end
if ra.Msg2Slot <= ra.PRACHOccasionSlot || ...
        ra.Msg3Slot <= ra.Msg2Slot || ra.Msg4Slot < ra.Msg3Slot
    error("sixgr:mac:ra:InvalidProcedureTiming", ...
        "Configured RA events must satisfy PRACH < Msg2 < Msg3 <= Msg4.");
end
if logical(ra.RequireRRCSetupComplete)
    if ~(isfinite(ra.SetupCompleteSlot) && ...
            ra.SetupCompleteSlot == fix(ra.SetupCompleteSlot) && ...
            ra.SetupCompleteSlot > ra.Msg4Slot)
        error("sixgr:mac:ra:InvalidProcedureTiming", ...
            "RRCSetupComplete slot must be an explicit integer after Msg4.");
    end
    if ~(isfinite(ra.RRCTransactionID) && ...
            any(ra.RRCTransactionID == 0:3))
        error("sixgr:mac:ra:InvalidRRCTransactionID", ...
            "initial_access.rrc.transaction_id must be in [0,3].");
    end
    if ~(isfinite(ra.SRB1LCID) && ra.SRB1LCID >= 1 && ...
            ra.SRB1LCID <= 32 && ra.SRB1LCID == fix(ra.SRB1LCID))
        error("sixgr:mac:ra:InvalidSRB1LCID", ...
            "initial_access.rrc.srb1_lcid must be an integer in [1,32].");
    end
end
end

function out = localSerializableRAConfig(s)
out = s;
try
    jsonencode(out);
catch
    out = struct();
end
end
