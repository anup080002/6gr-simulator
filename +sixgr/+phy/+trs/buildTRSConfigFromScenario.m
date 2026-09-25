function strictCfg = buildTRSConfigFromScenario(baseCfg, varargin)
%BUILDTRSCONFIGFROMSCENARIO Resolve fail-closed NZP-CSI-RS/TRS config.

p = inputParser;
p.FunctionName = "sixgr.phy.trs.buildTRSConfigFromScenario";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "trs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "trs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "RuntimeSlot", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
parse(p, baseCfg, varargin{:});
opt = p.Results;

cfg = baseCfg;
scsKHz = localResolveSubcarrierSpacingKHz(cfg);
mandatory = ["phy.carrier.NCellID","phy.carrier.NSizeGrid"];
missing = strings(0, 1);
for ii = 1:numel(mandatory)
    value = sixgr.util.structGet(cfg, mandatory(ii), []);
    if isempty(value)
        missing(end+1, 1) = mandatory(ii); %#ok<AGROW>
    end
end
if ~(isfinite(scsKHz) && scsKHz > 0)
    missing(end+1, 1) = "phy.numerology.scs_kHz|phy.carrier.SubcarrierSpacing"; %#ok<AGROW>
end
if ~isempty(missing)
    error("sixgr:phy:trs:MissingStrictConfigField", ...
        "Strict TRS config is missing mandatory fields: %s", strjoin(missing, ", "));
end

