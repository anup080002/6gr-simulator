function out = runConfiguredProtocolComponentValidation(cfg, runFolder, options)
%RUNCONFIGUREDPROTOCOLCOMPONENTVALIDATION Execute configured DL/UL L2 entities.
% This is strict component evidence.  It deliberately does not claim that
% these protocol PDUs were the payload of the retained PHY waveform trials.

arguments
    cfg (1,1) struct
    runFolder (1,1) string
    options.RunId (1,1) string = ""
    options.ScenarioName (1,1) string = ""
    options.WriteArtifacts (1,1) logical = true
end

protocol = sixgr.util.structGet(cfg, "protocol", struct());
if ~(isstruct(protocol) && logical(sixgr.util.structGet(protocol, "enabled", false)))
    error("sixgr:protocol:ConfiguredComponentDisabled", ...
        "Configured protocol component validation requires protocol.enabled=true.");
end
if ~logical(sixgr.util.structGet(protocol, "strict", false))
    error("sixgr:protocol:ConfiguredComponentNotStrict", ...
        "Configured protocol component validation requires protocol.strict=true.");
end
campaign = sixgr.util.structGet(protocol, "component_validation", struct());
if ~logical(sixgr.util.structGet(campaign, "enabled", false))
    error("sixgr:protocol:ConfiguredComponentDisabled", ...
        "protocol.component_validation.enabled must be true.");
end

sessions = localStructArray(sixgr.util.structGet(protocol, ...
    "traffic.sessions", struct()));
if isempty(sessions)
    error("sixgr:protocol:MissingTrafficSession", ...
        "At least one configured protocol traffic session is required.");
end
numUEs = localPositiveInteger(localFirst(cfg, ...
    ["scenario.ue.nUE","scenario.nUE", ...
    "deployment.numUEs","deployment_topology.num_ues", ...
    "users.nUsers","lls6g.users.nUsers"], []), ...
    "configured UE count");
packetCount = localPositiveInteger(sixgr.util.structGet(campaign, ...
    "packets_per_ue_direction", []), ...
    "protocol.component_validation.packets_per_ue_direction");
duplicateCheck = logical(sixgr.util.structGet(campaign, ...
    "duplicate_reception_check_enabled", false));
requireBidir = logical(sixgr.util.structGet(campaign, ...
    "require_configured_bidirectional_execution", false));
lcid = localPositiveInteger(sixgr.util.structGet(protocol, ...
    "mac.lcid", []), "protocol.mac.lcid");
if lcid > 32
    error("sixgr:protocol:InvalidLCID", ...
        "protocol.mac.lcid must be in [1, 32].");
end

