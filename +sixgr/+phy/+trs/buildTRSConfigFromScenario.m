function strictCfg = buildTRSConfigFromScenario(baseCfg, varargin)
%BUILDTRSCONFIGFROMSCENARIO Resolve fail-closed NZP-CSI-RS/TRS config.

p = inputParser;
p.FunctionName = "sixgr.phy.trs.buildTRSConfigFromScenario";
addRequired(p, "baseCfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunFolder", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RunId", "trs_strict_validation", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "trs_strict_validation", @(x) ischar(x) || isstring(x));
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
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.slot_numbers", [0 1]));
slotNumbers = unique(max(0, round(double(slotNumbers(:).'))), "stable");
if numel(slotNumbers) < 2
    slotNumbers = [slotNumbers slotNumbers(1)+1];
end

nPorts = max(1, round(double(sixgr.util.structGet(cfg, "phy.trs.nPorts", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.num_ports", 1)))));
rowNumber = max(1, round(double(sixgr.util.structGet(cfg, "phy.trs.csirsRowNumber", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.row_number", localRowForPorts(nPorts))))));
symbolLocation = max(0, round(double(sixgr.util.structGet(cfg, "phy.trs.symbolLocation", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.trs.symbol_location", 4)))));
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
strictCfg.SlotNumbers = double(slotNumbers);
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
strictCfg.ToolboxCarrier = resourceSet.Carrier;
strictCfg.ToolboxCSIRS = resourceSet.CSIRS;
strictCfg.NumCSIRSPorts = double(resourceSet.CSIRS.NumCSIRSPorts);
strictCfg.CDMType = string(resourceSet.CSIRS.CDMType);
strictCfg.Density = string(resourceSet.CSIRS.Density);
strictCfg.ConfigHash = sixgr.phy.trs.hashTRSConfig(strictCfg);
strictCfg.StrictValidation = sixgr.phy.trs.validateTRSConfigStrict(strictCfg);
strictCfg.ConfigExport = rmfield(strictCfg, intersect(fieldnames(strictCfg), ...
    {'ToolboxCarrier','ToolboxCSIRS','BaseConfig','ConfigExport','StrictValidation'}));
end

function row = localRowForPorts(nPorts)
if nPorts <= 1
    row = 2;
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
