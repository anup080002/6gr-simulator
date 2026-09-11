function [pdcch, cfgSI, carrierSI, resolution, absoluteSlot] = ...
        resolveSIB1ControlOccasion(carrier, cfg)
mib = sixgr.phy.broadcast.splitPDCCHConfigSIB1(localPDCCHConfigSIB1(cfg), ...
    "Source", "tx_configured_mib_pdcch_ConfigSIB1");
mib.DMRSTypeAPosition = double(sixgr.util.structGet(cfg, "phy.mib.dmrsTypeAPosition", 2));
[resolution, cfgSI] = sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier, cfg, mib, "RNTI", 65535);
ordinal = localMonitoringOccasionOrdinal(cfg);
if ordinal > height(resolution.MonitoringOccasions)
    error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
        "Type0 monitoring occasion ordinal %d exceeds the %d resolved occasions.", ...
        ordinal, height(resolution.MonitoringOccasions));
end
absoluteSlot = double( ...
    resolution.MonitoringOccasions.AbsoluteSlot(ordinal));
carrierSI = localCarrierAtAbsoluteSlot(carrier, absoluteSlot);
cfgSI = sixgr.util.structSet(cfgSI, ...
    "phy.carrier.NSlot", double(carrierSI.NSlot));
cfgSI = sixgr.util.structSet(cfgSI, ...
    "phy.carrier.NFrame", double(carrierSI.NFrame));
cfgSI = sixgr.util.structSet(cfgSI, ...
    "phy.sib1.pdcchAbsoluteSlot", absoluteSlot);
pdcch = resolution.PDCCH;
cfgSI = sixgr.util.structSet(cfgSI, "phy.sib1.resolvedCORESET0", resolution.CORESET0);
cfgSI = sixgr.util.structSet(cfgSI, "phy.sib1.resolvedSearchSpace0", resolution.SearchSpace0);
end

function value = localPDCCHConfigSIB1(cfg)
configured = sixgr.util.structGet(cfg, "phy.mib.pdcchConfigSIB1", []);
if isempty(configured)
    coreset0 = double(sixgr.util.structGet(cfg, "phy.sib1.coreset0Index", 0));
    search0 = double(sixgr.util.structGet(cfg, "phy.sib1.searchSpaceZero", 0));
    configured = coreset0 * 16 + search0;
end
value = double(configured);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && value >= 0 && value <= 255)
    error("sixgr:phy:broadcast:InvalidPDCCHConfigSIB1", ...
        "MIB pdcch-ConfigSIB1 must resolve to an integer in [0,255].");
end
end

function ordinal = localMonitoringOccasionOrdinal(cfg)
raw = sixgr.util.structGet(cfg, ...
    "initial_access.type0.monitoring_occasion_ordinal", ...
    sixgr.util.structGet(cfg, ...
    "phy.sib1.monitoringOccasionOrdinal", []));
if isempty(raw)
    error("sixgr:phy:broadcast:MissingType0MonitoringOccasion", ...
        "Strict SIB1 scheduling requires initial_access.type0.monitoring_occasion_ordinal.");
end
ordinal = localPositiveInteger(raw, "monitoring_occasion_ordinal");
end

function carrier = localCarrierAtAbsoluteSlot(carrier, absoluteSlot)
absoluteSlot = localNonnegativeInteger(absoluteSlot, "absoluteSlot");
slotsPerFrame = 10 * round(double(carrier.SlotsPerSubframe));
carrier.NFrame = floor(absoluteSlot / slotsPerFrame);
carrier.NSlot = mod(absoluteSlot, slotsPerFrame);
end

function value = localNonnegativeInteger(raw, fieldName)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && ...
        value >= 0)
    error("sixgr:phy:broadcast:InvalidSIB1Allocation", ...
        "%s must be a nonnegative integer.", fieldName);
end
end

function value = localPositiveInteger(raw, fieldName)
value = localNonnegativeInteger(raw, fieldName);
if value < 1
    error("sixgr:phy:broadcast:InvalidSIB1Allocation", ...
        "%s must be a positive integer.", fieldName);
end
end