executionRows = repmat(localExecutionRow(), 0, 1);
conservationRows = repmat(localConservationRow(), 0, 1);
eventTables = cell(0, 1);
runtimeCount = 0;
for sessionIndex = 1:numel(sessions)
    session = sessions(sessionIndex);
    directions = localDirections(sixgr.util.structGet(session, ...
        "direction", sixgr.util.structGet(cfg, "traffic.flowDirection", "")));
    flowId = string(sixgr.util.structGet(session, "flow_id", ...
        "flow-" + string(sessionIndex)));
    qfi = localPositiveInteger(sixgr.util.structGet(session, "qfi", ...
        sixgr.util.structGet(protocol, "sdap.qfi_to_drb.qfi", [])), ...
        "protocol traffic QFI");
    drbId = localResolveDRB(protocol, qfi);
    pduSessionId = localPositiveInteger(sixgr.util.structGet(session, ...
        "pdu_session_id", sixgr.util.structGet(protocol, ...
        "sdap.pdu_session_id", [])), "protocol PDU session ID");
    packetBytes = localPositiveInteger(sixgr.util.structGet(session, ...
        "packet_bytes", []), "protocol traffic packet_bytes");
    for direction = directions(:).'
        for ueIndex = 1:numUEs
            runtimeCount = runtimeCount + 1;
            ueId = "UE-" + compose("%03d", ueIndex);
            runtimeConfig = localRuntimeConfig(protocol, ueId, direction, ...
                qfi, drbId, pduSessionId, lcid);
            runtime = sixgr.protocol.ProtocolRuntime(runtimeConfig);
            for packetIndex = 1:packetCount
                packetId = flowId + "-" + direction + "-" + ueId + ...
                    "-" + compose("%04d", packetIndex);
                payload = localPayload(packetBytes, sessionIndex, ...
                    ueIndex, direction, packetIndex);
                eventTime = double(packetIndex);
                pdu = runtime.transmit(packetId, payload, eventTime);
                delivered = runtime.receive(pdu, eventTime + 0.25);
                duplicateRejected = true;
                if duplicateCheck
                    duplicateRejected = ~runtime.receive(pdu, eventTime + 0.50);
                end
                row = localExecutionRow();
                row.RunId = options.RunId;
                row.ScenarioName = options.ScenarioName;
                row.FlowId = flowId;
                row.UEId = ueId;
                row.UEIndex = ueIndex;
                row.Direction = direction;
                row.PacketId = packetId;
                row.QFI = qfi;
                row.DRBId = drbId;
                row.PduSessionId = pduSessionId;
                row.LCID = lcid;
                row.PayloadBytes = packetBytes;
                row.PayloadSHA256 = string(pdu.PacketSHA256);
                row.RLCPDUSHA256 = string(pdu.EncodedSHA256);
                row.MACTBSHA256 = string(pdu.MACSHA256);
                row.Delivered = logical(delivered);
                row.DuplicateCheckEnabled = duplicateCheck;
                row.DuplicateRejected = logical(duplicateRejected);
                row.EvidenceClassification = ...
                    "strict_component_execution_not_same_waveform_payload_truth";
                row.SameWaveformPayloadIntegration = false;
                row.CountsTowardWaveformTruth = false;
                row.ProxyUsed = false;
                row.FallbackUsed = false;
                row.Status = "PASS";
                if ~row.Delivered || ~row.DuplicateRejected
                    row.Status = "FAIL";
                end
                executionRows(end + 1, 1) = row; %#ok<AGROW>
            end
            conservation = runtime.conservation();
            sixgr.protocol.ProtocolInvariantGuard.requireConservation(conservation);
            cRow = localConservationRow();
            cRow.RunId = options.RunId;
            cRow.FlowId = flowId;
            cRow.UEId = ueId;
            cRow.Direction = direction;
            names = string(fieldnames(conservation));
            for name = names(:).'
                cRow.(char(name)) = double(conservation.(char(name)));
            end
            cRow.Status = "PASS";
            conservationRows(end + 1, 1) = cRow; %#ok<AGROW>
            eventT = runtime.Events.toTable(options.RunId);
            eventT = addvars(eventT, repmat(flowId, height(eventT), 1), ...
                repmat(direction, height(eventT), 1), ...
                'After', 'RunID', 'NewVariableNames', {'FlowId','Direction'});
            eventTables{end + 1, 1} = eventT; %#ok<AGROW>
        end
    end
end

executionT = struct2table(executionRows, "AsArray", true);
conservationT = struct2table(conservationRows, "AsArray", true);
eventT = localVertcatTables(eventTables);
configuredDirections = unique(executionT.Direction, "stable");
bidirOk = ~requireBidir || all(ismember(["DL","UL"], configuredDirections));
strictOk = ~isempty(executionT) && all(executionT.Status == "PASS") && ...
    all(conservationT.EquationErrorBytes == 0) && bidirOk;

summaryT = table(options.RunId, options.ScenarioName, numUEs, ...
    numel(sessions), runtimeCount, height(executionT), ...
    sum(executionT.Direction == "DL"), sum(executionT.Direction == "UL"), ...
    bidirOk, strictOk, false, false, ...
    "strict_component_execution_not_same_waveform_payload_truth", ...
    'VariableNames', {'RunId','ScenarioName','ConfiguredUECount', ...
    'ConfiguredSessionCount','ExecutedRuntimeCount','ExecutedPacketCount', ...
    'DLPacketCount','ULPacketCount','ConfiguredBidirectionalExecutionOk', ...
    'StrictComponentOk','SameWaveformPayloadIntegration', ...
    'CountsTowardWaveformTruth','EvidenceClassification'});

