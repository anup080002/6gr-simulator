function cfg = applyPDCCHConfigToRuntime(cfg, strictCfg, varargin)
%APPLYPDCCHCONFIGTORUNTIME Apply strict PDCCH fields to runtime cfg.

p = inputParser;
addRequired(p, "cfg", @isstruct);
addRequired(p, "strictCfg", @isstruct);
addParameter(p, "RNTI", strictCfg.RNTIValue, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "DCIFormat", strictCfg.DCIFormat, @(x) ischar(x) || isstring(x));
addParameter(p, "AggregationLevel", strictCfg.AggregationLevel, @(x) isnumeric(x) && isscalar(x));
parse(p, cfg, strictCfg, varargin{:});
opt = p.Results;

cfg = sixgr.util.structSet(cfg, "phy.carrier.NCellID", double(strictCfg.NCellID));
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", double(strictCfg.NSizeGrid));
cfg = sixgr.util.structSet(cfg, "phy.carrier.NStartGrid", double(strictCfg.NStartGrid));
cfg = sixgr.util.structSet(cfg, "phy.numerology.scs_kHz", double(strictCfg.SubcarrierSpacingKHz));
cfg = sixgr.util.structSet(cfg, "phy.fc_Hz", double(strictCfg.CarrierFrequencyHz));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.rnti", double(opt.RNTI));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.rntiType", char(string(strictCfg.RNTIType)));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.dciPayloadBits", double(strictCfg.DCIPayloadSizeBits));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.KBits", double(strictCfg.DCIPayloadSizeBits));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.dciFormat", char(string(opt.DCIFormat)));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.aggregationLevel", double(opt.AggregationLevel));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.aggregationLevels", double(strictCfg.AggregationLevelsEnabled));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.id", double(strictCfg.CORESETId));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.duration", double(strictCfg.CORESETDurationSymbols));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.frequencyResources", double(strictCfg.CORESETFrequencyDomainResources));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.regBundleSize", double(strictCfg.REGBundleSize));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.interleaverSize", double(strictCfg.InterleaverSize));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.shiftIndex", double(strictCfg.ShiftIndex));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.id", double(strictCfg.SearchSpaceId));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.startSymbol", double(strictCfg.SearchSpaceFirstSymbolWithinSlot));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.duration", double(strictCfg.SearchSpaceDuration));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.slotPeriodAndOffset", ...
    [double(strictCfg.SearchSpacePeriodicity) double(strictCfg.SearchSpaceOffset)]);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.numCandidates", ...
    [double(strictCfg.NumCandidatesAL1) double(strictCfg.NumCandidatesAL2) ...
    double(strictCfg.NumCandidatesAL4) double(strictCfg.NumCandidatesAL8) ...
    double(strictCfg.NumCandidatesAL16)]);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.blindSearch", true);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.nStartBWP", double(strictCfg.NStartGrid));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.nSizeBWP", double(strictCfg.NSizeGrid));
end
