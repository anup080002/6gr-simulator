function [pdcch, cfgSI, carrierSI, resolution, absoluteSlot] = ...
        resolveSIB1ControlOccasion(carrier, cfg, varargin)
% AbsoluteSlot selects an actual configured SI transmission, not any legal
% monitoring candidate. Its first ordinal is anchored once at radio epoch 0.
p=inputParser;
p.addParameter('AbsoluteSlot',[]);
p.parse(varargin{:});
requested=p.Results.AbsoluteSlot;
explicit=~isempty(requested);
if explicit
    assert(isnumeric(requested) && isreal(requested) && isscalar(requested) && ...
        isfinite(requested) && requested>=0 && requested==fix(requested) && ...
        requested<flintmax/160, 'sixgr:phy:broadcast:InvalidSIB1Clock', ...
        'AbsoluteSlot must be an exact nonnegative numeric slot index.');
    requested=double(requested);
    origin=carrier; origin.NFrame=0; origin.NSlot=0;
    cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
else
    origin=carrier;
end
mib = sixgr.phy.broadcast.splitPDCCHConfigSIB1(localPDCCHConfigSIB1(cfg), ...
    "Source", "tx_configured_mib_pdcch_ConfigSIB1");
mib.DMRSTypeAPosition = double(sixgr.util.structGet(cfg, "phy.mib.dmrsTypeAPosition", 2));
[resolution, cfgSI] = sixgr.phy.broadcast.deriveType0PDCCHFromMIB(origin, cfg, mib, "RNTI", 65535);
ordinal = localMonitoringOccasionOrdinal(cfg);
if ordinal > height(resolution.MonitoringOccasions)
    error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
        "Type0 monitoring occasion ordinal %d exceeds the %d resolved occasions.", ...
        ordinal, height(resolution.MonitoringOccasions));
end
selected=resolution.MonitoringOccasions(ordinal,:);
first=double(selected.AbsoluteSlot);
period=double(selected.PeriodSlots);
if explicit
    assert(resolution.MultiplexingPattern==1 && ...
        ~resolution.Context.SharedSpectrum && ...
        any(resolution.Context.PDCCHSCSKHz==[15 30]) && ...
        period==2*double(carrier.SlotsPerFrame), ...
        'sixgr:phy:broadcast:UnsupportedSIB1TransmissionCalendar', ...
        'Independent SI currently supports non-shared FR1 pattern 1 at 15/30 kHz.');
    assert(requested>=first && mod(requested-first,period)==0, ...
        'sixgr:phy:broadcast:SIB1OutsideConfiguredCalendar', ...
        ['SI slot %d is outside the configured transmitted subset: first=%d, ' ...
         'period=%d. Other legal monitoring candidates are not scheduled transmissions.'], ...
        requested,first,period);
    window=sixgr.phy.pdcch.resolveType0MonitoringWindow( ...
        resolution.Context,requested,requested+1);
    assert(height(window.MonitoringOccasions)==1 && ...
        window.MonitoringOccasions.FirstSymbol==selected.FirstSymbol, ...
        'sixgr:phy:broadcast:SIB1OutsideConfiguredCalendar', ...
        'The configured SI recurrence must also be an original Type-0 monitoring occasion.');
    % Preserve the original public row schema (window diagnostics remain a
    % separate receipt); do not relabel an ordinal in a moving frame.
    selected=window.MonitoringOccasions(:,selected.Properties.VariableNames);
    resolution.TransmissionMonitoringWindowSHA256=window.WindowSHA256;
end
absoluteSlot=double(selected.AbsoluteSlot);
resolution.SelectedMonitoringOccasion=selected;
resolution.ConfiguredMonitoringOccasionOrdinal=ordinal;
resolution.FirstSelectedAbsoluteSlot=first;
resolution.SIB1TransmissionPeriodSlots=period;
resolution.ExplicitAbsoluteTransmissionSlot=explicit;
if sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD"
    frame=sixgr.phy.FrameStructureEngine(cfg,"FrameCoreOnly",true);
    partition=frame.SlotPartition(absoluteSlot);
    if ~logical(partition.AllowDL)
        error("sixgr:phy:broadcast:Type0OccasionNotDLCapable", ...
            ["MIB pdcch-ConfigSIB1 resolves Type-0 PDCCH/SIB1 to absolute " + ...
             "slot %d (%s), which has no DL-capable symbols in the installed " + ...
             "TDD common pattern. Select a standards-derived SearchSpaceZero " + ...
             "occasion that is DL-capable."], ...
            absoluteSlot,string(partition.SlotLabel));
    end
end
carrierSI = localCarrierAtAbsoluteSlot(carrier, absoluteSlot);
cfgSI=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfgSI,absoluteSlot+1);
cfgSI = sixgr.util.structSet(cfgSI, ...
    "phy.sib1.pdcchAbsoluteSlot", absoluteSlot);
pdcch = resolution.PDCCH;
cfgSI = sixgr.util.structSet(cfgSI, "phy.sib1.resolvedCORESET0", resolution.CORESET0);
cfgSI = sixgr.util.structSet(cfgSI, "phy.sib1.resolvedSearchSpace0", resolution.SearchSpace0);
if sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD"
    controlSymbols = [double(pdcch.SearchSpace.StartSymbolWithinSlot), ...
        double(pdcch.CORESET.Duration)];
    if ~frame.IsDLAllocation(absoluteSlot,controlSymbols)
        error("sixgr:phy:broadcast:Type0ControlSymbolsNotDLCapable", ...
            "Configured Type-0 PDCCH symbols [%d,%d] in absolute slot %d are not entirely DL-capable.", ...
            controlSymbols(1),controlSymbols(2),absoluteSlot);
    end
    allocation = sixgr.phy.broadcast.configuredSIB1Allocation(carrierSI,cfgSI);
    if ~frame.IsDLAllocation(absoluteSlot,allocation.SymbolAllocation)
        error("sixgr:phy:broadcast:SIB1SymbolsNotDLCapable", ...
            "Configured SIB1 symbols [%d,%d] in absolute slot %d are not entirely DL-capable. Select an explicit legal monitoring occasion/allocation.", ...
            allocation.SymbolAllocation(1),allocation.SymbolAllocation(2),absoluteSlot);
    end
end
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
