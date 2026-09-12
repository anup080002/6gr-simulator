classdef DCIContextFactory
    %DCICONTEXTFACTORY Build strict contexts from operator-owned control config.

    methods (Static)
        function context = fromRuntimeConfig(cfg, dciFormat)
            control = sixgr.util.structGet(cfg, "phy.pdcch.operatorControl", []);
            if isstruct(control) && isfield(control,'connected_dci')
                context=sixgr.phy.pdcch.ConnectedDCIProfile.fromRuntimeConfig(cfg,dciFormat);
                return;
            end
            if isempty(control)
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "Runtime config does not carry phy.pdcch.operatorControl.");
            end
            context = sixgr.phy.pdcch.DCIContextFactory.fromOperatorControl( ...
                control, dciFormat);
        end

        function context = fromOperatorControl(control, dciFormat)
            if ~(isstruct(control) && isscalar(control))
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "Operator control configuration must be one scalar structure.");
            end
            strict = localRequired(control, "pdcch_strict");
            raw = localRequired(strict, "dci_context");
            fmt = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
            formats = string(localRequired(control, "dci_formats"));
            for ii = 1:numel(formats)
                formats(ii) = sixgr.phy.pdcch.normalizeDCIFormat(formats(ii));
            end
            rnti = localRequired(strict, "rnti");
            searchSpaceType = upper(string(localRequired(control, "search_space_type")));
            if any(searchSpaceType == ["UE","UE_SPECIFIC"])
                searchSpaceType = "USS";
            elseif searchSpaceType == "COMMON"
                searchSpaceType = "CSS";
            end
            data = struct( ...
                "SpecRelease", string(localRequired(strict, "spec_release")), ...
                "SpecVersion", string(localRequired(strict, "spec_version")), ...
                "DCIFormat", fmt, ...
                "RNTIType", string(localRequired(rnti, "type")), ...
                "RNTIValue", double(localRequired(rnti, "value")), ...
                "SearchSpaceType", searchSpaceType, ...
                "SearchSpaceID", double(localRequired(raw, "search_space_id")), ...
                "CORESETID", double(localRequired(raw, "coreset_id")), ...
                "ControlServingCell", double(localRequired(raw, "control_serving_cell")), ...
                "ControlCarrier", double(localRequired(raw, "control_carrier")), ...
                "ControlBWP", double(localRequired(raw, "control_bwp")), ...
                "ScheduledServingCell", double(localRequired(raw, "scheduled_serving_cell")), ...
                "ScheduledCarrier", double(localRequired(raw, "scheduled_carrier")), ...
                "ScheduledBWP", double(localRequired(raw, "scheduled_bwp")), ...
                "InitialDLBWPSize", double(localRequired(raw, "initial_dl_bwp_size")), ...
                "InitialDLBWPStart", double(localRequired(raw, "initial_dl_bwp_start")), ...
                "ActiveDLBWPSize", double(localRequired(raw, "active_dl_bwp_size")), ...
                "ActiveDLBWPStart", double(localRequired(raw, "active_dl_bwp_start")), ...
                "InitialULBWPSize", double(localRequired(raw, "initial_ul_bwp_size")), ...
                "InitialULBWPStart", double(localRequired(raw, "initial_ul_bwp_start")), ...
                "ActiveULBWPSize", double(localRequired(raw, "active_ul_bwp_size")), ...
                "ActiveULBWPStart", double(localRequired(raw, "active_ul_bwp_start")), ...
                "FrequencyAllocationType", string(localRequired(raw, "frequency_allocation_type")), ...
                "DLTimeDomainAllocations", double(localRequired(raw, "dl_time_domain_allocations")), ...
                "ULTimeDomainAllocations", double(localRequired(raw, "ul_time_domain_allocations")), ...
                "CarrierIndicatorPresent", logical(localRequired(raw, "carrier_indicator_present")), ...
                "CarrierIndicatorWidth", double(localRequired(raw, "carrier_indicator_width")), ...
                "CarrierIndicatorValue", double(localRequired(raw, "carrier_indicator_value")), ...
                "BWPIndicatorPresent", logical(localRequired(raw, "bwp_indicator_present")), ...
                "BWPIndicatorWidth", double(localRequired(raw, "bwp_indicator_width")), ...
                "SULIndicatorPresent", logical(localRequired(raw, "sul_indicator_present")), ...
                "FrequencyHoppingEnabled", logical(localRequired(raw, "frequency_hopping_enabled")), ...
                "TransformPrecodingEnabled", logical(localRequired(raw, "transform_precoding_enabled")), ...
                "HARQProcessCount", double(localRequired(raw, "harq_process_count")), ...
                "DAIWidth", double(localRequired(raw, "dai_width")), ...
                "AntennaPortFieldWidth", double(localRequired(raw, "antenna_port_field_width")), ...
                "LayerCapability", double(localRequired(raw, "layer_capability")), ...
                "TCIPresent", logical(localRequired(raw, "tci_present")), ...
                "TCIWidth", double(localRequired(raw, "tci_width")), ...
                "ActiveTCIStateID", double(localRequired(raw, "active_tci_state_id")), ...
                "SRSResourceIndicatorWidth", double(localRequired(raw, "srs_resource_indicator_width")), ...
                "SRSRequestWidth", double(localRequired(raw, "srs_request_width")), ...
                "CSIRequestWidth", double(localRequired(raw, "csi_request_width")), ...
                "RateMatchIndicatorWidth", double(localRequired(raw, "rate_match_indicator_width")), ...
                "ZPCSIRSTriggerWidth", double(localRequired(raw, "zp_csirs_trigger_width")), ...
                "CBGFieldsPresent", logical(localRequired(raw, "cbg_fields_present")), ...
                "CBGTransmissionWidth", double(localRequired(raw, "cbg_transmission_width")), ...
                "CBGFlushWidth", double(localRequired(raw, "cbg_flush_width")), ...
                "DMRSSequenceInitializationPresent", logical(localRequired(raw, ...
                    "dmrs_sequence_initialization_present")), ...
                "MonitoredFormats", formats(:).', ...
                "ConfigurationEpoch", double(localRequired(raw, "configuration_epoch")), ...
                "ExecutionProfile", string(localRequired(strict, "execution_profile")), ...
                "ResearchClass", string(localRequired(strict, "research_class")), ...
                "LegacyCompatibility", false);
            if isfield(raw,'ul_precoding')
                data.ULPrecoding=raw.ul_precoding;
                sixgr.phy.pdcch.ULPrecodingField.resolve(data);
            end
            if isfield(control,'dl_reference_signaling')
                data.DLReferenceSignaling=control.dl_reference_signaling;
                sixgr.phy.pdcch.DLReferenceSignaling.resolve(data);
            end
            context = sixgr.phy.pdcch.DCIContext(data);
        end

        function [context, timeDomainAssignmentIndex, source] = fromScheduledGrant(cfg, grant, dciFormat)
            %FROMSCHEDULEDGRANT Bind DCI semantics to the active YAML TDRA.
            %
            % A DCI time-domain field is an index into the active RRC
            % PDSCH/PUSCH-TimeDomainResourceAllocationList; it is not a
            % SLIV.  The same immutable context returned here must therefore
            % be used by both the scheduler packer and the receiver-side
            % semantic decoder.  This prevents a grant built from a
            % scenario-specific allocation (for example [0 13] when the
            % last UL symbol is reserved for SRS) from being decoded through
            % the legacy [0 14] table.
            if ~(isstruct(cfg) && isscalar(cfg))
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "Scheduled-grant DCI context requires one runtime config structure.");
            end
            if ~(isstruct(grant) && isscalar(grant) && ~isempty(fieldnames(grant)))
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "Scheduled-grant DCI context requires one finalized scheduler grant.");
            end

            fmt = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
            direction = localDirectionFromFormat(fmt);
            symbolAllocation = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
            symbolAllocation = reshape(symbolAllocation, 1, []);
            if numel(symbolAllocation) ~= 2 || any(~isfinite(symbolAllocation)) || ...
                    any(symbolAllocation ~= fix(symbolAllocation)) || ...
                    symbolAllocation(1) < 0 || symbolAllocation(2) < 1
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "Scheduled-grant DCI context requires integer SymbolAllocation=[start,count].");
            end

            operatorControl = sixgr.util.structGet(cfg, "phy.pdcch.operatorControl", struct());
            strict = sixgr.util.structGet(operatorControl, "pdcch_strict", struct());
            hasOperatorContext = isstruct(strict) && isscalar(strict) && ...
                isfield(strict, "dci_context") && ~isempty(strict.dci_context);
            hasOperatorContext=hasOperatorContext || isfield(operatorControl,'connected_dci');
            if hasOperatorContext
                context = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg, fmt);
                % The operator context declares the RRC layout and RNTI
                % type. For connected scheduling its RNTI value is a
                % template, not the identity of every scheduled UE. Bind
                % the authored payload context to the actual grant without
                % mutating the installed configuration/shared template.
                rnti = sixgr.util.structGet(grant, "RNTI", []);
                if ~(isnumeric(rnti) && isscalar(rnti) && isreal(rnti) && ...
                        isfinite(rnti) && rnti == fix(rnti) && rnti >= 0 && rnti <= 65535)
                    error("sixgr:phy:pdcch:missing_dci_context", ...
                        "Scheduled-grant DCI context requires an explicit integer RNTI in [0,65535].");
                end
                data = context.Data;
                if any(upper(string(data.RNTIType)) == ["C-RNTI","CS-RNTI","MCS-C-RNTI"])
                    data.RNTIValue = double(rnti);
                    context = sixgr.phy.pdcch.DCIContext(data);
                elseif double(data.RNTIValue) ~= double(rnti)
                    error("sixgr:phy:pdcch:wrong_dci_context", ...
                        "Common-procedure RNTI differs from its installed DCI context.");
                end
                source = "operator_rrc_dci_context";
            else
                nGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN));
                if ~(isscalar(nGrid) && isfinite(nGrid) && nGrid >= 1 && nGrid == fix(nGrid))
                    error("sixgr:phy:pdcch:missing_dci_context", ...
                        "Scheduled-grant DCI context requires integer phy.carrier.NSizeGrid.");
                end
                rnti = double(sixgr.util.structGet(grant, "RNTI", ...
                    sixgr.util.structGet(cfg, "phy.pdcch.rnti", NaN)));
                if ~(isscalar(rnti) && isfinite(rnti) && rnti >= 0 && rnti <= 65535)
                    error("sixgr:phy:pdcch:missing_dci_context", ...
                        "Scheduled-grant DCI context requires a finite RNTI in [0,65535].");
                end
                legacy = sixgr.phy.pdcch.DCIContext.fromLegacy(struct( ...
                    "NSizeGrid", nGrid, ...
                    "RNTIValue", rnti, ...
                    "SearchSpaceId", double(sixgr.util.structGet(cfg, ...
                        "phy.pdcch.searchSpace.id", 1)), ...
                    "CORESETId", double(sixgr.util.structGet(cfg, ...
                        "phy.pdcch.coreset.id", 0)), ...
                    "MonitoredFormats", string(sixgr.util.structGet(cfg, ...
                        "phy.pdcch.dciFormats", fmt))), fmt);
                data = legacy.Data;
                data.RNTIValue = rnti;
                data.SearchSpaceID = double(sixgr.util.structGet(cfg, ...
                    "phy.pdcch.searchSpace.id", data.SearchSpaceID));
                data.CORESETID = double(sixgr.util.structGet(cfg, ...
                    "phy.pdcch.coreset.id", data.CORESETID));
                data.ConfigurationEpoch = double(sixgr.util.structGet(cfg, ...
                    "phy.pdcch.configurationEpoch", data.ConfigurationEpoch));
                data.ExecutionProfile = "yaml_derived_active_tdra";
                data.LegacyCompatibility = false;
                [data.DLTimeDomainAllocations, dlSource] = ...
                    localActiveTDRA(cfg, grant, "DL", data.DLTimeDomainAllocations);
                [data.ULTimeDomainAllocations, ulSource] = ...
                    localActiveTDRA(cfg, grant, "UL", data.ULTimeDomainAllocations);
                context = sixgr.phy.pdcch.DCIContext(data);
                if direction == "DL"
                    source = dlSource;
                else
                    source = ulSource;
                end
            end

            if isfield(operatorControl,'dl_reference_signaling')
                data=context.Data;
                data.DLReferenceSignaling=operatorControl.dl_reference_signaling;
                sixgr.phy.pdcch.DLReferenceSignaling.resolve(data);
                context=sixgr.phy.pdcch.DCIContext(data);
            end
            if fmt=="0_1" && isfield(operatorControl,'ul_precoding')
                data=context.Data;
                if isfield(data,'ULPrecoding')
                    assert(isequaln(data.ULPrecoding,operatorControl.ul_precoding), ...
                        'sixgr:phy:pdcch:ULPrecodingContextMismatch','Conflicting UL precoding configurations.');
                end
                data.ULPrecoding=operatorControl.ul_precoding;
                sixgr.phy.pdcch.ULPrecodingField.resolve(data);
                context=sixgr.phy.pdcch.DCIContext(data);
            end
            if fmt=="0_1" && isfield(context.Data,'ULPrecoding')
                ul=context.Data.ULPrecoding;
                assert(double(ul.num_ports)==double(cfg.phy.pusch.NumAntennaPorts) && ...
                    double(ul.num_ports)==double(cfg.phy.srs.nPorts) && ...
                    double(ul.max_rank)>=double(cfg.phy.pusch.numLayers) && ...
                    logical(context.Data.TransformPrecodingEnabled)==logical(cfg.phy.pusch.transformPrecoding), ...
                    'sixgr:phy:pdcch:ULPrecodingContextMismatch', ...
                    'DCI UL precoding context must agree with the configured SRS/PUSCH ports, rank and waveform.');
            end
            if fmt=="0_1" && isfield(operatorControl,'ul_reference_signaling')
                data=context.Data; data.ULReferenceSignaling=operatorControl.ul_reference_signaling;
                sixgr.phy.pdcch.ULReferenceSignaling.resolve(data);
                assert(data.ULReferenceSignaling.srs_resource_count==1 && ...
                    isstruct(cfg.phy.srs) && isscalar(cfg.phy.srs) && ...
                    string(cfg.phy.srs.resourceSetUsage)=="codebook", ...
                    'sixgr:phy:pdcch:SRSResourceSetRuntimeMismatch', ...
                    'The current runtime config constructs one codebook SRS resource, not multiple independently selectable resources.');
                context=sixgr.phy.pdcch.DCIContext(data);
            end
            if direction == "DL"
                allocations = context.Data.DLTimeDomainAllocations;
            else
                allocations = context.Data.ULTimeDomainAllocations;
            end
            matches = find(double(allocations(:,2)) == symbolAllocation(1) & ...
                double(allocations(:,3)) == symbolAllocation(2));
            if isempty(matches)
                error("sixgr:phy:pdcch:grant_tdra_not_configured", ...
                    "The finalized %s grant SymbolAllocation=[%d %d] is absent " + ...
                     "from the active %s time-domain allocation list.", ...
                    direction, symbolAllocation(1), symbolAllocation(2), direction);
            end

            % Equal S/L allocations can occupy different future slots.
            % Select the row by the actual K0/K2 as well, not merely by
            % symbol span. Otherwise the DCI can advertise a different
            % data slot from the frozen scheduler decision.
            requestedOffset = localScheduledTimingOffset(grant,direction);
            if isfinite(requestedOffset)
                if size(allocations,2) < 4
                    error("sixgr:phy:pdcch:grant_tdra_timing_mismatch", ...
                        "Scheduled %s DCI requires an explicit TDRA timing-offset column.",direction);
                end
                matches = matches(double(allocations(matches,4)) == requestedOffset);
                if isempty(matches)
                    error("sixgr:phy:pdcch:grant_tdra_timing_mismatch", ...
                        "No active %s TDRA row matches SymbolAllocation=[%d %d] and offset %d.", ...
                        direction,symbolAllocation(1),symbolAllocation(2),requestedOffset);
                end
            end

            requestedIndex = localFirstFinite([ ...
                sixgr.util.structGet(grant, "TimeDomainResourceAssignmentIndex", NaN), ...
                sixgr.util.structGet(grant, "TDRAIndex", NaN), ...
                sixgr.util.structGet(grant, "TimeResourceAssignment", NaN)], NaN);
            if isfinite(requestedIndex)
                selected = matches(double(allocations(matches,1)) == requestedIndex);
                if isempty(selected)
                    error("sixgr:phy:pdcch:grant_tdra_index_mismatch", ...
                        "Configured TDRA index %d does not identify the finalized %s " + ...
                         "grant SymbolAllocation=[%d %d].", ...
                        round(requestedIndex), direction, symbolAllocation(1), symbolAllocation(2));
                end
                rowIndex = selected(1);
            else
                rowIndex = matches(1);
            end
            timeDomainAssignmentIndex = double(allocations(rowIndex,1));
        end
    end