paths = struct();
if options.WriteArtifacts
    csvDir = fullfile(runFolder, "protocol_stack", "csv");
    imageDir = fullfile(runFolder, "protocol_stack", "image");
    if ~isfolder(csvDir), mkdir(csvDir); end
    if ~isfolder(imageDir), mkdir(imageDir); end
    paths.Execution = string(fullfile(csvDir, ...
        "protocol_configured_component_execution.csv"));
    paths.Conservation = string(fullfile(csvDir, ...
        "protocol_configured_conservation.csv"));
    paths.Events = string(fullfile(csvDir, ...
        "protocol_configured_event_log.csv"));
    paths.Summary = string(fullfile(csvDir, ...
        "protocol_configured_component_summary.csv"));
    sixgr.util.csvWriteTable(paths.Execution, executionT);
    sixgr.util.csvWriteTable(paths.Conservation, conservationT);
    sixgr.util.csvWriteTable(paths.Events, eventT);
    sixgr.util.csvWriteTable(paths.Summary, summaryT);
    if logical(sixgr.util.structGet(campaign, "write_png", false))
        resolution = double(sixgr.util.structGet(campaign, ...
            "png_resolution_dpi", []));
        if ~(isscalar(resolution) && isfinite(resolution) && ...
                resolution >= 72 && resolution <= 1200)
            error("sixgr:protocol:InvalidRasterResolution", ...
                "protocol.component_validation.png_resolution_dpi must be in [72, 1200].");
        end
        paths.PacketFigure = string(fullfile(imageDir, ...
            "protocol_configured_packets_by_direction.png"));
        paths.EventFigure = string(fullfile(imageDir, ...
            "protocol_configured_events_by_layer.png"));
        localRenderPacketFigure(executionT, paths.PacketFigure, resolution);
        localRenderEventFigure(eventT, paths.EventFigure, resolution);
    end
end

out = struct("Ok", strictOk, "StrictOk", strictOk, ...
    "FailureReason", "", "SummaryTable", summaryT, ...
    "ArtifactTables", struct("execution", executionT, ...
    "conservation", conservationT, "events", eventT, "summary", summaryT), ...
    "ArtifactPaths", paths, ...
    "EvidenceClassification", ...
    "strict_component_execution_not_same_waveform_payload_truth", ...
    "SameWaveformPayloadIntegration", false, ...
    "CountsTowardWaveformTruth", false, ...
    "ProxyUsed", false, "FallbackUsed", false);
if ~strictOk
    out.FailureReason = "configured_protocol_component_execution_failed";
end
end

function config = localRuntimeConfig(protocol, ueId, direction, qfi, drbId, pduSessionId, lcid)
pdcp = sixgr.util.structGet(protocol, "pdcp", struct());
rlc = sixgr.util.structGet(protocol, "rlc", struct());
config = struct( ...
    "UEID", ueId, ...
    "BearerID", "DRB-" + string(drbId), ...
    "Direction", direction, ...
    "QFI", qfi, ...
    "DRBID", drbId, ...
    "PduSessionID", pduSessionId, ...
    "LCID", lcid, ...
    "PDCPSNBits", double(sixgr.util.structGet(pdcp, "sn_bits", [])), ...
    "RLCSNBits", double(sixgr.util.structGet(rlc, "sn_bits", [])), ...
    "ConfigurationEpoch", double(sixgr.util.structGet(protocol, ...
    "configuration_epoch", [])), ...
    "CipherAlgorithm", string(sixgr.util.structGet(pdcp, ...
    "cipher_algorithm", "")), ...
    "IntegrityAlgorithm", string(sixgr.util.structGet(pdcp, ...
    "integrity_algorithm", "")), ...
    "PollPDU", double(sixgr.util.structGet(rlc, "poll_pdu", [])), ...
    "PollByte", double(sixgr.util.structGet(rlc, "poll_byte", [])), ...
    "MaxRetxThreshold", double(sixgr.util.structGet(rlc, ...
    "max_retx_threshold", [])));
securityActive = config.CipherAlgorithm ~= "NEA0" || ...
    config.IntegrityAlgorithm ~= "NIA0";
config.SecurityActive = securityActive;
if securityActive
    config.CipherKey = localHexKey(sixgr.util.structGet(pdcp, ...
        "cipher_key_hex", ""), "protocol.pdcp.cipher_key_hex");
    config.IntegrityKey = localHexKey(sixgr.util.structGet(pdcp, ...
        "integrity_key_hex", ""), "protocol.pdcp.integrity_key_hex");
end
end

function bytes = localPayload(packetBytes, sessionIndex, ueIndex, direction, packetIndex)
directionOffset = 0;
if direction == "DL"
    directionOffset = 97;
end
offset = 31 * sessionIndex + 17 * ueIndex + directionOffset + packetIndex;
bytes = uint8(mod((0:(packetBytes - 1)) + offset, 256));
end

function directions = localDirections(value)
direction = upper(strtrim(string(value)));
switch direction
    case "BIDIR"
        directions = ["DL","UL"];
    case {"DL","UL"}
        directions = direction;
    otherwise
        error("sixgr:protocol:UnsupportedDirection", ...
            "Configured protocol traffic direction must be DL, UL, or BIDIR, not '%s'.", ...
            direction);
