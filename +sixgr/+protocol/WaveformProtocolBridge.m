classdef WaveformProtocolBridge < handle
    %WAVEFORMPROTOCOLBRIDGE Bind strict protocol PDUs to waveform TB bytes.
    %
    % This object is coordinator-owned.  It is intentionally excluded from
    % parfor payloads: protocol sequence numbers and lineage are serialized
    % state, while the finalized transport-block bits are immutable worker
    % inputs.

    properties (SetAccess = private)
        Enabled (1,1) logical = false
        NumUEs (1,1) double = 0
        Configuration (1,1) struct
    end

    properties (Access = private)
        TxRuntimes cell
        RxRuntimes cell
        Pending containers.Map
        Delivered containers.Map
    end

    methods
        function obj = WaveformProtocolBridge(protocolConfig, numUEs)
            arguments
                protocolConfig (1,1) struct
                numUEs (1,1) double {mustBeInteger,mustBeNonnegative}
            end
            obj.Configuration = protocolConfig;
            obj.NumUEs = numUEs;
            obj.Enabled = logical(sixgr.util.structGet(protocolConfig, "enabled", false)) && ...
                logical(sixgr.util.structGet(protocolConfig, "strict", false));
            obj.TxRuntimes = cell(numUEs, 2);
            obj.RxRuntimes = cell(numUEs, 2);
            obj.Pending = containers.Map('KeyType','char','ValueType','any');
            obj.Delivered = containers.Map('KeyType','char','ValueType','logical');
        end

        function [tbBits, evidence] = encodeFragment(obj, ueIndex, direction, ...
                transportBlockId, fragmentId, payload, tbsBits, eventTime)
            arguments
                obj
                ueIndex (1,1) double {mustBeInteger,mustBePositive}
                direction (1,1) string
                transportBlockId (1,1) string
                fragmentId (1,1) string
                payload (1,:) uint8
                tbsBits (1,1) double {mustBeInteger,mustBePositive}
                eventTime (1,1) double {mustBeNonnegative}
            end
            obj.requireEnabled();
            direction = obj.normalizeDirection(direction);
            if mod(tbsBits, 8) ~= 0
                error("sixgr:protocol:NonByteAlignedTransportBlock", ...
                    "Same-waveform protocol integration requires a byte-aligned TBS, not %d bits.", tbsBits);
            end
            obj.requireUE(ueIndex);
            tbKey = char(transportBlockId);
            if isKey(obj.Pending, tbKey)
                error("sixgr:protocol:DuplicateTransportBlockBinding", ...
                    "Transport block %s already owns a protocol fragment.", transportBlockId);
            end

            tx = obj.runtime(ueIndex, direction, "TX");
            pdu = tx.transmit(fragmentId, payload, eventTime);
            tbsBytes = tbsBits / 8;
            mac = sixgr.l2.mac.MACPDUAssembler.assemble(direction, ...
                struct("LCID", pdu.LCID, "Payload", pdu.Bytes, ...
                "OwnerID", "RLC-" + fragmentId), tbsBytes);
            pdu.MACBytes = mac.Bytes;
            pdu.MACSHA256 = mac.SHA256;
            pdu.TBID = transportBlockId;
            pdu.TransportBlockBits = tbsBits;
            pdu.MACPaddingBytes = mac.PaddingBytes;
            pdu.ProtocolFragmentId = fragmentId;
            obj.Pending(tbKey) = pdu;

            tbBits = localBytesToBits(mac.Bytes);
            if numel(tbBits) ~= tbsBits
                error("sixgr:protocol:TransportBlockSizeMismatch", ...
                    "MAC PDU produced %d bits for a %d-bit PHY transport block.", ...
                    numel(tbBits), tbsBits);
            end
            evidence = localEvidence(pdu, payload, mac.PaddingBytes);
        end

        function [delivered, evidence] = deliverDecoded(obj, transportBlockId, ...
                decodedTransportBlockBits, eventTime)
            arguments
                obj
                transportBlockId (1,1) string
                decodedTransportBlockBits
                eventTime (1,1) double {mustBeNonnegative}
            end
            obj.requireEnabled();
            key = char(transportBlockId);
            if isKey(obj.Delivered, key)
                delivered = false;
                evidence = struct("Status", "duplicate_harq_delivery_rejected", ...
                    "TransportBlockId", transportBlockId);
                return;
            end
            if ~isKey(obj.Pending, key)
                error("sixgr:protocol:MissingTransportBlockBinding", ...
                    "Decoded transport block %s has no protocol-PDU binding.", transportBlockId);
            end
            pdu = obj.Pending(key);
            decodedMACBytes = localBitsToBytes(decodedTransportBlockBits, ...
                double(pdu.TransportBlockBits));
            decodedMACSHA256 = sixgr.l2.mac.MACHash.of(decodedMACBytes);
            if decodedMACSHA256 ~= string(pdu.MACSHA256)
                error("sixgr:protocol:DecodedTransportBlockMismatch", ...
                    ["The decoder output for transport block %s does not match " + ...
                     "the MAC PDU that entered the waveform chain."], transportBlockId);
            end
            demux = sixgr.l2.mac.MACPDUDemultiplexer.decode( ...
                string(pdu.Direction), decodedMACBytes);
            if numel(demux.SubPDUs) ~= 1 || demux.SubPDUs(1).LCID ~= pdu.LCID
                error("sixgr:protocol:DecodedTransportBlockMismatch", ...
                    "Decoded transport block %s does not contain the expected MAC SDU.", ...
                    transportBlockId);
            end
            decodedRLCBytes = uint8(demux.SubPDUs(1).Payload);
            decodedRLC_SHA256 = sixgr.protocol.ProtocolHash.bytes(decodedRLCBytes);
            if decodedRLC_SHA256 ~= string(pdu.EncodedSHA256)
                error("sixgr:protocol:DecodedTransportBlockMismatch", ...
                    "Decoded RLC PDU for transport block %s differs from the transmitted PDU.", ...
                    transportBlockId);
            end
            recoveredPDU = pdu;
            recoveredPDU.MACBytes = decodedMACBytes;
            recoveredPDU.Bytes = decodedRLCBytes;
            % ProtocolRuntime owns both Tx and Rx state for one bearer.  The
            % same bearer instance is required so delivery closes the exact
            % lineage node created during transmit.  Crucially, the bytes
            % passed to its receive side are reconstructed from the actual
            % PHY decoder output above, never from the pending Tx copy.
            rx = obj.runtime(localUEIndex(pdu), string(pdu.Direction), "TX");
            delivered = rx.receive(recoveredPDU, eventTime);
            if delivered
                obj.Delivered(key) = true;
            end
            evidence = struct("Status", localDeliveryStatus(delivered), ...
                "TransportBlockId", transportBlockId, ...
                "ProtocolFragmentId", string(pdu.ProtocolFragmentId), ...
                "PacketId", string(pdu.PacketID), ...
                "MACSHA256", string(pdu.MACSHA256), ...
                "DecodedMACSHA256", string(decodedMACSHA256), ...
                "EncodedRLC_SHA256", string(pdu.EncodedSHA256), ...
                "DecodedRLC_SHA256", string(decodedRLC_SHA256), ...
                "PayloadSHA256", string(pdu.PacketSHA256), ...
                "DecodedBitCount", double(numel(decodedTransportBlockBits)), ...
                "DecodedBitExact", true, ...
                "EvidenceSource", "actual_phy_decoder_bits_demuxed_through_strict_mac_rlc_pdcp_sdap");
        end

        function bytes = maximumPayloadBytes(obj, tbsBits)
            arguments
                obj
                tbsBits (1,1) double {mustBeInteger,mustBePositive}
            end
            obj.requireEnabled();
            if mod(tbsBits, 8) ~= 0
                bytes = 0;
                return;
            end
            pdcpSNBits = double(sixgr.util.structGet(obj.Configuration, "pdcp.sn_bits", NaN));
            rlcSNBits = double(sixgr.util.structGet(obj.Configuration, "rlc.sn_bits", NaN));
            if ~ismember(pdcpSNBits, [12 18]) || ~ismember(rlcSNBits, [12 18])
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Waveform protocol binding requires explicit 12- or 18-bit PDCP/RLC SN lengths.");
            end
            fixedHeaders = 1 + (2 + double(pdcpSNBits == 18)) + ...
                (2 + double(rlcSNBits == 18));
            tbsBytes = tbsBits / 8;
            bytes = max(0, tbsBytes - fixedHeaders - 3);
            if bytes + fixedHeaders <= 255
                bytes = min(tbsBytes - fixedHeaders - 2, bytes + 1);
            end
            bytes = max(0, floor(bytes));
        end
    end

    methods (Access = private)
        function runtime = runtime(obj, ueIndex, direction, endpoint)
            col = 1 + double(direction == "UL");
            if endpoint == "TX"
                bank = obj.TxRuntimes;
            else
                bank = obj.RxRuntimes;
            end
            runtime = bank{ueIndex, col};
            if isempty(runtime)
                runtime = sixgr.protocol.ProtocolRuntime( ...
                    localRuntimeConfig(obj.Configuration, ueIndex, direction));
                if endpoint == "TX"
                    obj.TxRuntimes{ueIndex, col} = runtime;
                else
                    obj.RxRuntimes{ueIndex, col} = runtime;
                end
            end
        end

        function requireEnabled(obj)
            if ~obj.Enabled
                error("sixgr:protocol:WaveformProtocolBridgeDisabled", ...
                    "Same-waveform protocol bridge is not enabled by strict protocol YAML configuration.");
            end
        end

        function requireUE(obj, ueIndex)
            if ueIndex > obj.NumUEs
                error("sixgr:protocol:InvalidUEIndex", ...
                    "Protocol UE index %d exceeds configured UE count %d.", ueIndex, obj.NumUEs);
            end
        end
    end

    methods (Static, Access = private)
        function value = normalizeDirection(value)
            value = upper(strtrim(string(value)));
            if ~any(value == ["DL","UL"])
                error("sixgr:protocol:UnsupportedDirection", ...
                    "Protocol waveform direction must be DL or UL.");
            end
        end
    end