end

function value = localScheduledTimingOffset(grant,direction)
if direction == "DL", name = "K0"; else, name = "K2"; end
value = NaN;
for path = ["TimingDecision."+name, name, name+"Slots"]
    candidate = sixgr.util.structGet(grant,path,[]);
    if isempty(candidate), continue; end
    if ~(isnumeric(candidate) && isscalar(candidate) && isreal(candidate) && ...
            (isnan(candidate) || (isfinite(candidate) && candidate >= 0 && candidate == fix(candidate))))
        error("sixgr:phy:pdcch:grant_tdra_timing_mismatch", ...
            "Scheduled %s must be a nonnegative integer or unset NaN.",path);
    end
    if isnan(candidate), continue; end
    if isfinite(value) && value ~= double(candidate)
        error("sixgr:phy:pdcch:grant_tdra_timing_mismatch", ...
            "Conflicting %s scheduler timing aliases.",name);
    end
    value = double(candidate);
end
end

function value = localRequired(source, name)
if ~(isstruct(source) && isscalar(source) && isfield(source, name))
    error("sixgr:phy:pdcch:missing_dci_context", ...
        "Operator PDCCH configuration is missing '%s'.", name);
end
value = source.(name);
if isempty(value)
    error("sixgr:phy:pdcch:missing_dci_context", ...
        "Operator PDCCH configuration field '%s' is empty.", name);
