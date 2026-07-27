classdef RRCBoundedUPERCodec
    %RRCBOUNDEDUPERCODEC Exact minimal TS 38.331 V18.9.0 message profile.
    %
    % The enabled tuples are deliberately narrow: they reproduce the
    % independently generated pycrate V18.9.0 vectors and reject every
    % other optional-IE shape. This is not a general RRC ASN.1 codec.

    methods (Static)
        function value = available()
            value = true;
        end

        function bytes = encode(messageType, transactionID, options)
            arguments
                messageType (1,1) string
                transactionID (1,1) double = 0
                options.UEIdentity (1,1) double = hex2dec("123456789")
                options.CRNTI (1,1) double = 1
                options.PhysCellID (1,1) double = 0
                options.ResumeIdentity (1,1) double = hex2dec("123456")
            end
            if transactionID ~= floor(transactionID) || ...
                    ~ismember(transactionID, 0:3)
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "RRC transaction identifier must be in [0,3].");
            end
            messageType = string(messageType);
            switch messageType
                case "RRCSetupRequest"
                    bits = [0 0 0 1, ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.bits( ...
                        options.UEIdentity, 39), ...
                        0 1 0 0, 0];
                    bytes = sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.pack(bits);
                case "RRCReestablishmentRequest"
                    bits = [0 1 0, ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.bits( ...
                        options.CRNTI, 16), ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.bits( ...
                        options.PhysCellID, 10), zeros(1,16), 1 0, 0];
                    bytes = sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.pack(bits);
                case "RRCResumeRequest"
                    bits = [0 0 1, ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.bits( ...
                        options.ResumeIdentity, 24), ...
                        zeros(1,16), 0 1 0 0, 0];
                    bytes = sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.pack(bits);
                case "RRCSetup"
                    bytes = uint8([32 + 8*transactionID, 0, 8, 0, 0]);
                case "RRCSetupComplete"
                    bytes = uint8([16 + 2*transactionID, 0, 0, 64, 64]);
                case "SecurityModeCommand"
                    bytes = uint8([32 + 2*transactionID, 9, 16]);
                case "UECapabilityEnquiry"
                    bytes = uint8([48 + 2*transactionID, 0, 0]);
                case "MeasurementReport"
                    bytes = uint8([0, 0, 0, 0, 0]);
                otherwise
                    [channel, index] = ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.simpleIndex( ...
                        messageType);
                    if channel == ""
                        error("sixgr:rrc:ASN1ConstraintViolation", ...
                            "Message %s is outside the bounded UPER profile.", ...
                            messageType);
                    end
                    bytes = uint8([8*index + 2*transactionID, 0]);
            end
        end

        function decoded = decode(bytes, channel)
            arguments
                bytes
                channel (1,1) string
            end
            bytes = uint8(bytes(:).');
            channel = upper(channel);
            if isempty(bytes)
                error("sixgr:rrc:UPERDecodeFailed", "RRC UPER PDU is empty.");
            end
            try
                switch channel
                    case "UL-CCCH"
                        decoded = ...
                            sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.decodeULCCCH( ...
                            bytes);
                    case "DL-CCCH"
                        if numel(bytes) ~= 5 || bitshift(bytes(1), -5) ~= 1
                            error("sixgr:rrc:UPERDecodeFailed", ...
                                "Unsupported DL-CCCH bounded PDU.");
                        end
                        transactionID = bitand(bitshift(bytes(1), -3), 3);
                        decoded = struct("MessageType","RRCSetup", ...
                            "TransactionID",double(transactionID), ...
                            "Channel","DL-CCCH");
                    case {"UL-DCCH","DL-DCCH"}
                        decoded = ...
                            sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.decodeDCCH( ...
                            bytes, channel);
                    otherwise
                        error("sixgr:rrc:UPERDecodeFailed", ...
                            "Unsupported RRC logical channel %s.", channel);
                end
                expected = ...
                    sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.encode( ...
                    decoded.MessageType, decoded.TransactionID, ...
                    "UEIdentity", sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.get( ...
                    decoded, "UEIdentity", hex2dec("123456789")), ...
                    "CRNTI", sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.get( ...
                    decoded, "CRNTI", 1), ...
                    "PhysCellID", sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.get( ...
                    decoded, "PhysCellID", 0), ...
                    "ResumeIdentity", ...
                    sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.get( ...
                    decoded, "ResumeIdentity", hex2dec("123456")));
                if ~isequal(bytes, expected)
                    error("sixgr:rrc:UPERDecodeFailed", ...
                        "RRC PDU contains unsupported optional/reserved bits.");
                end
                decoded.UPERHex = upper(string(reshape( ...
                    dec2hex(bytes,2).',1,[])));
                decoded.EncodedBits = 8*numel(bytes);
                semantic = jsonencode(decoded);
                decoded.DecodedTreeSHA256 = ...
                    sixgr.protocol.ProtocolHash.bytes(semantic);
            catch exception
                if exception.identifier == "sixgr:rrc:UPERDecodeFailed"
                    rethrow(exception);
                end
                throwAsCaller(MException("sixgr:rrc:UPERDecodeFailed", ...
                    "Bounded RRC UPER decode failed: %s", exception.message));
            end
        end
    end

    methods (Static, Access = private)
        function decoded = decodeULCCCH(bytes)
            if numel(bytes) ~= 6
                error("sixgr:rrc:UPERDecodeFailed", ...
                    "Bounded UL-CCCH PDU must contain 48 bits.");
            end
            bits = sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.unpack(bytes);
            choice = sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.value(bits(2:3));
            switch choice
                case 0
                    if bits(4) ~= 1
                        error("sixgr:rrc:UPERDecodeFailed", ...
                            "Only randomValue RRCSetupRequest identity is enabled.");
                    end
                    decoded = struct("MessageType","RRCSetupRequest", ...
                        "TransactionID",0,"Channel","UL-CCCH", ...
                        "UEIdentity", ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.value( ...
                        bits(5:43)));
                case 1
                    decoded = struct("MessageType","RRCResumeRequest", ...
                        "TransactionID",0,"Channel","UL-CCCH", ...
                        "ResumeIdentity", ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.value( ...
                        bits(4:27)));
                case 2
                    decoded = struct( ...
                        "MessageType","RRCReestablishmentRequest", ...
                        "TransactionID",0,"Channel","UL-CCCH", ...
                        "CRNTI", ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.value( ...
                        bits(4:19)), ...
                        "PhysCellID", ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.value( ...
                        bits(20:29)));
                otherwise
                    error("sixgr:rrc:UPERDecodeFailed", ...
                        "Unsupported UL-CCCH c1 choice.");
            end
        end

        function decoded = decodeDCCH(bytes, channel)
            index = double(bitshift(bytes(1), -3));
            transactionID = double(bitand(bitshift(bytes(1), -1), 3));
            if channel == "UL-DCCH"
                names = ["MeasurementReport", ...
                    "RRCReconfigurationComplete","RRCSetupComplete", ...
                    "RRCReestablishmentComplete","RRCResumeComplete", ...
                    "SecurityModeComplete","","","","UECapabilityInformation"];
            else
                names = ["RRCReconfiguration","RRCResume","RRCRelease", ...
                    "RRCReestablishment","SecurityModeCommand","", ...
                    "UECapabilityEnquiry"];
            end
            if index+1 > numel(names) || strlength(names(index+1)) == 0
                error("sixgr:rrc:UPERDecodeFailed", ...
                    "Unsupported bounded DCCH c1 choice %d.", index);
            end
            messageType = names(index+1);
            if messageType == "MeasurementReport"
                transactionID = 0;
            end
            decoded = struct("MessageType",messageType, ...
                "TransactionID",transactionID,"Channel",channel);
        end

        function [channel,index] = simpleIndex(messageType)
            ul = ["MeasurementReport","RRCReconfigurationComplete", ...
                "RRCSetupComplete","RRCReestablishmentComplete", ...
                "RRCResumeComplete","SecurityModeComplete","","","", ...
                "UECapabilityInformation"];
            dl = ["RRCReconfiguration","RRCResume","RRCRelease", ...
                "RRCReestablishment","SecurityModeCommand","", ...
                "UECapabilityEnquiry"];
            found = find(ul == messageType,1);
            if ~isempty(found)
                channel = "UL-DCCH";
                index = found-1;
                return;
            end
            found = find(dl == messageType,1);
            if ~isempty(found)
                channel = "DL-DCCH";
                index = found-1;
            else
                channel = "";
                index = NaN;
            end
        end

        function bits = bits(value, count)
            if value < 0 || value >= 2^count || value ~= floor(value)
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "RRC integer does not fit in %d constrained bits.", count);
            end
            bits = bitget(uint64(value), count:-1:1);
        end

        function bytes = pack(bits)
            if mod(numel(bits),8) ~= 0
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "Bounded RRC encoder produced a non-byte-aligned PDU.");
            end
            matrix = reshape(uint8(bits),8,[]).';
            bytes = uint8(double(matrix)*double((2.^(7:-1:0)).'));
            bytes = bytes(:).';
        end

        function bits = unpack(bytes)
            positions = repmat(8:-1:1,numel(bytes),1);
            expanded = repmat(bytes(:),1,8);
            bits = reshape(bitget(expanded,positions).',1,[]);
        end

        function value = value(bits)
            value = double(bits(:).') * ...
                double((2.^(numel(bits)-1:-1:0)).');
        end

        function value = get(input, name, fallback)
            if isfield(input,name)
                value = input.(name);
            else
                value = fallback;
            end
        end
    end
end