end

function config = localRuntimeConfig(protocol, ueIndex, direction)
sessions = localStructArray(sixgr.util.structGet(protocol, "traffic.sessions", struct()));
if isempty(sessions)
    error("sixgr:protocol:MissingTrafficSession", ...
        "Same-waveform protocol execution requires protocol.traffic.sessions.");
end
match = false(numel(sessions),1);
for i = 1:numel(sessions)
    configured = upper(string(sixgr.util.structGet(sessions(i), "direction", "")));
    match(i) = configured == direction || configured == "BIDIR";
end
idx = find(match, 1, "first");
if isempty(idx)
    error("sixgr:protocol:MissingTrafficSession", ...
        "No configured protocol traffic session carries %s.", direction);
end
session = sessions(idx);
qfi = double(sixgr.util.structGet(session, "qfi", NaN));
mappings = localStructArray(sixgr.util.structGet(protocol, "sdap.qfi_to_drb", struct()));
drb = NaN;
for i = 1:numel(mappings)
    if double(sixgr.util.structGet(mappings(i), "qfi", NaN)) == qfi
        drb = double(sixgr.util.structGet(mappings(i), "drb_id", NaN));
        break;
    end
end
pdcp = sixgr.util.structGet(protocol, "pdcp", struct());
rlc = sixgr.util.structGet(protocol, "rlc", struct());
config = struct( ...
    "UEID", "UE-" + compose("%03d", ueIndex), ...
    "BearerID", "DRB-" + string(drb), ...
    "Direction", direction, "QFI", qfi, "DRBID", drb, ...
    "PduSessionID", double(sixgr.util.structGet(session, "pdu_session_id", ...
        sixgr.util.structGet(protocol, "sdap.pdu_session_id", NaN))), ...
    "LCID", double(sixgr.util.structGet(protocol, "mac.lcid", NaN)), ...
    "PDCPSNBits", double(sixgr.util.structGet(pdcp, "sn_bits", NaN)), ...
    "RLCSNBits", double(sixgr.util.structGet(rlc, "sn_bits", NaN)), ...
    "ConfigurationEpoch", double(sixgr.util.structGet(protocol, "configuration_epoch", NaN)), ...
    "CipherAlgorithm", string(sixgr.util.structGet(pdcp, "cipher_algorithm", "")), ...
    "IntegrityAlgorithm", string(sixgr.util.structGet(pdcp, "integrity_algorithm", "")), ...
    "PollPDU", double(sixgr.util.structGet(rlc, "poll_pdu", NaN)), ...
    "PollByte", double(sixgr.util.structGet(rlc, "poll_byte", NaN)), ...
    "MaxRetxThreshold", double(sixgr.util.structGet(rlc, "max_retx_threshold", NaN)));