end
end

function direction = localDirectionFromFormat(fmt)
if startsWith(string(fmt), "0_")
    direction = "UL";
else
    direction = "DL";
end
end

function [rows, source] = localActiveTDRA(cfg, grant, direction, defaults)
direction = upper(string(direction));
grantDirection = upper(string(sixgr.util.structGet(grant, "Direction", "")));
if direction == "DL"
    root = "phy.pdsch";
    listNames = [root + ".timeDomainAllocations", ...
        root + ".time_domain_allocations", ...
        root + ".TimeDomainAllocations"];
    offset = localFirstFinite([ ...
        sixgr.util.structGet(grant, "TimingDecision.K0", NaN), ...
        sixgr.util.structGet(grant, "K0Slots", NaN), ...
        sixgr.util.structGet(cfg, "mac.timing.k0", NaN)], 0);
else
    root = "phy.pusch";
    listNames = [root + ".timeDomainAllocations", ...
        root + ".time_domain_allocations", ...
        root + ".TimeDomainAllocations"];
    offset = localFirstFinite([ ...
        sixgr.util.structGet(grant, "TimingDecision.K2", NaN), ...
        sixgr.util.structGet(grant, "K2Slots", NaN), ...
        sixgr.util.structGet(cfg, "mac.timing.k2", NaN)], 1);