nSizeGrid = max(1, round(double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 24))));
nStartGrid = max(0, round(double(sixgr.util.structGet(cfg, "phy.carrier.NStartGrid", 0))));
nCellID = max(0, round(double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 0))));
slotNumbers = sixgr.util.structGet(cfg, "phy.trs.slotNumbers", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.slot_numbers", []));
slotAuthority = "explicit_slot_numbers";
if isempty(slotNumbers)
    periodSlots = double(sixgr.util.structGet(cfg, "phy.trs.period_slots", NaN));
    periodOffset = double(sixgr.util.structGet(cfg, "phy.trs.period_offset", 0));
    if ~(isscalar(periodSlots) && isfinite(periodSlots) && periodSlots >= 1 && ...
            periodSlots == round(periodSlots) && isscalar(periodOffset) && ...
            isfinite(periodOffset) && periodOffset >= 0 && ...
            periodOffset < periodSlots && periodOffset == round(periodOffset))
        error("sixgr:phy:trs:MissingSlotAuthority", ...
            ["Enabled TRS requires either explicit zero-based slot_numbers " + ...
             "or an integer period_slots/period_offset pair resolved from YAML."]);
    end
    burstLength = double(sixgr.util.structGet(cfg,"phy.trs.burstLengthSlots",1));
    validateattributes(burstLength,{'numeric'},{'scalar','integer','positive','<=',periodSlots});
    slotNumbers = periodOffset+(0:burstLength-1);
    slotAuthority = "periodic_offset";
else
    rawSlotNumbers = double(slotNumbers(:).');
    if any(~isfinite(rawSlotNumbers)) || any(rawSlotNumbers < 0) || ...
            any(rawSlotNumbers ~= round(rawSlotNumbers))
        error("sixgr:phy:trs:InvalidSlotNumbers", ...
            "TRS slot_numbers must be finite nonnegative zero-based integers.");
    end
    slotNumbers = rawSlotNumbers;
end
slotNumbers = unique(slotNumbers, "stable");
runtimeWindow = struct();
if ~isempty(opt.RuntimeSlot)
    runtimeWindow = sixgr.truth.resolveTRSObservationWindow(cfg,opt.RuntimeSlot);
    if ~runtimeWindow.ObservationStarts
        error("sixgr:phy:trs:NotObservationStart", ...
            "Runtime slot %g is not the first resource of this TRS observation window.",opt.RuntimeSlot);
    end
    slotNumbers = runtimeWindow.AbsoluteSlotNumbers;
end

nPorts = max(1, round(double(sixgr.util.structGet(cfg, "phy.trs.nPorts", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.num_ports", 1)))));
rowNumber = max(1, round(double(sixgr.util.structGet(cfg, "phy.trs.csirsRowNumber", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.row_number", localRowForPorts(nPorts))))));
symbolLocation = double(sixgr.util.structGet(cfg, "phy.trs.symbolLocation", ...
    sixgr.util.structGet(cfg, "phy.trs.symbolLocations", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.symbol_locations", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.symbol_location", [])))));
subcarrierLocation = max(0, round(double(sixgr.util.structGet(cfg, "phy.trs.subcarrierLocation", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.subcarrier_location", 0)))));
rbOffset = max(0, round(double(sixgr.util.structGet(cfg, "phy.trs.rbOffset", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.rb_offset", 0)))));
numRB = round(double(sixgr.util.structGet(cfg, "phy.trs.numRB", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.num_rb", nSizeGrid - rbOffset))));
numRB = max(1, min(numRB, nSizeGrid - rbOffset));
scramblingID = max(0, round(double(sixgr.util.structGet(cfg, "phy.trs.scramblingID", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.scrambling_id", nCellID)))));

strictCfg = struct();
strictCfg.RunId = string(opt.RunId);
strictCfg.ScenarioName = string(opt.ScenarioName);
strictCfg.RunFolder = string(opt.RunFolder);
strictCfg.CellId = 1;
strictCfg.UEId = 1;
strictCfg.BindingSource = string(sixgr.util.structGet(cfg, "phy.trs.bindingSource", "scenario_config"));
strictCfg.ReferenceSignalFamily = "TRS";
strictCfg.ToolboxReferenceSignal = "NZP-CSI-RS";
strictCfg.TRSInfoEnabled = true;
strictCfg.NCellID = double(nCellID);
strictCfg.NSizeGrid = double(nSizeGrid);
strictCfg.NStartGrid = double(nStartGrid);
strictCfg.SubcarrierSpacingKHz = double(scsKHz);
strictCfg.FrameNumber = 0;
if ~isempty(fieldnames(runtimeWindow))
    strictCfg.FrameNumber = runtimeWindow.FrameNumber;
    strictCfg.RuntimeObservationWindow = runtimeWindow;
end
strictCfg.SlotNumbers = double(slotNumbers);
strictCfg.NZPCSIRSResourceIDs = double(sixgr.util.structGet(cfg, ...
    "lls6g.reference_signals.trs.resource_ids",[]));
strictCfg.BurstLengthSlots = double(sixgr.util.structGet(cfg,"phy.trs.burstLengthSlots",numel(slotNumbers)));
strictCfg.SlotAuthority = slotAuthority;
strictCfg.PeriodSlots = double(sixgr.util.structGet(cfg, "phy.trs.period_slots", NaN));
strictCfg.PeriodOffset = double(sixgr.util.structGet(cfg, "phy.trs.period_offset", NaN));
strictCfg.CSIRSType = "nzp";
strictCfg.CSIRSPeriod = "on";
strictCfg.RowNumber = double(rowNumber);
strictCfg.NumCSIRSPortsRequested = double(nPorts);
strictCfg.SymbolLocation = double(symbolLocation);
strictCfg.SubcarrierLocation = double(subcarrierLocation);
strictCfg.RBOffset = double(rbOffset);
strictCfg.NumRB = double(numRB);
strictCfg.NID = double(scramblingID);
strictCfg.DetectionThreshold = double(sixgr.util.structGet(cfg, "phy.trs.detectionThreshold", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.detection_threshold", 0.55)));
strictCfg.DetectionPolicy = string(sixgr.util.structGet(cfg,"phy.trs.detectionPolicy","fixed_correlation"));
strictCfg.RuntimeChannelEstimator = string(sixgr.util.structGet(cfg,"phy.trs.runtimeChannelEstimator","nr_channel_estimate"));
strictCfg.TargetFalseAlarmProbability = double(sixgr.util.structGet(cfg,"phy.trs.targetFalseAlarmProbability",NaN));
strictCfg.MinCoverageRatio = double(sixgr.util.structGet(cfg, "phy.trs.minCoverageRatio", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.min_coverage_ratio", 0.95)));
strictCfg.TimingToleranceSamples = double(sixgr.util.structGet(cfg, "phy.trs.timingToleranceSamples", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.timing_tolerance_samples", 2)));
strictCfg.FrequencyToleranceHz = double(sixgr.util.structGet(cfg, "phy.trs.frequencyToleranceHz", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.frequency_tolerance_hz", 50)));
strictCfg.ChannelNMSEThresholddB = double(sixgr.util.structGet(cfg, "phy.trs.channelNMSEThresholddB", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.channel_nmse_threshold_db", -8)));
strictCfg.HighSNRdB = double(sixgr.util.structGet(cfg, "channel.snr_dB", ...
    sixgr.util.structGet(cfg, "simulation.snr_db", 35)));
strictCfg.LowSNRSweepdB = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.low_snr_sweep_db", [-12 0 20 35]));
strictCfg.TimingOffsetSweepSamples = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.timing_offset_sweep_samples", [0 2 4]));
strictCfg.FrequencyOffsetSweepHz = double(sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.frequency_offset_sweep_hz", [0 100 250]));
strictCfg.ChannelModel = string(sixgr.util.structGet(cfg, "channel.model", "AWGN"));
strictCfg.BaseConfig = cfg;

resourceSet = sixgr.phy.trs.buildNZPCSIRSResourceSetForTRS(strictCfg);
if ~isempty(fieldnames(runtimeWindow)) && runtimeWindow.Authority == "explicit_slot_numbers" && ...
        runtimeWindow.SlotsPerFrame ~= double(resourceSet.Carrier.SlotsPerFrame)
    error("sixgr:phy:trs:RuntimeFrameTimingMismatch", ...
        "Resolved TRS slotsPerFrame must match the actual carrier numerology.");
end
strictCfg.ToolboxCarrier = resourceSet.Carrier;
strictCfg.ToolboxCSIRS = resourceSet.CSIRS;
strictCfg.ToolboxResources = resourceSet.Resources;
strictCfg.NumCSIRSPorts = double(resourceSet.CSIRS.NumCSIRSPorts);
strictCfg.CDMType = string(resourceSet.CSIRS.CDMType);
strictCfg.Density = string(resourceSet.CSIRS.Density);
strictCfg.ConfigHash = sixgr.phy.trs.hashTRSConfig(strictCfg);
strictCfg.StrictValidation = sixgr.phy.trs.validateTRSConfigStrict(strictCfg);
strictCfg.ConfigExport = rmfield(strictCfg, intersect(fieldnames(strictCfg), ...
    {'ToolboxCarrier','ToolboxCSIRS','ToolboxResources','BaseConfig','ConfigExport','StrictValidation'}));
end

function row = localRowForPorts(nPorts)
if nPorts <= 1
    % trs-Info uses one-port, density-three NZP-CSI-RS mapping row 1.
    row = 1;
elseif nPorts <= 2
    row = 3;
else
    row = 4;
end
end

function scsKHz = localResolveSubcarrierSpacingKHz(cfg)
scsKHz = double(sixgr.util.structGet(cfg, "phy.numerology.scs_kHz", NaN));
if isfinite(scsKHz) && scsKHz > 0
    return;
end
scsKHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", NaN)));
end