config.SecurityActive = config.CipherAlgorithm ~= "NEA0" || ...
    config.IntegrityAlgorithm ~= "NIA0";
end

function values = localStructArray(value)
if isempty(value)
    values = repmat(struct(),0,1);
elseif iscell(value)
    values = [value{:}];
elseif isstruct(value)
    values = value(:);
else
    error("sixgr:protocol:UnsupportedCapability", ...
        "Protocol session/mapping configuration must be a struct array.");
end
end

function bits = localBytesToBits(bytes)
bytes = uint8(bytes(:));
matrix = false(numel(bytes), 8);
for bitIndex = 1:8
    matrix(:,bitIndex) = logical(bitget(bytes, 9 - bitIndex));
end
bits = int8(reshape(matrix.', [], 1));
end

function bytes = localBitsToBytes(bits, expectedBitCount)
bits = double(bits(:));
if numel(bits) ~= expectedBitCount
    error("sixgr:protocol:DecodedTransportBlockLengthMismatch", ...
        "PHY decoder returned %d bits for a %d-bit protocol transport block.", ...
        numel(bits), expectedBitCount);
end
if mod(numel(bits), 8) ~= 0 || any(~isfinite(bits)) || ...
        any(bits ~= 0 & bits ~= 1)
    error("sixgr:protocol:InvalidDecodedTransportBlockBits", ...
        "Decoded protocol transport-block data must be a byte-aligned binary vector.");
end
weights = 2.^(7:-1:0);
bytes = uint8(reshape(bits, 8, []).' * weights.');
bytes = bytes(:).';
end

function evidence = localEvidence(pdu, payload, paddingBytes)
evidence = struct( ...
    "ProtocolFragmentId", string(pdu.ProtocolFragmentId), ...
    "PacketId", string(pdu.PacketID), ...
    "PayloadBits", double(numel(payload) * 8), ...
    "PayloadSHA256", string(pdu.PacketSHA256), ...
    "SDAPHeaderHex", localHex(pdu.SDAPHeader), ...
    "PDCPHeaderHex", localHex(pdu.PDCPHeader), ...
    "RLCHeaderHex", localHex(pdu.RLCHeader), ...
    "EncodedRLC_SHA256", string(pdu.EncodedSHA256), ...
    "MACSHA256", string(pdu.MACSHA256), ...
    "MACPDUBytes", double(numel(pdu.MACBytes)), ...
    "MACPaddingBytes", double(paddingBytes), ...
    "SameWaveformPayloadTruth", true, ...
    "EvidenceSource", "strict_sdap_pdcp_rlc_mac_bytes_bound_to_phy_transport_block");
end

function value = localHex(bytes)
bytes = uint8(bytes(:));
if isempty(bytes)
    value = "";
else
    value = lower(join(compose("%02X", bytes), ""));
end
end

function idx = localUEIndex(pdu)
token = regexp(char(string(pdu.PacketID)), 'UE-(\d+)', 'tokens', 'once');
if isempty(token)
    error("sixgr:protocol:LineageViolation", ...
        "Protocol packet identity does not contain a UE index.");
end
idx = str2double(token{1});
end

function value = localDeliveryStatus(delivered)
if delivered
    value = "delivered_after_exact_phy_decode";
else
    value = "protocol_duplicate_or_reordering_rejected";
end
end
