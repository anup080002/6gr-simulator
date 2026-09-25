classdef TimingRelationEngine < handle
    %TIMINGRELATIONENGINE Exact K0/K1/K2 timing across BWP numerologies/CCs.
    %
    % The engine validates; it never repairs an unavailable or impossible
    % target by moving it to a later slot. Every operational rejection is
    % returned with an explicit ReasonCode and recorded in Trace.

    properties (SetAccess = private)
        Policy (1,1) struct
    end

    properties (Access = private)
        CarrierByID containers.Map
        Trace struct = struct([])
        NextSequence (1,1) uint64 = uint64(1)
    end

    methods
        function obj = TimingRelationEngine(carriers, policy)
            if nargin == 0
                obj.CarrierByID = containers.Map( ...
                    "KeyType", "char", "ValueType", "any");
                obj.Policy = struct();
                return;
            end
            values = localCarrierCell(carriers);
            obj.CarrierByID = containers.Map( ...
                "KeyType", "char", "ValueType", "any");
            for index = 1:numel(values)
                carrier = values{index};
                key = char(carrier.CCID);
                if isKey(obj.CarrierByID, key)
                    error("sixgr:phy:frame:DuplicateComponentCarrier", ...
                        "Duplicate component-carrier identity '%s'.", carrier.CCID);
                end
                obj.CarrierByID(key) = carrier;
            end
            obj.Policy = localPolicy(policy);
        end

        function result = resolvePDSCH(obj, request)
            request = localSetProcedure(request, "PDSCH");
            result = obj.resolve(request);
        end

        function result = resolvePUSCH(obj, request)
            request = localSetProcedure(request, "PUSCH");
            result = obj.resolve(request);
        end

        function result = resolveHARQACK(obj, request)
            request = localSetProcedure(request, "HARQ_ACK");
            result = obj.resolve(request);
        end

        function result = resolve(obj, request)
            if ~isstruct(request) || ~isscalar(request)
                error("sixgr:phy:frame:InvalidTimingRequest", ...
                    "Timing request must be a scalar struct.");
            end
            procedure = localProcedure(localRequired(request, ...
                ["Procedure", "procedure"], "Procedure"));
            testID = string(localOptional(request, ...
                ["TestID", "test_id"], "timing-" + string(obj.NextSequence)));
            sourceTime = localTime(localRequired(request, ...
                ["SourceTime", "source_time"], "SourceTime"), "SourceTime");
            schedulingCCID = localIdentifier(localRequired(request, ...
                ["SchedulingCCID", "scheduling_cc_id"], ...
                "SchedulingCCID"), "SchedulingCCID");
            scheduledCCID = localIdentifier(localRequired(request, ...
                ["ScheduledCCID", "scheduled_cc_id"], ...
                "ScheduledCCID"), "ScheduledCCID");
            carrierIndicator = localNonnegativeInteger(localRequired(request, ...
                ["CarrierIndicator", "carrier_indicator"], ...
                "CarrierIndicator"), "CarrierIndicator");
            sourceBWPID = localIdentifier(localRequired(request, ...
                ["SourceBWPID", "source_bwp_id"], ...
                "SourceBWPID"), "SourceBWPID");
            targetBWPID = localIdentifier(localRequired(request, ...
                ["TargetBWPID", "target_bwp_id"], ...
                "TargetBWPID"), "TargetBWPID");
            sourceNumSymbols = localPositiveInteger(localRequired(request, ...
                ["SourceNumSymbols", "source_num_symbols"], ...
                "SourceNumSymbols"), "SourceNumSymbols");
            targetStartSymbol = localNonnegativeInteger(localRequired(request, ...
                ["TargetStartSymbol", "TDRAStartSymbol", ...
                "target_start_symbol"], "TargetStartSymbol"), ...
                "TargetStartSymbol");
            targetNumSymbols = localPositiveInteger(localRequired(request, ...
                ["TargetNumSymbols", "TDRANumSymbols", ...
                "target_num_symbols"], "TargetNumSymbols"), ...
                "TargetNumSymbols");
            harqProcessID = localOptional(request, ...
                ["HARQProcessID", "harq_process_id"], NaN);

            result = localBaseResult(testID, procedure, schedulingCCID, ...
                scheduledCCID, carrierIndicator, sourceBWPID, targetBWPID, ...
                sourceTime, sourceNumSymbols, targetStartSymbol, ...
                targetNumSymbols, harqProcessID);
            [schedulingCarrier, found] = obj.lookupCarrier(schedulingCCID);
            if ~found
                result = obj.finish(result, false, ...
                    "unknown_scheduling_component_carrier");
                return;
            end
            [scheduledCarrier, found] = obj.lookupCarrier(scheduledCCID);
            if ~found
                result = obj.finish(result, false, ...
                    "unknown_scheduled_component_carrier");
                return;
            end
            identity = schedulingCarrier.validateGrantIdentity(struct( ...
                "SchedulingCCID", schedulingCCID, ...
                "ScheduledCCID", scheduledCCID, ...
                "CarrierIndicator", carrierIndicator));
            if ~identity.Valid
                result = obj.finish(result, false, identity.ReasonCode);
                return;
            end
            if ~any(scheduledCarrier.SchedulingCCIDs == schedulingCCID)
                result = obj.finish(result, false, ...
                    "cross_carrier_scheduling_not_configured");
                return;
            end

            targetDirection = localTargetDirection(procedure);
            if procedure == "HARQ_ACK"
                sourceCarrier = scheduledCarrier;
            else
                sourceCarrier = schedulingCarrier;
            end
            try
                sourceBWP = sourceCarrier.configuredBWP(sourceBWPID, "DL");
            catch cause
                if string(cause.identifier) == "sixgr:phy:frame:UnknownBWP"
                    result = obj.finish(result, false, "unknown_source_bwp");
                    return;
                end
                rethrow(cause);
            end
            try
                targetBWP = scheduledCarrier.configuredBWP( ...
                    targetBWPID, targetDirection);
            catch cause
                if string(cause.identifier) == "sixgr:phy:frame:UnknownBWP"
                    result = obj.finish(result, false, "unknown_target_bwp");
                    return;
                end
                rethrow(cause);
            end
            result.SourceMu = sourceBWP.Mu;
            result.TargetMu = targetBWP.Mu;
            result.TargetDirection = targetDirection;
            if targetBWP.ControlBWPID ~= sourceBWPID
                result = obj.finish(result, false, ...
                    "control_data_bwp_relationship_mismatch");
                return;
            end
            if ~sourceCarrier.BWPState.isActiveAt( ...
                    sourceBWPID, "DL", sourceTime)
                result = obj.finish(result, false, ...
                    "source_bwp_inactive_at_source_time");
                return;
            end
            [~, ~, ~, sourceAligned] = sourceTime.toNumerology(sourceBWP);
            if ~sourceAligned
                result = obj.finish(result, false, ...
                    "source_time_not_symbol_aligned");
                return;
            end
            sourceEnd = sourceTime.plusSymbols(sourceNumSymbols, sourceBWP);
            result.SourceEndTick = sourceEnd.tickValue();

            [kValue, kReason, kField] = localK(request, procedure, obj.Policy);
            result.(kField) = kValue;
            if strlength(kReason) > 0
                result = obj.finish(result, false, kReason);
                return;
            end
            if targetStartSymbol + targetNumSymbols > ...
                    targetBWP.SymbolsPerSlot
                result = obj.finish(result, false, ...
                    "target_symbol_range_out_of_bounds");
                return;
            end

            [sourceSlotStart, ~, ~] = sourceTime.floorToSlot(sourceBWP);
            [targetBaseSlot, ~, ~] = ...
                sourceSlotStart.floorToSlot(targetBWP);
            targetSlotStart = targetBaseSlot.plusSlots(kValue, targetBWP);
            targetStart = targetSlotStart.plusSymbols( ...
                targetStartSymbol, targetBWP);
            targetEnd = targetStart.plusSymbols( ...
                targetNumSymbols, targetBWP);
            result.TargetSlotTick = targetSlotStart.tickValue();
            result.TargetTick = targetStart.tickValue();
            result.TargetEndTick = targetEnd.tickValue();
            result.TargetAbsoluteSlot = localAbsoluteSlot( ...
                targetSlotStart, targetBWP);

            if targetStart < sourceEnd
                result = obj.finish(result, false, "target_time_in_past");
                return;
            end
            if ~scheduledCarrier.BWPState.isActiveAt( ...
                    targetBWPID, targetDirection, targetStart)
                result = obj.finish(result, false, ...
                    "target_bwp_inactive_at_target_time");
                return;
            end

            [minimumProcessingTicks, processingReason] = ...
                localProcessingTicks(request, sourceBWP, targetBWP, ...
                sourceEnd, targetStart);
            if strlength(processingReason) > 0
                result = obj.finish(result, false, processingReason);
                return;
            end
            result.MinimumProcessingTicks = minimumProcessingTicks;
            waveformPlacement = targetStart;
            % TS 38.214 5.3 and 6.4 both use the advanced UL symbol
            % start. Nominal K1 timing alone cannot prove N1 feasibility.
            if any(procedure == ["PUSCH", "HARQ_ACK"])
                try
                    timingAdvance = localNonnegativeInt64(localRequired(request, ...
                        ["TimingAdvanceTicks", "timing_advance_ticks"], ...
                        "TimingAdvanceTicks"), "TimingAdvanceTicks");
                catch
                    result = obj.finish(result, false, ...
                        "invalid_timing_advance");
                    return;
                end
                result.TimingAdvanceTicks = timingAdvance;
                if timingAdvance > targetStart.tickValue()
                    result = obj.finish(result, false, ...
                        "timing_advance_before_timeline_origin");
                    return;
                end
                waveformPlacement = targetStart.plusTicks(-timingAdvance);
            end
            result.WaveformPlacementTick = waveformPlacement.tickValue();
            gap = waveformPlacement.ticksUntil(sourceEnd);
            % ticksUntil is sourceEnd - waveformPlacement; invert for the
            % source-end to waveform-placement processing interval.
            gap = -gap;
            result.ProcessingGapTicks = gap;
            if gap < minimumProcessingTicks
                result = obj.finish(result, false, ...
                    localProcessingFailureReason(procedure));
                return;
            end

            availability = scheduledCarrier.symbolAvailability( ...
                targetBWP, targetSlotStart, targetStartSymbol, ...
                targetNumSymbols, targetDirection);
            result.AvailabilityReasonCode = string(availability.ReasonCode);
            result.ObservedDirections = strjoin( ...
                string(availability.ObservedDirections(:).'), "|");
            if ~availability.Available
                result = obj.finish(result, false, ...
                    localAvailabilityReason(availability.ReasonCode));
                return;
            end

            result = obj.finish(result, true, "timing_relation_valid");
        end

        function output = traceTable(obj)
            if isempty(obj.Trace)
                output = localEmptyTraceTable();
            else
                output = struct2table(obj.Trace);
            end
        end

        function clearTrace(obj)
            obj.Trace = struct([]);
            obj.NextSequence = uint64(1);
        end

        function carrier = componentCarrier(obj, ccid)
            [carrier, found] = obj.lookupCarrier( ...
                localIdentifier(ccid, "CCID"));
            if ~found
                error("sixgr:phy:frame:UnknownComponentCarrier", ...
                    "Unknown component-carrier identity '%s'.", string(ccid));
            end
        end
    end

    methods (Static)
        function decision = resolveProductionGrant(cfg, grant)
            %RESOLVEPRODUCTIONGRANT Canonical adapter for runtime grants.
            %
            % This is the only production-facing construction path. It
            % consumes the serializable frameStructure.TimingContext
            % snapshot and never reconstructs timing from compact TDD
            % strings, legacy scalar defaults, or implicit full-slot
            % allocations.
            decision = localResolveProductionGrant(cfg, grant);
        end
    end

    methods (Access = private)
        function [carrier, found] = lookupCarrier(obj, ccid)
            key = char(ccid);
            found = isKey(obj.CarrierByID, key);
            if found
                carrier = obj.CarrierByID(key);
            else
                carrier = sixgr.phy.frame.ComponentCarrierConfig();
            end
        end

        function result = finish(obj, result, valid, reasonCode)
            result.Valid = logical(valid);
            result.ReasonCode = string(reasonCode);
            if valid
                result.Status = "PASS";
            else
                result.Status = "REJECTED";
            end
            result.Sequence = obj.NextSequence;
            obj.NextSequence = obj.NextSequence + 1;
            if isempty(obj.Trace)
                obj.Trace = result;
            else
                obj.Trace(end + 1) = result;
            end
        end
    end
end

function decision = localResolveProductionGrant(cfg, grant)
decision = localProductionDecision();
if ~(isstruct(cfg) && isscalar(cfg))
    decision.ReasonCode = "invalid_runtime_config";
    decision.Diagnostic = "Runtime configuration must be a scalar struct.";
    return;
end
if ~(isstruct(grant) && isscalar(grant))
    decision.ReasonCode = "invalid_production_grant";
    decision.Diagnostic = "Production grant must be a scalar struct.";
    return;
end

[context, frameState, reason] = localAttachedTimingContext(cfg);
if strlength(reason) > 0
    decision.ReasonCode = reason;
    decision.Diagnostic = ...
        "phy.frameStructure.TimingContext is required and must be complete.";
    return;
end
decision.ContractVersion = string(context.ContractVersion);
try
    [engine, identity] = localEngineFromAttachedContext( ...
        context, frameState);
catch cause
    decision.ReasonCode = "invalid_attached_timing_context";
    decision.Diagnostic = string(cause.identifier) + ": " + ...
        string(cause.message);
    return;
end

direction = upper(string(localOptional(grant, ...
    ["Direction", "direction"], "")));
if ~any(direction == ["DL", "UL"])
    decision.ReasonCode = "invalid_grant_direction";
    decision.Diagnostic = "Grant direction must be explicitly DL or UL.";
    return;
end
decision.Direction = direction;
[harqEnabled, reason] = localProductionHARQAuthority(cfg);
if strlength(reason) > 0
    decision.ReasonCode = reason;
    decision.Diagnostic = ...
        "phy.harq.enable and mac.harq.enable must be explicit and consistent.";
    return;
end
decision.HARQEnabled = harqEnabled;
decision.HARQACKRequired = direction == "DL" && harqEnabled;
[identity, reason] = localGrantIdentity(grant, identity);
if strlength(reason) > 0
    decision.ReasonCode = reason;
    return;
end
decision.SchedulingCCID = string(identity.SchedulingCCID);
decision.ScheduledCCID = string(identity.ScheduledCCID);
decision.CarrierIndicator = double(identity.CarrierIndicator);
decision.SourceBWPID = string(identity.SourceBWPID);
if direction == "DL"
    decision.TargetBWPID = string(identity.DLBWPID);
else
    decision.TargetBWPID = string(identity.ULBWPID);
end

[sourceAbsoluteSlot, reason] = localSourceAbsoluteSlot(grant);
if strlength(reason) > 0
    decision.ReasonCode = reason;
    return;
end
decision.ControlAbsoluteSlot = int64(sourceAbsoluteSlot);
[controlAllocation, reason] = localControlSymbolAllocation(cfg, grant);
if strlength(reason) > 0
    decision.ReasonCode = reason;
    return;
end
decision.ControlSymbolAllocation = controlAllocation;
[dataAllocation, reason] = localStrictAllocation( ...
    localOptional(grant, ["SymbolAllocation", ...
    "symbol_allocation"], []), "data");
if strlength(reason) > 0
    decision.ReasonCode = reason;
    return;
end

try
    schedulingCarrier = engine.componentCarrier(identity.SchedulingCCID);
    scheduledCarrier = engine.componentCarrier(identity.ScheduledCCID);
    sourceBWP = schedulingCarrier.configuredBWP( ...
        identity.SourceBWPID, "DL");
    dlBWP = scheduledCarrier.configuredBWP(identity.DLBWPID, "DL");
    ulBWP = scheduledCarrier.configuredBWP(identity.ULBWPID, "UL");
    sourceSlotStart = ...
        sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol( ...
        sourceAbsoluteSlot, 0, sourceBWP);
    controlStart = sourceSlotStart.plusSymbols( ...
        controlAllocation(1), sourceBWP);
catch cause
    decision.ReasonCode = "invalid_control_timing_identity";
    decision.Diagnostic = string(cause.identifier) + ": " + ...
        string(cause.message);
    return;
end

try
    if direction == "DL"
        if decision.HARQACKRequired
            requiredRelations = ["K0", "K1"];
        else
            requiredRelations = "K0";
        end
    else
        requiredRelations = "K2";
    end
    policy = sixgr.phy.frame.TimingPolicyCatalog.resolveProduction( ...
        context.Policy, dlBWP.Mu, ulBWP.Mu, requiredRelations);
catch cause
    decision.ReasonCode = "invalid_production_timing_policy";
    decision.Diagnostic = string(cause.identifier) + ": " + ...
        string(cause.message);
    return;
end
processing = localOptional(policy, ...
    ["ControlToDataProcessingTimeSymbols"], struct());
if ~(isstruct(processing) && isscalar(processing))
    decision.ReasonCode = "processing_time_policy_not_attached";
    return;
end

dataRequest = struct( ...
    "TestID", "production-" + lower(direction) + "-data", ...
    "SourceTime", controlStart, ...
    "SchedulingCCID", identity.SchedulingCCID, ...
    "ScheduledCCID", identity.ScheduledCCID, ...
    "CarrierIndicator", identity.CarrierIndicator, ...
    "SourceBWPID", identity.SourceBWPID, ...
    "TargetBWPID", localTargetBWPID(identity, direction), ...
    "SourceNumSymbols", controlAllocation(2), ...
    "TargetStartSymbol", dataAllocation(1), ...
    "TargetNumSymbols", dataAllocation(2), ...
    "HARQProcessID", localHARQProcessID(grant));

if direction == "DL"
    [minimumSymbols, validProcessing] = localPolicyScalar( ...
        processing, "PDCCHToPDSCH");
    dataRequest.MinimumProcessingSymbols = minimumSymbols;
    if ~validProcessing
        decision.ReasonCode = ...
            "pdsch_processing_time_policy_not_attached";
        return;
    end
    dataRequest.ProcessingTimeReference = ...
        policy.PDSCHProcessingTimeReference;
    [dataResult, attempts] = localSelectRelation(engine, ...
        dataRequest, "PDSCH", grant, policy, "K0");
else
    [minimumSymbols, validProcessing] = localPolicyScalar( ...
        processing, "PDCCHToPUSCHN2");
    dataRequest.MinimumProcessingSymbols = minimumSymbols;
    if ~validProcessing
        decision.ReasonCode = ...
            "n2_processing_time_policy_not_attached";
        return;
    end
    dataRequest.ProcessingTimeReference = ...
        policy.PUSCHProcessingTimeReference;
    processingBase=sixgr.phy.frame.TimingPolicyCatalog.capability1ProcessingBase( ...
        "PUSCH",[sourceBWP.Mu,ulBWP.Mu]);
    try
        processingBudget=localPUSCHProcessingBudget(cfg,grant,ulBWP, ...
            [sourceBWP.Mu,ulBWP.Mu],dataAllocation);
    catch cause
        decision.ReasonCode="pusch_processing_allocation_invalid";
        decision.Diagnostic=string(cause.identifier)+": "+string(cause.message);
        return;
    end
    dataRequest.MinimumProcessingTicks=processingBudget.Ticks;
    [timingAdvance, foundTA] = localExplicitTimingAdvance( ...
        grant, policy);
    if ~foundTA
        decision.ReasonCode = "timing_advance_not_attached";
        return;
    end
    dataRequest.TimingAdvanceTicks = timingAdvance;
    [dataResult, attempts] = localSelectRelation(engine, ...
        dataRequest, "PUSCH", grant, policy, "K2");
    dataResult.ProcessingBase=processingBase;
    dataResult.ProcessingBudget=processingBudget;
end
decision.DataDecision = dataResult;
decision.DataAttempts = attempts;
if ~dataResult.Valid
    decision.ReasonCode = "data_timing_rejected:" + ...
        string(dataResult.ReasonCode);
    return;
end
decision.DataAbsoluteSlot = int64(dataResult.TargetAbsoluteSlot);
decision.K0 = double(dataResult.K0);
decision.K2 = double(dataResult.K2);

if decision.HARQACKRequired
    [feedbackTimingAdvance, foundTA] = localExplicitTimingAdvance(grant, policy);
    if ~foundTA
        decision.ReasonCode = "harq_ack_timing_advance_not_attached";
        return;
    end
    [feedbackAllocation, reason] = ...
        localFeedbackSymbolAllocation(cfg, grant);
    if strlength(reason) > 0
        decision.ReasonCode = reason;
        return;
    end
    [minimumSymbols, validProcessing] = localPolicyScalar( ...
        processing, "PDSCHToHARQACKN1");
    if ~validProcessing
        decision.ReasonCode = ...
            "n1_processing_time_policy_not_attached";
        return;
    end
    feedbackRequest = struct( ...
        "TestID", "production-dl-harq-ack", ...
        "SourceTime", sixgr.phy.frame.AbsoluteTime.fromTicks( ...
        dataResult.TargetTick), ...
        "SchedulingCCID", identity.SchedulingCCID, ...
        "ScheduledCCID", identity.ScheduledCCID, ...
        "CarrierIndicator", identity.CarrierIndicator, ...
        "SourceBWPID", identity.DLBWPID, ...
        "TargetBWPID", identity.ULBWPID, ...
        "SourceNumSymbols", dataAllocation(2), ...
        "TargetStartSymbol", feedbackAllocation(1), ...
        "TargetNumSymbols", feedbackAllocation(2), ...
        "MinimumProcessingSymbols", minimumSymbols, ...
        "ProcessingTimeReference", ...
            policy.PDSCHProcessingTimeReference, ...
        "TimingAdvanceTicks", feedbackTimingAdvance, ...
        "HARQProcessID", localHARQProcessID(grant));
    processingBase=sixgr.phy.frame.TimingPolicyCatalog.capability1ProcessingBase( ...
        "HARQ_ACK",[sourceBWP.Mu,dlBWP.Mu,ulBWP.Mu]);
    feedbackRequest.MinimumProcessingTicks=processingBase.Ticks;
    [feedbackResult, feedbackAttempts] = localSelectRelation( ...
        engine, feedbackRequest, "HARQ_ACK", grant, policy, "K1");
    feedbackResult.ProcessingBase=processingBase;
    decision.HARQACKDecision = feedbackResult;
    decision.HARQACKAttempts = feedbackAttempts;
    if ~feedbackResult.Valid
        decision.ReasonCode = "harq_ack_timing_rejected:" + ...
            string(feedbackResult.ReasonCode);
        return;
    end
    decision.K1 = double(feedbackResult.K1);
    decision.FeedbackAbsoluteSlot = ...
        int64(feedbackResult.TargetAbsoluteSlot);
end

decision.Valid = true;
decision.Status = "PASS";
decision.ReasonCode = "production_timing_valid";
decision.Diagnostic = "";
end

function budget=localPUSCHProcessingBudget(cfg,grant,bwp,mus,allocation)
% Express the scheduled active BWP on its own numerology grid. No samples
% are generated here; the first-symbol RE occupancy is independent of the
% slot-dependent pilot sequence and frequency-hopping PRB translation.
carrier=nrCarrierConfig('NSizeGrid',bwp.NSizeBWP,'NStartGrid',bwp.NStartBWP, ...
    'SubcarrierSpacing',bwp.SCSKHz,'CyclicPrefix',bwp.CyclicPrefix);
args={'SymbolAllocation',allocation};
keys={"PRBSet","Modulation","NumLayers","RNTI","MappingType", ...
    "TransformPrecoding","TransmissionScheme","NumAntennaPorts","TPMI"};
aliases={"PRBSet","Modulation",["NumLayers","Layers"],"RNTI", ...
    ["MappingType","mappingType"],"TransformPrecoding","TransmissionScheme", ...
    ["NumAntennaPorts","NumLogicalPorts","PortCount"],["TPMI","PMI"]};
for k=1:numel(keys)
    value=localOptional(grant,aliases{k},[]);
    if keys{k}=="NumAntennaPorts"
        % Replay schemas may retain unknown spatial metadata as NaN. It is
        % not an antenna-port override: passing it to the allocator drops
        % the installed codebook dimension and leaves the toolbox default.
        % Consume the first known grant alias, otherwise retain cfg ports.
        value=[];
        for alias=aliases{k}
            candidate=localOptional(grant,alias,[]);
            if isempty(candidate) || (isnumeric(candidate) && ...
                    isscalar(candidate) && isnan(candidate))
                continue;
            end
            validateattributes(candidate,{'numeric'}, ...
                {'scalar','real','finite','integer','positive'});
            value=candidate;
            break;
        end
    end
    if ~isempty(value), args=[args,{keys{k},value}]; end %#ok<AGROW>
end
prbs=localOptional(grant,"PRBSet",[]);
start=localOptional(grant,"PRBStart",[]);
count=localOptional(grant,["AllocatedPRBCount","PRBCount"],[]);
if isempty(prbs) && ~isempty(start) && ~isempty(count)
    validateattributes(start,{'numeric'},{'scalar','integer','nonnegative','finite'});
    validateattributes(count,{'numeric'},{'scalar','integer','positive','finite'});
    args=[args,{'PRBSet',double(start)+(0:double(count)-1)}];
end
layers=localOptional(grant,["NumLayers","Layers"], ...
    sixgr.util.structGet(cfg,'phy.pusch.numLayers', ...
    sixgr.util.structGet(cfg,'phy.pusch.nLayers',NaN)));
ports=sixgr.phy.grant.resolveScheduledDMRSPortSet(cfg,'UL',layers,grant);
cfg=sixgr.util.structSet(cfg,'phy.pusch.dmrs.scheduledPortSet',ports);
[~,~,pusch]=sixgr.phy.grid.allocPUSCHTransport(carrier,cfg,args{:});
budget=sixgr.phy.frame.puschPreparationProcessingTime(carrier,pusch,mus);
end

function decision = localProductionDecision()
emptyRelation = struct();
decision = struct( ...
    "ContractVersion", "", ...
    "Adapter", ...
        "sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant", ...
    "IndexConvention", "zero_based", ...
    "Direction", "", ...
    "SchedulingCCID", "", ...
    "ScheduledCCID", "", ...
    "CarrierIndicator", NaN, ...
    "SourceBWPID", "", ...
    "TargetBWPID", "", ...
    "ControlAbsoluteSlot", int64(-1), ...
    "ControlSymbolAllocation", [], ...
    "DataAbsoluteSlot", int64(-1), ...
    "FeedbackAbsoluteSlot", int64(-1), ...
    "K0", NaN, ...
    "K1", NaN, ...
    "K2", NaN, ...
    "HARQEnabled", false, ...
    "HARQACKRequired", false, ...
    "DataDecision", emptyRelation, ...
    "HARQACKDecision", emptyRelation, ...
    "DataAttempts", struct([]), ...
    "HARQACKAttempts", struct([]), ...
    "Valid", false, ...
    "Status", "REJECTED", ...
    "ReasonCode", "", ...
    "Diagnostic", "");
end

function [enabled, reason] = localProductionHARQAuthority(cfg)
enabled = false;
reason = "";
phyValue = sixgr.util.structGet(cfg, "phy.harq.enable", []);
macValue = sixgr.util.structGet(cfg, "mac.harq.enable", []);
if isempty(phyValue) || isempty(macValue)
    reason = "harq_enable_authority_not_attached";
    return;
end
if ~(isscalar(phyValue) && (islogical(phyValue) || isnumeric(phyValue)) && ...
        isfinite(double(phyValue)) && ismember(double(phyValue), [0, 1])) || ...
        ~(isscalar(macValue) && (islogical(macValue) || isnumeric(macValue)) && ...
        isfinite(double(macValue)) && ismember(double(macValue), [0, 1]))
    reason = "invalid_harq_enable_authority";
    return;
end
if logical(phyValue) ~= logical(macValue)
    reason = "inconsistent_harq_enable_authority";
    return;
end
enabled = logical(phyValue);
end

function [context, frameState, reason] = localAttachedTimingContext(cfg)
context = struct();
frameState = struct();
reason = "";
phy = localOptional(cfg, ["phy"], []);
if ~(isstruct(phy) && isscalar(phy))
    reason = "frame_timing_context_not_attached";
    return;
end
frameState = localOptional(phy, ["frameStructure"], []);
if ~(isstruct(frameState) && isscalar(frameState))
    reason = "frame_timing_context_not_attached";
    return;
end
context = localOptional(frameState, ["TimingContext"], []);
if ~(isstruct(context) && isscalar(context))
    reason = "frame_timing_context_not_attached";
    return;
end
required = ["ContractVersion", "IndexConvention", ...
    "ComponentCarriers", "BWPState", "Policy", "DefaultIdentity"];
if any(~isfield(context, required))
    reason = "incomplete_frame_timing_context";
    return;
end
if string(context.ContractVersion) ~= "sixgr_frame_runtime_state/v1"
    reason = "unsupported_frame_timing_context_version";
    return;
end
if string(context.IndexConvention) ~= "zero_based"
    reason = "unsupported_frame_timing_index_convention";
end
end

function [engine, identity] = localEngineFromAttachedContext( ...
        context, frameState)
carrierSnapshots = context.ComponentCarriers;
if iscell(carrierSnapshots)
    carrierSnapshots = [carrierSnapshots{:}];
end
if ~(isstruct(carrierSnapshots) && ~isempty(carrierSnapshots))
    error("sixgr:phy:frame:InvalidAttachedCarrierState", ...
        "TimingContext.ComponentCarriers must be nonempty.");
end
bwpStates = context.BWPState;
if iscell(bwpStates)
    bwpStates = [bwpStates{:}];
end
if ~(isstruct(bwpStates) && numel(bwpStates) == numel(carrierSnapshots))
    error("sixgr:phy:frame:InvalidAttachedBWPState", ...
        "TimingContext.BWPState must contain one state per carrier.");
end

carriers = cell(1, numel(carrierSnapshots));
for carrierIndex = 1:numel(carrierSnapshots)
    snapshot = carrierSnapshots(carrierIndex);
    stateIndex = find(arrayfun(@(value) ...
        string(value.CCID) == string(snapshot.CCID), bwpStates), 1);
    if isempty(stateIndex)
        error("sixgr:phy:frame:InvalidAttachedBWPState", ...
            "Carrier '%s' has no attached BWP state.", ...
            string(snapshot.CCID));
    end
    state = bwpStates(stateIndex);
    rawBWPs = snapshot.BWPs;
    if iscell(rawBWPs)
        rawBWPs = [rawBWPs{:}];
    end
    if ~(isstruct(rawBWPs) && ~isempty(rawBWPs))
        error("sixgr:phy:frame:InvalidAttachedBWPState", ...
            "Carrier '%s' has no attached BWP snapshots.", ...
            string(snapshot.CCID));
    end
    bwpObjects = cell(1, numel(rawBWPs));
    for bwpIndex = 1:numel(rawBWPs)
        bwpConfig = rawBWPs(bwpIndex);
        if isfield(bwpConfig, "ConfiguredActivationTick")
            bwpConfig.SwitchActivationTick = ...
                bwpConfig.ConfiguredActivationTick;
        end
        direction = upper(string(bwpConfig.Direction));
        if direction == "DL"
            carrierGrid = snapshot.DLCarrierGrid;
        elseif direction == "UL"
            carrierGrid = snapshot.ULCarrierGrid;
        else
            error("sixgr:phy:frame:InvalidAttachedBWPState", ...
                "Attached BWP direction must be DL or UL.");
        end
        bwpObjects{bwpIndex} = sixgr.phy.frame.BWPConfig( ...
            bwpConfig, carrierGrid);
    end
    carrierConfig = snapshot;
    carriers{carrierIndex} = ...
        sixgr.phy.frame.ComponentCarrierConfig( ...
        carrierConfig, bwpObjects);
    if string(carriers{carrierIndex}.DuplexMode) == "TDD"
        if ~isfield(frameState, "SlotState") || ...
                ~(isstruct(frameState.SlotState) && ...
                isscalar(frameState.SlotState))
            error("sixgr:phy:frame:MissingAttachedSlotState", ...
                "TDD production timing requires attached canonical SlotState.");
        end
        carriers{carrierIndex}.setSlotFormatState(frameState.SlotState);
    end
    localRestoreAttachedBWPState(carriers{carrierIndex}, state);
end

engine = sixgr.phy.frame.TimingRelationEngine( ...
    carriers, context.Policy);
identity = context.DefaultIdentity;
end

function localRestoreAttachedBWPState(carrier, state)
required = ["ActiveDLBWPID", "ActiveULBWPID", "Epoch", ...
    "CurrentTick", "PendingCommands", "History", "IndexConvention"];
if any(~isfield(state, required)) || ...
        string(state.IndexConvention) ~= "zero_based"
    error("sixgr:phy:frame:IncompleteAttachedBWPState", ...
        "Attached BWP state is incomplete or uses an unsupported index convention.");
end
currentTick = localNonnegativeInt64(state.CurrentTick, "CurrentTick");
pending = localStructSequence(state.PendingCommands, "PendingCommands");
if ~isempty(pending)
    requiredCommand = ["Sequence", "CommandID", "CCID", "Direction", ...
        "TargetBWPID", "ControlBWPID", "IssuedTick", ...
        "ActivationTick", "TriggerSource", "Status", "ReasonCode"];
    if any(~isfield(pending, requiredCommand))
        error("sixgr:phy:frame:IncompleteAttachedBWPSwitchCommand", ...
            "Every attached BWP switch command must preserve its complete provenance.");
    end
    sequence = double([pending.Sequence]);
    if any(~isfinite(sequence)) || any(sequence < 0) || ...
            numel(unique(sequence)) ~= numel(sequence)
        error("sixgr:phy:frame:InvalidAttachedBWPSwitchSequence", ...
            "Attached BWP switch command sequences must be finite and unique.");
    end
    [~, order] = sort(sequence);
    pending = pending(order);
    for index = 1:numel(pending)
        command = pending(index);
        status = lower(string(command.Status));
        if status == "rejected"
            continue;
        end
        if ~any(status == ["pending", "applied"])
            error("sixgr:phy:frame:InvalidAttachedBWPSwitchStatus", ...
                "Attached BWP switch command '%s' has status '%s'.", ...
                string(command.CommandID), status);
        end
        if string(command.CCID) ~= string(carrier.CCID)
            error("sixgr:phy:frame:AttachedBWPSwitchCarrierMismatch", ...
                "BWP switch command '%s' targets the wrong component carrier.", ...
                string(command.CommandID));
        end
        issued = sixgr.phy.frame.AbsoluteTime.fromTicks( ...
            localNonnegativeInt64(command.IssuedTick, "IssuedTick"));
        activation = sixgr.phy.frame.AbsoluteTime.fromTicks( ...
            localNonnegativeInt64(command.ActivationTick, "ActivationTick"));
        result = carrier.BWPState.scheduleSwitch( ...
            string(command.Direction), string(command.TargetBWPID), ...
            activation, ...
            "IssuedTime", issued, ...
            "ControlBWPID", string(command.ControlBWPID), ...
            "TriggerSource", string(command.TriggerSource), ...
            "CommandID", string(command.CommandID));
        if ~result.Accepted
            error("sixgr:phy:frame:AttachedBWPSwitchReplayRejected", ...
                "BWP switch command '%s' could not be replayed: %s.", ...
                string(command.CommandID), string(result.ReasonCode));
        end
    end
end
carrier.BWPState.applyUntil( ...
    sixgr.phy.frame.AbsoluteTime.fromTicks(currentTick));
if string(carrier.BWPState.ActiveDLBWPID) ~= ...
        string(state.ActiveDLBWPID) || ...
        string(carrier.BWPState.ActiveULBWPID) ~= ...
        string(state.ActiveULBWPID)
    error("sixgr:phy:frame:AttachedBWPActiveStateMismatch", ...
        "Replayed BWP switch state does not match the attached active DL/UL identities.");
end
if double(carrier.BWPState.Epoch) ~= double(state.Epoch)
    error("sixgr:phy:frame:AttachedBWPEpochMismatch", ...
        "Replayed BWP epoch %d does not match attached epoch %d.", ...
        double(carrier.BWPState.Epoch), double(state.Epoch));
end
localValidateAttachedHistory(carrier.BWPState.historyTable(), ...
    state.History);
end

function localValidateAttachedHistory(replayed, rawAttached)
attached = localStructSequence(rawAttached, "History");
if isempty(attached)
    error("sixgr:phy:frame:MissingAttachedBWPHistory", ...
        "Attached BWP state must preserve its initial-state history.");
end
required = ["Event", "Direction", "Tick", "ActiveBWPID", ...
    "CommandID", "Status", "ReasonCode"];
if any(~isfield(attached, required))
    error("sixgr:phy:frame:IncompleteAttachedBWPHistory", ...
        "Attached BWP history rows are incomplete.");
end
for index = 1:numel(attached)
    row = attached(index);
    status = lower(string(row.Status));
    if status == "rejected"
        % Rejected commands do not alter state and are not replayed from
        % PendingCommands, but their attached audit row is still consumed
        % and schema-validated above.
        continue;
    end
    match = replayed.Event == string(row.Event) & ...
        replayed.Direction == string(row.Direction) & ...
        replayed.Tick == int64(row.Tick) & ...
        replayed.ActiveBWPID == string(row.ActiveBWPID) & ...
        replayed.CommandID == string(row.CommandID) & ...
        replayed.Status == string(row.Status) & ...
        replayed.ReasonCode == string(row.ReasonCode);
    if ~any(match)
        error("sixgr:phy:frame:AttachedBWPHistoryMismatch", ...
            "Attached BWP history row %d cannot be reproduced.", index - 1);
    end
end
end

function output = localStructSequence(input, label)
if isempty(input)
    output = struct([]);
elseif iscell(input)
    if ~all(cellfun(@(value) isstruct(value) && isscalar(value), input(:)))
        error("sixgr:phy:frame:InvalidAttachedBWPState", ...
            "%s cells must contain scalar structs.", label);
    end
    output = [input{:}];
elseif isstruct(input)
    output = input(:).';
else
    error("sixgr:phy:frame:InvalidAttachedBWPState", ...
        "%s must be a struct array or cell array of scalar structs.", label);
end
end

function [identity, reason] = localGrantIdentity(grant, attached)
identity = attached;
reason = "";
fields = ["SchedulingCCID", "ScheduledCCID", "CarrierIndicator", ...
    "SourceBWPID", "DLBWPID", "ULBWPID"];
for field = fields
    if ~isfield(attached, field)
        reason = "incomplete_default_timing_identity";
        return;
    end
    if isfield(grant, field) && ~isempty(grant.(char(field)))
        supplied = grant.(char(field));
        if ~isscalar(supplied) || ...
                strlength(strtrim(string(supplied))) == 0
            reason = "invalid_grant_timing_identity";
            return;
        end
        identity.(char(field)) = supplied;
    end
end
if isfield(grant, "TargetBWPID") && ~isempty(grant.TargetBWPID)
    direction = upper(string(localOptional(grant, ...
        ["Direction", "direction"], "")));
    if direction == "DL"
        identity.DLBWPID = grant.TargetBWPID;
    elseif direction == "UL"
        identity.ULBWPID = grant.TargetBWPID;
    else
        reason = "invalid_grant_direction";
    end
end
end

function [slot, reason] = localSourceAbsoluteSlot(grant)
reason = "";
raw = localOptional(grant, ...
    ["ControlAbsoluteSlot", "SourceAbsoluteSlot", "Slot"], []);
try
    slot = localNonnegativeInteger(raw, "ControlAbsoluteSlot");
catch
    slot = NaN;
    reason = "invalid_or_missing_control_absolute_slot";
end
end

function [allocation, reason] = localControlSymbolAllocation(cfg, grant)
raw = localOptional(grant, ...
    ["ControlSymbolAllocation", "PDCCHSymbolAllocation"], []);
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "phy.pdcch.symbolAllocation", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "phy.pdcch.SymbolAllocation", []);
end
if isempty(raw)
    start = sixgr.util.structGet(cfg, "phy.pdcch.startSymbol", []);
    count = sixgr.util.structGet(cfg, "phy.pdcch.numSymbols", []);
    if isempty(count)
        count = sixgr.util.structGet(cfg, ...
            "phy.pdcch.coreset.duration", []);
    end
    if ~isempty(start) && ~isempty(count)
        raw = [start, count];
    end
end
[allocation, reason] = localStrictAllocation(raw, "control");
end

function [allocation, reason] = localFeedbackSymbolAllocation(cfg, grant)
raw = localOptional(grant, ...
    ["HARQFeedbackSymbolAllocation", "PUCCHSymbolAllocation"], []);
if isempty(raw)
    raw = sixgr.util.structGet(cfg, ...
        "phy.pucch.harqACKSymbolAllocation", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "phy.pucch.SymbolAllocation", []);
end
if isempty(raw)
    raw = sixgr.util.structGet(cfg, "phy.pucch.symbolAllocation", []);
end
[allocation, reason] = localStrictAllocation(raw, "harq_ack");
end

function [allocation, reason] = localStrictAllocation(raw, label)
allocation = [NaN, NaN];
reason = "";
if ~(isnumeric(raw) && isreal(raw) && numel(raw) == 2 && ...
        all(isfinite(double(raw(:)))) && ...
        all(double(raw(:)) == fix(double(raw(:)))) && ...
        double(raw(1)) >= 0 && double(raw(2)) >= 1)
    reason = "invalid_or_missing_" + string(label) + ...
        "_symbol_allocation";
    return;
end
allocation = reshape(double(raw), 1, 2);
end

function value = localTargetBWPID(identity, direction)
if direction == "DL"
    value = identity.DLBWPID;
else
    value = identity.ULBWPID;
end
end

function processID = localHARQProcessID(grant)
raw = localOptional(grant, ...
    ["HARQProcess", "HARQProcessID"], []);
if isempty(raw)
    harq = localOptional(grant, ["HARQ"], struct());
    if isstruct(harq) && isscalar(harq)
        raw = localOptional(harq, ["HarqID", "HARQProcessID"], NaN);
    else
        raw = NaN;
    end
end
if isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
        isfinite(double(raw)) && double(raw) >= 0 && ...
        double(raw) == fix(double(raw))
    processID = double(raw);
else
    processID = NaN;
end
end

function [value, valid] = localPolicyScalar(policy, field)
valid = isfield(policy, field);
if valid
    raw = policy.(field);
    valid = isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
        isfinite(double(raw)) && double(raw) >= 0 && ...
        double(raw) == fix(double(raw));
end
if valid
    value = double(raw);
else
    value = NaN;
end
end

function [value, found] = localExplicitTimingAdvance(grant, policy)
found = false;
value = int64(-1);
if isfield(grant, "TimingAdvanceTicks")
    raw = grant.TimingAdvanceTicks;
elseif isfield(policy, "TimingAdvanceTicks")
    raw = policy.TimingAdvanceTicks;
else
    return;
end
try
    value = localNonnegativeInt64(raw, "TimingAdvanceTicks");
    found = true;
catch
    found = false;
end
end

function [result, attempts] = localSelectRelation(engine, request, ...
        procedure, grant, policy, kField)
[candidates, explicit] = localKCandidates(grant, policy, kField);
if isempty(candidates)
    result = localRejectedRelation(procedure, ...
        "no_attached_" + lower(kField) + "_candidate");
    attempts = struct([]);
    return;
end
attempts = struct([]);
result = localRejectedRelation(procedure, ...
    "no_valid_" + lower(kField) + "_candidate");
for index = 1:numel(candidates)
    request.(kField) = candidates(index);
    switch procedure
        case "PDSCH"
            candidate = engine.resolvePDSCH(request);
        case "PUSCH"
            candidate = engine.resolvePUSCH(request);
        otherwise
            candidate = engine.resolveHARQACK(request);
    end
    if procedure=="HARQ_ACK" && isfield(grant,'HARQACKPUSCHTimingConstraints')
        candidate.PUSCHMultiplexingTiming=struct([]);
        if candidate.Valid
            [muxValid,muxReason,muxEvidence]=sixgr.phy.frame.evaluateHARQPUSCHTimingConstraints( ...
                candidate,grant.HARQACKPUSCHTimingConstraints);
            candidate.PUSCHMultiplexingTiming=muxEvidence;
            if ~muxValid
                candidate.Valid=false; candidate.Status="REJECTED";
                candidate.ReasonCode=muxReason;
            end
        end
    end
    if isempty(attempts)
        attempts = candidate;
    else
        attempts(end + 1) = candidate; %#ok<AGROW>
    end
    result = candidate;
    if candidate.Valid
        return;
    end
    if explicit
        return;
    end
end
end

function [candidates, explicit] = localKCandidates(grant, policy, field)
explicit = false;
if isfield(grant, field) && ~isempty(grant.(field))
    raw = grant.(field);
    if ~(isnumeric(raw) && isscalar(raw) && isnan(double(raw)))
        candidates = raw;
        explicit = true;
        return;
    end
end
selectedField = "Selected" + field;
if isfield(policy, selectedField) && ~isempty(policy.(selectedField))
    candidates = policy.(selectedField);
    explicit = true;
    return;
end
allowedField = "Allowed" + field;
if isfield(policy, allowedField)
    candidates = reshape(double(policy.(allowedField)), 1, []);
else
    candidates = zeros(1, 0);
end
end

function result = localRejectedRelation(procedure, reason)
result = struct( ...
    "Procedure", string(procedure), ...
    "Valid", false, ...
    "Status", "REJECTED", ...
    "ReasonCode", string(reason), ...
    "K0", NaN, "K1", NaN, "K2", NaN, ...
    "TargetAbsoluteSlot", int64(-1), ...
    "TargetTick", int64(-1));
end

function policy = localPolicy(input)
if ~isstruct(input) || ~isscalar(input)
    error("sixgr:phy:frame:InvalidTimingPolicy", ...
        "Timing policy must be a scalar validated struct.");
end
policy = struct();
policy.AllowedK0 = localIntegerVector(localRequired(input, ...
    ["AllowedK0", "allowed_k0"], "AllowedK0"), "AllowedK0");
policy.AllowedK1 = localIntegerVector(localRequired(input, ...
    ["AllowedK1", "allowed_k1"], "AllowedK1"), "AllowedK1");
policy.AllowedK2 = localIntegerVector(localRequired(input, ...
    ["AllowedK2", "allowed_k2"], "AllowedK2"), "AllowedK2");
policy.PolicyID = localText(localRequired(input, ...
    ["PolicyID", "policy_id"], "PolicyID"), "PolicyID");
policy.Source = localText(localRequired(input, ...
    ["Source", "source"], "Source"), "Source");
end

function [value, reason, field] = localK(request, procedure, policy)
reason = "";
switch procedure
    case "PDSCH"
        name = ["K0", "k0"];
        allowed = policy.AllowedK0;
        field = "K0";
    case "PUSCH"
        name = ["K2", "k2"];
        allowed = policy.AllowedK2;
        field = "K2";
    otherwise
        name = ["K1", "k1"];
        allowed = policy.AllowedK1;
        field = "K1";
end
raw = localRequired(request, name, field);
if ~(isnumeric(raw) && isreal(raw) && isscalar(raw) && ...
        isfinite(double(raw)) && double(raw) >= 0 && ...
        double(raw) == fix(double(raw)))
    value = NaN;
    reason = "invalid_" + lower(field);
    return;
end
value = double(raw);
if ~any(value == allowed)
    reason = "unsupported_" + lower(field);
end
end

function [ticks, reason] = localProcessingTicks(request, sourceBWP, ...
        targetBWP, sourceEnd, targetStart)
reason = "";
rawTicks = localOptional(request, ...
    ["MinimumProcessingTicks", "minimum_processing_ticks"], []);
if ~isempty(rawTicks)
    try
        ticks = localNonnegativeInt64(rawTicks, "MinimumProcessingTicks");
    catch
        ticks = int64(-1);
        reason = "invalid_minimum_processing_time";
    end
    return;
end
rawSymbols = localOptional(request, ...
    ["MinimumProcessingSymbols", "minimum_processing_symbols"], []);
reference = upper(string(localOptional(request, ...
    ["ProcessingTimeReference", "processing_time_reference"], "")));
if isempty(rawSymbols) || strlength(reference) == 0
    ticks = int64(-1);
    reason = "processing_time_capability_not_provided";
    return;
end
try
    symbols = localNonnegativeInteger( ...
        rawSymbols, "MinimumProcessingSymbols");
catch
    ticks = int64(-1);
    reason = "invalid_minimum_processing_time";
    return;
end
if reference == "SOURCE"
    referenceMu=sourceBWP.Mu;
elseif reference == "TARGET"
    referenceMu=targetBWP.Mu;
else
    ticks = int64(-1);
    reason = "invalid_processing_time_reference";
    return;
end
% N1/N2 are measured in the nominal symbol unit specified by TS 38.214,
% not the actual duration of SOURCE/TARGET waveform symbols. Long CP and
% extended CP must affect resource boundaries, not this processing unit.
try
    ticks=sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(symbols,referenceMu);
catch cause
    if string(cause.identifier)=="sixgr:phy:frame:InvalidProcessingSymbolDuration"
        ticks=int64(-1); reason="invalid_minimum_processing_time";
        return;
    end
    rethrow(cause);
end
end

function reason = localProcessingFailureReason(procedure)
if procedure == "PUSCH"
    reason = "insufficient_n2_processing_time";
elseif procedure == "HARQ_ACK"
    reason = "insufficient_n1_processing_time";
else
    reason = "insufficient_control_to_data_processing_time";
end
end

function reason = localAvailabilityReason(input)
input = string(input);
switch input
    case "allocation_hits_fixed_ul"
        reason = "target_hits_fixed_opposite_direction";
    case "allocation_hits_fixed_dl"
        reason = "target_hits_fixed_opposite_direction";
    case "flexible_symbols_unresolved"
        reason = "target_flexible_symbols_unresolved";
    case "allocation_hits_guard"
        reason = "target_hits_guard_symbols";
    case "allocation_hits_unused"
        reason = "target_hits_unused_symbols";
    case "symbol_range_out_of_bounds"
        reason = "target_symbol_range_out_of_bounds";
    otherwise
        reason = input;
end
end

function absoluteSlot = localAbsoluteSlot(time, bwp)
[frame, slot, ~, aligned] = time.toNumerology(bwp);
if ~aligned
    error("sixgr:phy:frame:InternalTimingMisalignment", ...
        "Resolved target slot start is not aligned to its target BWP.");
end
absoluteSlot = frame * int64(bwp.SlotsPerFrame) + slot;
end

function result = localBaseResult(testID, procedure, schedulingCCID, ...
        scheduledCCID, carrierIndicator, sourceBWPID, targetBWPID, ...
        sourceTime, sourceNumSymbols, targetStartSymbol, targetNumSymbols, ...
        harqProcessID)
result = struct( ...
    "Sequence", uint64(0), ...
    "TestID", string(testID), ...
    "Procedure", string(procedure), ...
    "SchedulingCCID", string(schedulingCCID), ...
    "ScheduledCCID", string(scheduledCCID), ...
    "CarrierIndicator", double(carrierIndicator), ...
    "SourceBWPID", string(sourceBWPID), ...
    "TargetBWPID", string(targetBWPID), ...
    "TargetDirection", "", ...
    "SourceTick", sourceTime.tickValue(), ...
    "SourceEndTick", int64(-1), ...
    "SourceMu", NaN, ...
    "TargetMu", NaN, ...
    "K0", NaN, ...
    "K1", NaN, ...
    "K2", NaN, ...
    "TargetAbsoluteSlot", int64(-1), ...
    "TargetSlotTick", int64(-1), ...
    "TargetTick", int64(-1), ...
    "TargetEndTick", int64(-1), ...
    "TargetStartSymbol", double(targetStartSymbol), ...
    "TargetNumSymbols", double(targetNumSymbols), ...
    "SourceNumSymbols", double(sourceNumSymbols), ...
    "MinimumProcessingTicks", int64(-1), ...
    "ProcessingGapTicks", int64(-1), ...
    "TimingAdvanceTicks", int64(0), ...
    "WaveformPlacementTick", int64(-1), ...
    "AvailabilityReasonCode", "", ...
    "ObservedDirections", "", ...
    "HARQProcessID", double(harqProcessID), ...
    "Valid", false, ...
    "ReasonCode", "", ...
    "Status", "", ...
    "IndexConvention", "zero_based");
end

function carriers = localCarrierCell(input)
if iscell(input)
    carriers = input(:).';
elseif isa(input, "sixgr.phy.frame.ComponentCarrierConfig")
    carriers = arrayfun(@(x) x, input(:).', "UniformOutput", false);
else
    error("sixgr:phy:frame:InvalidComponentCarrierSet", ...
        "TimingRelationEngine carriers must be ComponentCarrierConfig objects.");
end
if isempty(carriers)
    error("sixgr:phy:frame:EmptyComponentCarrierSet", ...
        "TimingRelationEngine requires at least one component carrier.");
end
for index = 1:numel(carriers)
    if ~isa(carriers{index}, "sixgr.phy.frame.ComponentCarrierConfig") || ...
            ~isscalar(carriers{index})
        error("sixgr:phy:frame:InvalidComponentCarrierSet", ...
            "Each timing carrier must be a scalar ComponentCarrierConfig.");
    end
end
end

function request = localSetProcedure(request, procedure)
if ~isstruct(request) || ~isscalar(request)
    error("sixgr:phy:frame:InvalidTimingRequest", ...
        "Timing request must be a scalar struct.");
end
request.Procedure = procedure;
end

function value = localProcedure(input)
value = upper(strrep(localText(input, "Procedure"), "-", "_"));
if any(value == ["HARQ", "HARQACK", "PUCCH"])
    value = "HARQ_ACK";
end
if ~any(value == ["PDSCH", "PUSCH", "HARQ_ACK"])
    error("sixgr:phy:frame:InvalidTimingProcedure", ...
        "Procedure must be PDSCH, PUSCH, or HARQ_ACK.");
end
end

function direction = localTargetDirection(procedure)
if procedure == "PDSCH"
    direction = "DL";
else
    direction = "UL";
end
end

function value = localRequired(input, aliases, label)
names = string(fieldnames(input));
for alias = string(aliases(:)).'
    index = find(strcmpi(names, alias), 1);
    if ~isempty(index)
        value = input.(char(names(index)));
        return;
    end
end
error("sixgr:phy:frame:MissingTimingRequestField", ...
    "Timing request field '%s' is required.", label);
end

function value = localOptional(input, aliases, defaultValue)
names = string(fieldnames(input));
for alias = string(aliases(:)).'
    index = find(strcmpi(names, alias), 1);
    if ~isempty(index)
        value = input.(char(names(index)));
        return;
    end
end
value = defaultValue;
end

function value = localTime(input, label)
if ~isa(input, "sixgr.phy.frame.AbsoluteTime") || ~isscalar(input)
    error("sixgr:phy:frame:InvalidAbsoluteTime", ...
        "%s must be a scalar AbsoluteTime.", label);
end
value = input;
end

function value = localIdentifier(input, label)
if isnumeric(input) && isreal(input) && isscalar(input) && ...
        isfinite(double(input)) && double(input) >= 0 && ...
        double(input) == fix(double(input))
    value = string(double(input));
else
    value = localText(input, label);
end
if strlength(value) == 0 || contains(value, "|")
    error("sixgr:phy:frame:InvalidCarrierIdentifier", ...
        "%s is empty or contains the reserved delimiter '|'.", label);
end
end

function value = localText(input, label)
if ~(ischar(input) || (isstring(input) && isscalar(input)))
    error("sixgr:phy:frame:InvalidTextValue", ...
        "%s must be scalar text.", label);
end
value = strtrim(string(input));
end

function value = localNonnegativeInteger(input, label)
if ~(isnumeric(input) && isreal(input) && isscalar(input) && ...
        isfinite(double(input)) && double(input) >= 0 && ...
        double(input) == fix(double(input)))
    error("sixgr:phy:frame:InvalidTimingInteger", ...
        "%s must be a nonnegative integer scalar.", label);
end
value = double(input);
end

function value = localPositiveInteger(input, label)
value = localNonnegativeInteger(input, label);
if value < 1
    error("sixgr:phy:frame:InvalidTimingInteger", ...
        "%s must be a positive integer scalar.", label);
end
end

function value = localNonnegativeInt64(input, label)
if ~(isnumeric(input) && isreal(input) && isscalar(input))
    error("sixgr:phy:frame:InvalidTimingInteger", ...
        "%s must be a nonnegative int64-range integer scalar.", label);
end
if isinteger(input)
    if input < 0
        error("sixgr:phy:frame:InvalidTimingInteger", ...
            "%s must be nonnegative.", label);
    end
    if isa(input, "uint64") && input > uint64(intmax("int64"))
        error("sixgr:phy:frame:InvalidTimingInteger", ...
            "%s exceeds the int64 range.", label);
    end
    value = int64(input);
    return;
end
numericValue = double(input);
if ~(isfinite(numericValue) && numericValue >= 0 && ...
        numericValue == fix(numericValue) && ...
        numericValue <= double(intmax("int64")))
    error("sixgr:phy:frame:InvalidTimingInteger", ...
        "%s must be a nonnegative int64-range integer scalar.", label);
end
value = int64(numericValue);
end

function values = localIntegerVector(input, label)
if ~(isnumeric(input) && isreal(input) && ...
        (isempty(input) || isvector(input)) && ...
        all(isfinite(double(input(:)))) && ...
        all(double(input(:)) >= 0) && ...
        all(double(input(:)) == fix(double(input(:)))))
    error("sixgr:phy:frame:InvalidTimingPolicy", ...
        "%s must be a vector of nonnegative integers.", label);
end
values = unique(double(input(:).'), "stable");
end

function output = localEmptyTraceTable()
prototype = localBaseResult("", "PDSCH", "", "", 0, "", "", ...
    sixgr.phy.frame.AbsoluteTime.fromTicks(0), 1, 0, 1, NaN);
output = struct2table(prototype);
output(1,:) = [];
end
