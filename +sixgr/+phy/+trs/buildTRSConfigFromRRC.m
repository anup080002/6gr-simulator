function cfg = buildTRSConfigFromRRC(rrcCfg, baseCfg, varargin)
%BUILDTRSCONFIGFROMRRC Resolve strict TRS config from RRC-like fields.

if nargin < 2 || isempty(baseCfg)
    baseCfg = struct();
end
cfgIn = baseCfg;
paths = ["row_number","symbol_location","symbol_locations","subcarrier_location","num_rb", ...
    "rb_offset","scrambling_id","slot_numbers","burst_length_slots","detection_threshold"];
for ii = 1:numel(paths)
    value = sixgr.util.structGet(rrcCfg, paths(ii), []);
    if isempty(value)
        value = sixgr.util.structGet(rrcCfg, "trs." + paths(ii), []);
    end
    if ~isempty(value)
        key = lower(strrep(char(paths(ii)), "_", ""));
        switch key
            case "rownumber"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.csirsRowNumber", value);
            case {"symbollocation","symbollocations"}
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.symbolLocation", value);
            case "subcarrierlocation"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.subcarrierLocation", value);
            case "numrb"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.numRB", value);
            case "rboffset"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.rbOffset", value);
            case "scramblingid"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.scramblingID", value);
            case "slotnumbers"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.slotNumbers", value);
            case "burstlengthslots"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.burstLengthSlots", value);
            case "detectionthreshold"
                cfgIn = sixgr.util.structSet(cfgIn, "phy.trs.detectionThreshold", value);
        end
    end
end
cfg = sixgr.phy.trs.buildTRSConfigFromScenario(cfgIn, varargin{:});
cfg.BindingSource = "rrc_config";
cfg.ConfigHash = sixgr.phy.trs.hashTRSConfig(cfg);
cfg.StrictValidation = sixgr.phy.trs.validateTRSConfigStrict(cfg);
end