end
end

function drbId = localResolveDRB(protocol, qfi)
mapping = localStructArray(sixgr.util.structGet(protocol, ...
    "sdap.qfi_to_drb", struct()));
drbId = [];
for index = 1:numel(mapping)
    if double(sixgr.util.structGet(mapping(index), "qfi", NaN)) == qfi
        drbId = sixgr.util.structGet(mapping(index), "drb_id", []);
        break;
    end
end
if isempty(drbId)
    drbId = sixgr.util.structGet(protocol, "sdap.default_drb_id", []);
end
drbId = localPositiveInteger(drbId, "configured SDAP DRB ID");
end

function value = localFirst(cfg, paths, defaultValue)
value = defaultValue;
for path = paths(:).'
    candidate = sixgr.util.structGet(cfg, path, []);
    if ~isempty(candidate)
        value = candidate;
        return;
    end
end
end

function value = localPositiveInteger(value, label)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= 1 && value == fix(value))
    error("sixgr:protocol:InvalidConfiguredValue", ...
        "%s must be an explicitly configured positive integer.", label);
end
end

function values = localStructArray(value)
if iscell(value)
    if isempty(value)
        values = struct.empty;
    else
        values = [value{:}];
    end
elseif isstruct(value)
    values = value;
else
    values = struct.empty;
end
end

function key = localHexKey(value, label)
text = char(strtrim(string(value)));
if numel(text) ~= 32 || any(~ismember(lower(text), ['0':'9','a':'f']))
    error("sixgr:protocol:InvalidSecurityKey", ...
        "%s must contain exactly 32 hexadecimal characters.", label);
end
key = uint8(sscanf(text, '%2x').');
end

function T = localVertcatTables(tables)
if isempty(tables)
    T = table();
    return;
end
T = tables{1};
for index = 2:numel(tables)
    T = [T; tables{index}]; %#ok<AGROW>
end
end

function localRenderPacketFigure(T, path, resolution)
directions = ["DL","UL"];
transmitted = arrayfun(@(d)sum(T.Direction == d), directions);
delivered = arrayfun(@(d)sum(T.Direction == d & T.Delivered), directions);
fig = figure("Visible", "off", "Color", "white", ...
    "Position", [100 100 900 520]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
bar([transmitted(:), delivered(:)], "grouped");
set(gca, "XTick", 1:2, "XTickLabel", cellstr(directions));
ylabel("Packets"); xlabel("Direction");
title("Configured L2 packet execution by direction");
legend("Transmitted", "Delivered", "Location", "best");
grid on;
sixgr.util.exportFigureArtifact(fig, path, "Resolution", resolution);
end

function localRenderEventFigure(T, path, resolution)
layers = unique(T.Layer, "stable");
counts = arrayfun(@(layer)sum(T.Layer == layer), layers);
fig = figure("Visible", "off", "Color", "white", ...
    "Position", [100 100 1000 520]);
cleanup = onCleanup(@() close(fig)); %#ok<NASGU>
bar(counts);
set(gca, "XTick", 1:numel(layers), "XTickLabel", cellstr(layers));
ylabel("Events"); xlabel("Protocol layer");
title("Configured SDAP/PDCP/RLC/MAC event evidence");
grid on;
sixgr.util.exportFigureArtifact(fig, path, "Resolution", resolution);
end

function row = localExecutionRow()
row = struct("RunId","", "ScenarioName","", "FlowId","", ...
    "UEId","", "UEIndex",NaN, "Direction","", "PacketId","", ...
    "QFI",NaN, "DRBId",NaN, "PduSessionId",NaN, "LCID",NaN, ...
    "PayloadBytes",NaN, "PayloadSHA256","", "RLCPDUSHA256","", ...
    "MACTBSHA256","", "Delivered",false, ...
    "DuplicateCheckEnabled",false, "DuplicateRejected",false, ...
    "EvidenceClassification","", "SameWaveformPayloadIntegration",false, ...
    "CountsTowardWaveformTruth",false, "ProxyUsed",false, ...
    "FallbackUsed",false, "Status","");
end

function row = localConservationRow()
row = struct("RunId","", "FlowId","", "UEId","", "Direction","", ...
    "ArrivedBytes",0, "QueuedBytes",0, "InFlightBytes",0, ...
    "DeliveredBytes",0, "DroppedBytes",0, "UnownedBytes",0, ...
    "DuplicateDeliveredBytes",0, "EquationErrorBytes",0, "Status","");
end
