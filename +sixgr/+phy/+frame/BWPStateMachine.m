classdef BWPStateMachine < handle
    %BWPSTATEMACHINE Direction-isolated, absolute-time BWP activation.
    %
    % Switch commands are queued with an exact activation tick. Applying a
    % DL switch never changes the active UL BWP, and vice versa. Grants are
    % validated against the state at their own absolute time.

    properties (SetAccess = private)
        CCID (1,1) string = ""
        ActiveDLBWPID (1,1) string = ""
        ActiveULBWPID (1,1) string = ""
        CurrentTime (1,1) sixgr.phy.frame.AbsoluteTime = ...
            sixgr.phy.frame.AbsoluteTime.fromTicks(0)
        Epoch (1,1) uint64 = uint64(0)
    end

    properties (Access = private)
        BWPList cell = {}
        PendingCommands struct = struct([])
        History struct = struct([])
        NextSequence (1,1) uint64 = uint64(1)
        InitialDLBWPID (1,1) string = ""
        InitialULBWPID (1,1) string = ""
    end

    methods
        function obj = BWPStateMachine(bwps)
            if nargin == 0
                return;
            end
            obj.BWPList = localBWPCell(bwps);
            if isempty(obj.BWPList)
                error("sixgr:phy:frame:EmptyBWPSet", ...
                    "BWPStateMachine requires at least one BWPConfig.");
            end
            ccids = strings(numel(obj.BWPList), 1);
            pairKeys = strings(numel(obj.BWPList), 1);
            versions = zeros(numel(obj.BWPList), 1);
            for index = 1:numel(obj.BWPList)
                bwp = obj.BWPList{index};
                ccids(index) = bwp.CCID;
                pairKeys(index) = bwp.Direction + "|" + bwp.BWPID;
                versions(index) = double(bwp.StateVersion);
            end
            if numel(unique(ccids)) ~= 1
                error("sixgr:phy:frame:MixedCarrierBWPSet", ...
                    "One BWPStateMachine cannot contain BWPs from different CCIDs.");
            end
            if numel(unique(pairKeys)) ~= numel(pairKeys)
                error("sixgr:phy:frame:DuplicateBWPIdentity", ...
                    "BWP identities must be unique within each direction.");
            end
            obj.CCID = ccids(1);
            obj.Epoch = uint64(max(versions));
            obj.ActiveDLBWPID = localInitialActive(obj.BWPList, "DL");
            obj.ActiveULBWPID = localInitialActive(obj.BWPList, "UL");
            obj.InitialDLBWPID = obj.ActiveDLBWPID;
            obj.InitialULBWPID = obj.ActiveULBWPID;
            if strlength(obj.ActiveDLBWPID) > 0
                obj.appendHistory("INITIAL_STATE", "DL", obj.CurrentTime, ...
                    "", obj.ActiveDLBWPID, obj.ActiveDLBWPID, "", ...
                    "configuration", "initial-dl", "active", "initial_active_bwp");
            end
            if strlength(obj.ActiveULBWPID) > 0
                obj.appendHistory("INITIAL_STATE", "UL", obj.CurrentTime, ...
                    "", obj.ActiveULBWPID, obj.ActiveULBWPID, "", ...
                    "configuration", "initial-ul", "active", "initial_active_bwp");
            end
        end

        function decision = scheduleSwitch(obj, direction, targetBWPID, ...
                activationTime, varargin)
            direction = localDirection(direction);
            targetBWPID = localIdentifier(targetBWPID, "targetBWPID");
            activationTime = localTime(activationTime, "activationTime");

            parser = inputParser;
            parser.FunctionName = "BWPStateMachine.scheduleSwitch";
            parser.addParameter("IssuedTime", obj.CurrentTime, ...
                @(v) isa(v, "sixgr.phy.frame.AbsoluteTime") && isscalar(v));
            parser.addParameter("ControlBWPID", obj.ActiveDLBWPID, ...
                @(v) localIdentifierPredicate(v));
            parser.addParameter("TriggerSource", "RRC", @(v) localTextPredicate(v));
            parser.addParameter("CommandID", "", @(v) localTextPredicate(v));
            parser.parse(varargin{:});
            issuedTime = localTime(parser.Results.IssuedTime, "IssuedTime");
            controlBWPID = localIdentifier( ...
                parser.Results.ControlBWPID, "ControlBWPID");
            triggerSource = localText(parser.Results.TriggerSource, ...
                "TriggerSource");
            commandID = string(parser.Results.CommandID);
            if strlength(commandID) == 0
                commandID = "bwp-switch-" + string(obj.NextSequence);
            end

            if issuedTime < obj.CurrentTime
                decision = obj.rejectedDecision(direction, targetBWPID, ...
                    activationTime, controlBWPID, triggerSource, commandID, ...
                    "issued_time_before_state_time");
                return;
            end
            obj.applyUntil(issuedTime);
            if activationTime < issuedTime
                decision = obj.rejectedDecision(direction, targetBWPID, ...
                    activationTime, controlBWPID, triggerSource, commandID, ...
                    "activation_time_before_command");
                return;
            end
            [target, found] = obj.lookupBWP(targetBWPID, direction);
            if ~found
                decision = obj.rejectedDecision(direction, targetBWPID, ...
                    activationTime, controlBWPID, triggerSource, commandID, ...
                    "unknown_target_bwp");
                return;
            end
            try
                target.assertActivationCompatible();
            catch cause
                if string(cause.identifier) == ...
                        "sixgr:phy:frame:TDDReferenceSCSAboveActiveBWP"
                    reason = "tdd_reference_scs_above_target_bwp";
                else
                    rethrow(cause);
                end
                decision = obj.rejectedDecision(direction, targetBWPID, ...
                    activationTime, controlBWPID, triggerSource, commandID, reason);
                return;
            end
            if activationTime < target.ConfiguredActivationTime
                decision = obj.rejectedDecision(direction, targetBWPID, ...
                    activationTime, controlBWPID, triggerSource, commandID, ...
                    "activation_time_before_configured_time");
                return;
            end
            if strlength(controlBWPID) == 0 || ...
                    ~obj.isActiveNoAdvance(controlBWPID, "DL")
                decision = obj.rejectedDecision(direction, targetBWPID, ...
                    activationTime, controlBWPID, triggerSource, commandID, ...
                    "control_bwp_not_active");
                return;
            end
            command = struct( ...
                "Sequence", obj.NextSequence, ...
                "CommandID", commandID, ...
                "CCID", obj.CCID, ...
                "Direction", direction, ...
                "FromBWPID", obj.activeID(direction), ...
                "TargetBWPID", targetBWPID, ...
                "ControlBWPID", controlBWPID, ...
                "IssuedTick", issuedTime.tickValue(), ...
                "ActivationTick", activationTime.tickValue(), ...
                "TriggerSource", triggerSource, ...
                "Status", "pending", ...
                "ReasonCode", "switch_queued");
            if isempty(obj.PendingCommands)
                obj.PendingCommands = command;
            else
                obj.PendingCommands(end + 1) = command;
            end
            obj.NextSequence = obj.NextSequence + 1;
            obj.appendHistory("SWITCH_COMMAND", direction, issuedTime, ...
                command.FromBWPID, targetBWPID, command.FromBWPID, ...
                controlBWPID, triggerSource, commandID, "pending", ...
                "switch_queued");
            decision = localDecision(true, "switch_queued", commandID, ...
                direction, command.FromBWPID, targetBWPID, ...
                activationTime, obj.Epoch);
        end

        function applyUntil(obj, time)
            time = localTime(time, "time");
            if time < obj.CurrentTime
                error("sixgr:phy:frame:BWPStateTimeRegression", ...
                    "BWP state cannot move backward from tick %d to tick %d.", ...
                    obj.CurrentTime.tickValue(), time.tickValue());
            end
            if ~isempty(obj.PendingCommands)
                pending = find(arrayfun(@(x) string(x.Status) == "pending" && ...
                    x.ActivationTick <= time.tickValue(), obj.PendingCommands));
                if ~isempty(pending)
                    orderTable = table( ...
                        int64([obj.PendingCommands(pending).ActivationTick]).', ...
                        uint64([obj.PendingCommands(pending).Sequence]).', ...
                        pending(:), ...
                        'VariableNames', [ ...
                        "ActivationTick", "Sequence", "CommandIndex"]);
                    orderTable = sortrows(orderTable, ...
                        ["ActivationTick", "Sequence"]);
                    pending = orderTable.CommandIndex.';
                    for index = pending
                        command = obj.PendingCommands(index);
                        old = obj.activeID(command.Direction);
                        obj.setActiveID(command.Direction, command.TargetBWPID);
                        obj.Epoch = obj.Epoch + 1;
                        obj.PendingCommands(index).Status = "applied";
                        obj.PendingCommands(index).ReasonCode = "switch_activated";
                        activation = sixgr.phy.frame.AbsoluteTime.fromTicks( ...
                            command.ActivationTick);
                        obj.appendHistory("SWITCH_ACTIVATION", ...
                            command.Direction, activation, old, ...
                            command.TargetBWPID, command.TargetBWPID, ...
                            command.ControlBWPID, command.TriggerSource, ...
                            command.CommandID, "active", "switch_activated");
                    end
                end
            end
            obj.CurrentTime = time;
        end

        function bwp = activeBWP(obj, direction, time)
            direction = localDirection(direction);
            if nargin >= 3 && ~isempty(time)
                obj.applyUntil(time);
            end
            id = obj.activeID(direction);
            if strlength(id) == 0
                error("sixgr:phy:frame:NoActiveBWP", ...
                    "Carrier '%s' has no configured active %s BWP.", ...
                    obj.CCID, direction);
            end
            [bwp, found] = obj.lookupBWP(id, direction);
            if ~found
                error("sixgr:phy:frame:CorruptBWPState", ...
                    "Active %s BWP '%s' is absent from the configured set.", ...
                    direction, id);
            end
        end

        function tf = isActive(obj, bwpID, direction, time)
            direction = localDirection(direction);
            bwpID = localIdentifier(bwpID, "bwpID");
            if nargin >= 4 && ~isempty(time)
                obj.applyUntil(time);
            end
            tf = obj.isActiveNoAdvance(bwpID, direction);
        end

        function tf = isActiveAt(obj, bwpID, direction, time)
            direction = localDirection(direction);
            bwpID = localIdentifier(bwpID, "bwpID");
            time = localTime(time, "time");
            tf = obj.activeIDAt(direction, time) == bwpID;
        end

        function bwp = activeBWPAt(obj, direction, time)
            direction = localDirection(direction);
            time = localTime(time, "time");
            id = obj.activeIDAt(direction, time);
            if strlength(id) == 0
                error("sixgr:phy:frame:NoActiveBWP", ...
                    "Carrier '%s' has no configured active %s BWP.", ...
                    obj.CCID, direction);
            end
            [bwp, found] = obj.lookupBWP(id, direction);
            if ~found
                error("sixgr:phy:frame:CorruptBWPState", ...
                    "Historical active %s BWP '%s' is not configured.", ...
                    direction, id);
            end
        end

        function epoch = epochAt(obj, time)
            time = localTime(time, "time");
            % The configuration epoch is the initial maximum StateVersion
            % plus each command whose exact activation time has elapsed.
            initialEpoch = uint64(0);
            for index = 1:numel(obj.BWPList)
                initialEpoch = max(initialEpoch, obj.BWPList{index}.StateVersion);
            end
            if isempty(obj.PendingCommands)
                epoch = initialEpoch;
                return;
            end
            activated = arrayfun(@(x) x.ActivationTick <= time.tickValue() && ...
                string(x.Status) ~= "rejected", obj.PendingCommands);
            epoch = initialEpoch + uint64(nnz(activated));
        end

        function result = validateGrant(obj, grant)
            if ~isstruct(grant) || ~isscalar(grant)
                error("sixgr:phy:frame:InvalidBWPGrant", ...
                    "BWP grant validation input must be a scalar struct.");
            end
            direction = localDirection(localRequiredField(grant, ...
                ["Direction", "direction"], "Direction"));
            bwpID = localIdentifier(localRequiredField(grant, ...
                ["BWPID", "bwp_id"], "BWPID"), "BWPID");
            ccid = localIdentifier(localRequiredField(grant, ...
                ["CCID", "cc_id"], "CCID"), "CCID");
            time = localTime(localRequiredField(grant, ...
                ["Time", "AbsoluteTime", "time"], "Time"), "Time");
            if ccid ~= obj.CCID
                result = localGrantDecision(false, ...
                    "grant_carrier_identity_mismatch", ccid, bwpID, ...
                    direction, time, obj.epochAt(time));
                return;
            end
            [target, found] = obj.lookupBWP(bwpID, direction);
            if ~found
                result = localGrantDecision(false, "unknown_bwp", ...
                    ccid, bwpID, direction, time, obj.epochAt(time));
                return;
            end
            if ~obj.isActiveAt(bwpID, direction, time)
                result = localGrantDecision(false, "inactive_bwp", ...
                    ccid, bwpID, direction, time, obj.epochAt(time));
                return;
            end
            controlID = localIdentifier(string(localOptionalField(grant, ...
                ["ControlBWPID", "control_bwp_id"], target.ControlBWPID)), ...
                "ControlBWPID");
            if controlID ~= target.ControlBWPID
                result = localGrantDecision(false, ...
                    "control_data_bwp_relationship_mismatch", ...
                    ccid, bwpID, direction, time, obj.epochAt(time));
                return;
            end
            if ~obj.isActiveAt(controlID, "DL", time)
                result = localGrantDecision(false, ...
                    "control_bwp_inactive", ccid, bwpID, direction, ...
                    time, obj.epochAt(time));
                return;
            end
            result = localGrantDecision(true, "bwp_active", ...
                ccid, bwpID, direction, time, obj.epochAt(time));
        end

        function requireActive(obj, bwpID, direction, time)
            grant = struct("CCID", obj.CCID, "BWPID", bwpID, ...
                "Direction", direction, "Time", time);
            result = obj.validateGrant(grant);
            if ~result.Allowed
                error("sixgr:phy:frame:InactiveBWPGrant", ...
                    "Grant on carrier '%s', %s BWP '%s' at tick %d was " + ...
                    "rejected: %s.", ...
                    obj.CCID, result.Direction, result.BWPID, ...
                    result.Tick, result.ReasonCode);
            end
        end

        function bwp = configuredBWP(obj, bwpID, direction)
            [bwp, found] = obj.lookupBWP( ...
                localIdentifier(bwpID, "bwpID"), localDirection(direction));
            if ~found
                error("sixgr:phy:frame:UnknownBWP", ...
                    "Unknown %s BWP '%s' on carrier '%s'.", ...
                    localDirection(direction), string(bwpID), obj.CCID);
            end
        end

        function values = configuredBWPs(obj, direction)
            direction = localDirection(direction);
            keep = cellfun(@(x) x.Direction == direction, obj.BWPList);
            values = obj.BWPList(keep);
        end

        function output = historyTable(obj)
            if isempty(obj.History)
                output = localEmptyHistoryTable();
            else
                output = struct2table(obj.History);
            end
        end

        function output = pendingTable(obj)
            if isempty(obj.PendingCommands)
                output = table();
            else
                output = struct2table(obj.PendingCommands);
            end
        end
    end

    methods (Access = private)
        function [bwp, found] = lookupBWP(obj, bwpID, direction)
            found = false;
            bwp = sixgr.phy.frame.BWPConfig();
            for index = 1:numel(obj.BWPList)
                candidate = obj.BWPList{index};
                if candidate.BWPID == bwpID && ...
                        candidate.Direction == direction
                    bwp = candidate;
                    found = true;
                    return;
                end
            end
        end

        function id = activeID(obj, direction)
            if direction == "DL"
                id = obj.ActiveDLBWPID;
            else
                id = obj.ActiveULBWPID;
            end
        end

        function setActiveID(obj, direction, id)
            if direction == "DL"
                obj.ActiveDLBWPID = id;
            else
                obj.ActiveULBWPID = id;
            end
        end

        function tf = isActiveNoAdvance(obj, bwpID, direction)
            tf = obj.activeID(direction) == bwpID;
        end

        function id = activeIDAt(obj, direction, time)
            if direction == "DL"
                id = obj.InitialDLBWPID;
            else
                id = obj.InitialULBWPID;
            end
            if isempty(obj.PendingCommands)
                return;
            end
            selected = find(arrayfun(@(x) ...
                string(x.Direction) == direction && ...
                x.ActivationTick <= time.tickValue() && ...
                string(x.Status) ~= "rejected", obj.PendingCommands));
            if isempty(selected)
                return;
            end
            orderTable = table( ...
                int64([obj.PendingCommands(selected).ActivationTick]).', ...
                uint64([obj.PendingCommands(selected).Sequence]).', ...
                selected(:), ...
                'VariableNames', [ ...
                "ActivationTick", "Sequence", "CommandIndex"]);
            orderTable = sortrows(orderTable, ...
                ["ActivationTick", "Sequence"]);
            command = obj.PendingCommands(orderTable.CommandIndex(end));
            id = string(command.TargetBWPID);
        end

        function decision = rejectedDecision(obj, direction, targetBWPID, ...
                activationTime, controlBWPID, triggerSource, commandID, reason)
            old = obj.activeID(direction);
            obj.appendHistory("SWITCH_COMMAND", direction, obj.CurrentTime, ...
                old, targetBWPID, old, controlBWPID, triggerSource, ...
                commandID, "rejected", reason);
            decision = localDecision(false, reason, commandID, direction, ...
                old, targetBWPID, activationTime, obj.Epoch);
        end

        function appendHistory(obj, event, direction, time, oldBWPID, ...
                commandedBWPID, activeBWPID, controlBWPID, triggerSource, ...
                commandID, status, reasonCode)
            row = struct( ...
                "Sequence", obj.NextSequence, ...
                "Event", string(event), ...
                "CCID", obj.CCID, ...
                "Direction", string(direction), ...
                "Tick", time.tickValue(), ...
                "OldBWPID", string(oldBWPID), ...
                "CommandedBWPID", string(commandedBWPID), ...
                "ActiveBWPID", string(activeBWPID), ...
                "ControlBWPID", string(controlBWPID), ...
                "TriggerSource", string(triggerSource), ...
                "CommandID", string(commandID), ...
                "Epoch", obj.Epoch, ...
                "Status", string(status), ...
                "ReasonCode", string(reasonCode), ...
                "IndexConvention", "zero_based");
            if isempty(obj.History)
                obj.History = row;
            else
                obj.History(end + 1) = row;
            end
            obj.NextSequence = obj.NextSequence + 1;
        end
    end