end

rows = [];
for ii = 1:numel(listNames)
    candidate = sixgr.util.structGet(cfg, listNames(ii), []);
    if ~isempty(candidate)
        rows = double(candidate);
        break;
    end
end
if ~isempty(rows)
    if ~(ismatrix(rows) && size(rows,2) >= 3 && all(isfinite(rows(:))))
        error("sixgr:phy:pdcch:missing_dci_context", ...
            "%s time-domain allocation list must be a finite matrix [index,start,count,...].", ...
            direction);
    end
    source = "yaml_explicit_active_tdra_list";
    return;
end

allocation = double(sixgr.util.structGet(cfg, root + ".symbolAllocation", []));
if isempty(allocation)
    startSymbol = sixgr.util.structGet(cfg, root + ".startSymbol", []);
    numSymbols = sixgr.util.structGet(cfg, root + ".numSymbols", []);
    if ~isempty(startSymbol) && ~isempty(numSymbols)
        allocation = [double(startSymbol), double(numSymbols)];
    end
end
allocation = reshape(allocation, 1, []);
if numel(allocation) ~= 2 || any(~isfinite(allocation))
    % The opposite direction may be disabled in a direction-specific unit
    % scenario.  Preserve its complete legacy table; the scheduled
    % direction is still validated below against its active allocation.
    rows = double(defaults);
    source = "legacy_opposite_direction_tdra_not_scheduled";
    return;
end

rows = double(defaults);
if grantDirection == direction || strlength(grantDirection) == 0
    requestedIndex = localFirstFinite([ ...
        sixgr.util.structGet(grant, "TimeDomainResourceAssignmentIndex", NaN), ...
        sixgr.util.structGet(grant, "TDRAIndex", NaN), ...
        sixgr.util.structGet(grant, "TimeResourceAssignment", NaN)], 0);
else
    requestedIndex = 0;
end
requestedIndex = max(0, round(requestedIndex));
rowIndex = find(rows(:,1) == requestedIndex, 1, "first");
if isempty(rowIndex)
    rows(end+1,:) = [requestedIndex, allocation(1), allocation(2), offset]; %#ok<AGROW>
else
    rows(rowIndex,2:4) = [allocation(1), allocation(2), offset];
end
source = "yaml_symbol_allocation_derived_active_tdra";
end

function value = localFirstFinite(values, defaultValue)
value = double(defaultValue);
try
    values = double(values(:));
catch
    return;
end
values = values(isfinite(values));
if ~isempty(values)
    value = double(values(1));
end
end
