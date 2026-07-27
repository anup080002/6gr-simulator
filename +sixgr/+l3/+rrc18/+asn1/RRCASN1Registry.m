classdef RRCASN1Registry
    %RRCASN1REGISTRY Fail-closed registry for independent R18 UPER vectors.
    %
    % Enabled tuples must exist in both the declared message catalog and
    % the independently generated TS 38.331 V18.9.0 frozen-vector file.
    % Missing tuples are rejected before procedure state can mutate.

    properties (SetAccess = immutable)
        VectorRoot (1,1) string
        Rows table
        FrozenRows table
        VectorSHA256 (1,1) string
    end

    methods
        function obj = RRCASN1Registry(vectorRoot)
            arguments
                vectorRoot (1,1) string
            end
            path = fullfile(vectorRoot, "protocol_rrc_message_vectors.csv");
            if ~isfile(path)
                error("sixgr:rrc:UPERDecodeFailed", ...
                    "Independent RRC UPER vector catalog is missing.");
            end
            obj.VectorRoot = vectorRoot;
            obj.Rows = sixgr.l3.rrc18.asn1.RRCASN1Registry.readStrings(path);
            frozenPath = fullfile(vectorRoot, ...
                "protocol_rrc_release18_uper_vectors.csv");
            if isfile(frozenPath)
                obj.FrozenRows = ...
                    sixgr.l3.rrc18.asn1.RRCASN1Registry.readStrings(frozenPath);
            else
                obj.FrozenRows = table();
            end
            obj.VectorSHA256 = sixgr.protocol.ProtocolHash.file(path);
        end

        function requireEnabled(obj, messageType, transactionID)
            arguments
                obj
                messageType (1,1) string
                transactionID (1,1) double
            end
            match = obj.Rows.MessageType == messageType & ...
                str2double(obj.Rows.TransactionID) == transactionID & ...
                lower(obj.Rows.ExpectedValid) == "true";
            if ~any(match)
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "RRC message tuple %s/%d is not declared valid.", ...
                    messageType, transactionID);
            end
            sourceRows = obj.Rows(match,:);
            key = sourceRows.CaseID + "|" + sourceRows.MessageType + "|" + ...
                sourceRows.TransactionID;
            if isempty(obj.FrozenRows)
                frozen = false(size(key));
            else
                frozenKeys = obj.FrozenRows.CaseID + "|" + ...
                    obj.FrozenRows.MessageType + "|" + ...
                    obj.FrozenRows.TransactionID;
                frozen = ismember(key, frozenKeys);
            end
            if ~all(frozen)
                error("sixgr:protocol:UnsupportedCapability", ...
                    "%s/%d requires an independent Release-18 frozen UPER vector.", ...
                    messageType, transactionID);
            end
        end

        function decoded = decode(obj, messageType, transactionID, bits, decoder)
            arguments
                obj
                messageType (1,1) string
                transactionID (1,1) double
                bits
                decoder = []
            end
            obj.requireEnabled(messageType, transactionID);
            try
                if isempty(decoder)
                    channel = obj.FrozenRows.Channel( ...
                        obj.FrozenRows.MessageType == messageType & ...
                        str2double(obj.FrozenRows.TransactionID) == ...
                        transactionID);
                    channel = unique(channel);
                    if numel(channel) ~= 1
                        error("sixgr:rrc:UPERDecodeFailed", ...
                            "Frozen RRC channel binding is ambiguous.");
                    end
                    decoded = ...
                        sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.decode( ...
                        bits, channel);
                elseif isa(decoder, "function_handle")
                    decoded = decoder(uint8(bits(:)));
                else
                    error("sixgr:rrc:UPERDecodeFailed", ...
                        "External UPER decoder must be a function handle.");
                end
            catch exception
                throwAsCaller(MException("sixgr:rrc:UPERDecodeFailed", ...
                    "Independent UPER decoder failed: %s", exception.message));
            end
        end

        function rejectNonUPER(~, payload)
            if ischar(payload) || isstring(payload) || isstruct(payload)
                error("sixgr:rrc:UPERDecodeFailed", ...
                    "Strict RRC wire input must be ASN.1 UPER bits.");
            end
        end
    end

    methods (Static, Access = private)
        function value = readStrings(path)
            options = detectImportOptions(path, "Delimiter", ",", ...
                "VariableNamingRule", "preserve");
            options = setvartype(options, options.VariableNames, "string");
            value = readtable(path, options);
        end
    end
end