end

function values = localBWPCell(input)
if iscell(input)
    values = input(:).';
elseif isa(input, "sixgr.phy.frame.BWPConfig")
    values = arrayfun(@(x) x, input(:).', "UniformOutput", false);
else
    error("sixgr:phy:frame:InvalidBWPSet", ...
        "BWPs must be BWPConfig objects or a cell array of BWPConfig objects.");
end
for index = 1:numel(values)
    if ~isa(values{index}, "sixgr.phy.frame.BWPConfig") || ...
            ~isscalar(values{index})
        error("sixgr:phy:frame:InvalidBWPSet", ...
            "Every BWP set member must be a scalar BWPConfig.");
    end
end
end

function id = localInitialActive(values, direction)
matches = false(numel(values), 1);
ids = strings(numel(values), 1);
configured = false(numel(values), 1);
for index = 1:numel(values)
    configured(index) = values{index}.Direction == direction;
    matches(index) = configured(index) && values{index}.ActiveInitial;
    ids(index) = values{index}.BWPID;
end
if ~any(configured)
    id = "";
    return;
end
if nnz(matches) ~= 1
    error("sixgr:phy:frame:InvalidInitialBWPState", ...
        "Exactly one configured %s BWP must have ActiveInitial=true.", direction);
end
id = ids(matches);
end

function value = localTime(input, label)
if ~isa(input, "sixgr.phy.frame.AbsoluteTime") || ~isscalar(input)
    error("sixgr:phy:frame:InvalidAbsoluteTime", ...
        "%s must be a scalar AbsoluteTime.", label);
end
value = input;
end

function value = localDirection(input)
value = upper(localText(input, "direction"));
if any(value == ["DOWNLINK", "D"])
    value = "DL";
elseif any(value == ["UPLINK", "U"])
    value = "UL";
end
if ~any(value == ["DL", "UL"])
    error("sixgr:phy:frame:InvalidBWPDirection", ...
        "Direction must be DL or UL.");
end
end

function value = localIdentifier(input, label)
if isnumeric(input) && isreal(input) && isscalar(input) && ...
        isfinite(double(input)) && double(input) >= 0 && ...
        double(input) == fix(double(input))
    value = string(double(input));
else
    value = localText(input, label);
end
if contains(value, "|")
    error("sixgr:phy:frame:InvalidResourceIdentifier", ...
        "%s must not contain '|'.", label);
end
end

function tf = localIdentifierPredicate(value)
try
    localIdentifier(value, "identifier");
    tf = true;
catch
    tf = false;
end
end

function value = localText(input, label)
if ~(ischar(input) || (isstring(input) && isscalar(input)))
    error("sixgr:phy:frame:InvalidTextValue", ...
        "%s must be scalar text.", label);
end
value = strtrim(string(input));
end

function tf = localTextPredicate(value)
try
    localText(value, "value");
    tf = true;
catch
    tf = false;
end
end

function value = localRequiredField(input, aliases, label)
names = string(fieldnames(input));
for alias = string(aliases(:)).'
    index = find(strcmpi(names, alias), 1);
    if ~isempty(index)
        value = input.(char(names(index)));
        return;
    end
end
error("sixgr:phy:frame:MissingGrantField", ...
    "Grant field '%s' is required.", label);
end

function value = localOptionalField(input, aliases, defaultValue)
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

function decision = localDecision(accepted, reason, commandID, direction, ...
        oldBWPID, targetBWPID, activationTime, epoch)
decision = struct( ...
    "Accepted", logical(accepted), ...
    "ReasonCode", string(reason), ...
    "CommandID", string(commandID), ...
    "Direction", string(direction), ...
    "OldBWPID", string(oldBWPID), ...
    "TargetBWPID", string(targetBWPID), ...
    "ActivationTick", activationTime.tickValue(), ...
    "Epoch", uint64(epoch));
end

function decision = localGrantDecision(allowed, reason, ccid, bwpID, ...
        direction, time, epoch)
decision = struct( ...
    "Allowed", logical(allowed), ...
    "ReasonCode", string(reason), ...
    "CCID", string(ccid), ...
    "BWPID", string(bwpID), ...
    "Direction", string(direction), ...
    "Tick", time.tickValue(), ...
    "Epoch", uint64(epoch));
end

function output = localEmptyHistoryTable()
output = table( ...
    zeros(0,1,"uint64"), strings(0,1), strings(0,1), strings(0,1), ...
    zeros(0,1,"int64"), strings(0,1), strings(0,1), strings(0,1), ...
    strings(0,1), strings(0,1), strings(0,1), zeros(0,1,"uint64"), ...
    strings(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', { ...
    'Sequence','Event','CCID','Direction','Tick','OldBWPID', ...
    'CommandedBWPID','ActiveBWPID','ControlBWPID','TriggerSource', ...
    'CommandID','Epoch','Status','ReasonCode','IndexConvention'});
end
