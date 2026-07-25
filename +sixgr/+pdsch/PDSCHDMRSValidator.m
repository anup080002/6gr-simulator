classdef PDSCHDMRSValidator
    %PDSCHDMRSVALIDATOR Validate PDSCH DM-RS tables without mutation.
    %
    % All symbols and logical DM-RS ports are zero based.  The symbol
    % locations are the selected Release-18 table entries used by the
    % frozen Prompt-02 vectors.  Invalid entries fail before a Toolbox
    % configuration or waveform object is created.

    methods (Static)
        function result = validateConfiguration(config)
            if ~isstruct(config) || ~isscalar(config)
                error("sixgr:pdsch:InvalidDMRSConfiguration", ...
                    "PDSCH DM-RS configuration must be a scalar struct.");
            end
            original = config;
            required = [ ...
                "MappingType","DMRSLength","PDSCHStartSymbol", ...
                "PDSCHDurationLd","DMRSTypeAPosition", ...
                "DMRSAdditionalPosition","DMRSConfigurationType", ...
                "DMRSMultiplexing","DMRSPortSet"];
            missing = required(~isfield(config, required));
            if ~isempty(missing)
                error("sixgr:pdsch:IncompleteDMRSConfiguration", ...
                    "PDSCH DM-RS configuration is missing: %s.", ...
                    strjoin(cellstr(missing), ", "));
            end

            symbols = sixgr.pdsch.PDSCHDMRSValidator. ...
                resolveSymbolPositions( ...
                config.MappingType, config.DMRSLength, ...
                config.PDSCHStartSymbol, config.PDSCHDurationLd, ...
                config.DMRSTypeAPosition, config.DMRSAdditionalPosition);

            numLayers = [];
            if isfield(config, "NumLayers")
                numLayers = config.NumLayers;
            end
            numCDMGroups = [];
            if isfield(config, "NumCDMGroupsWithoutData")
                numCDMGroups = config.NumCDMGroupsWithoutData;
            end
            ports = sixgr.pdsch.PDSCHDMRSValidator.resolvePortSet( ...
                config.DMRSConfigurationType, config.DMRSLength, ...
                config.DMRSMultiplexing, config.DMRSPortSet, ...
                "NumLayers", numLayers, ...
                "NumCDMGroupsWithoutData", numCDMGroups);

            if isfield(config, "NIDNSCID")
                sixgr.pdsch.PDSCHDMRSValidator.validateNIDNSCID( ...
                    config.NIDNSCID);
            end
            if isfield(config, "NSCID")
                sixgr.pdsch.PDSCHDMRSValidator.validateNSCID(config.NSCID);
            end

            result = struct( ...
                "SymbolPositions", double(symbols(:).'), ...
                "SymbolCount", numel(symbols), ...
                "Ports", ports, ...
                "LogicalPortSet", double(config.DMRSPortSet(:).'), ...
                "OriginalUnchanged", isequaln(original, config), ...
                "IndexBase", "zero_based");
        end

        function symbols = resolveSymbolPositions(mappingType, dmrsLength, ...
                pdschStartSymbol, pdschDurationLd, dmrsTypeAPosition, ...
                dmrsAdditionalPosition)
            mappingType = upper(strtrim(string(mappingType)));
            if ~isscalar(mappingType) || ...
                    ~any(mappingType == ["A","B"])
                error("sixgr:pdsch:InvalidDMRSMappingType", ...
                    "PDSCH DM-RS mapping type must be A or B.");
            end
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                dmrsLength, 1, 2, "InvalidDMRSLength", ...
                "DMRSLength must be 1 or 2.");
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                pdschStartSymbol, 0, 13, "InvalidPDSCHSymbolAllocation", ...
                "PDSCHStartSymbol must be a zero-based slot symbol.");
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                pdschDurationLd, 1, 14, "InvalidPDSCHSymbolAllocation", ...
                "PDSCHDurationLd must be in the range 1...14.");
            if pdschStartSymbol + pdschDurationLd > 14
                error("sixgr:pdsch:InvalidPDSCHSymbolAllocation", ...
                    "The PDSCH symbol allocation extends beyond the slot.");
            end
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                dmrsTypeAPosition, 2, 3, "InvalidDMRSTypeAPosition", ...
                "DMRSTypeAPosition must be 2 or 3.");
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                dmrsAdditionalPosition, 0, 3, ...
                "UnsupportedDMRSPositionCombination", ...
                "DMRSAdditionalPosition must be in the range 0...3.");

            % TS 38.211 l_d is the allocation end relative to the slot for
            % mapping type A, and the allocation duration for mapping B.
            tableLd = pdschDurationLd;
            if mappingType == "A"
                tableLd = pdschStartSymbol + pdschDurationLd;
            end
            row = sixgr.pdsch.PDSCHDMRSValidator.positionTableRow( ...
                mappingType, dmrsLength, tableLd);
            column = dmrsAdditionalPosition + 1;
            if isempty(row) || column > numel(row) || isempty(row{column})
                error("sixgr:pdsch:UnsupportedDMRSPositionCombination", ...
                    "The selected mapping type, length, allocation duration, " + ...
                    "type-A position, and additional-position combination " + ...
                    "has no DM-RS table entry.");
            end

            raw = double(row{column});
            symbols = zeros(size(raw));
            for i = 1:numel(raw)
                if raw(i) == -1
                    if mappingType == "A"
                        symbols(i) = dmrsTypeAPosition;
                    else
                        symbols(i) = pdschStartSymbol;
                    end
                elseif raw(i) == -2
                    symbols(i) = 11;
                elseif mappingType == "A"
                    symbols(i) = raw(i);
                else
                    symbols(i) = pdschStartSymbol + raw(i);
                end
            end
            if dmrsLength == 2
                symbols = reshape([symbols; symbols + 1], 1, []);
            end

            allocationEnd = pdschStartSymbol + pdschDurationLd;
            if any(symbols < pdschStartSymbol | symbols >= allocationEnd)
                error("sixgr:pdsch:UnsupportedDMRSPositionCombination", ...
                    "The selected DM-RS symbols do not lie wholly inside " + ...
                    "the PDSCH symbol allocation.");
            end
            symbols = double(symbols(:).');
        end

        function portInfo = resolvePort(configType, dmrsLength, ...
                multiplexing, logicalPort)
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                configType, 1, 2, "InvalidDMRSConfigurationType", ...
                "DMRSConfigurationType must be 1 or 2.");
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                dmrsLength, 1, 2, "InvalidDMRSLength", ...
                "DMRSLength must be 1 or 2.");
            multiplexing = lower(strtrim(string(multiplexing)));
            if ~isscalar(multiplexing) || ...
                    ~any(multiplexing == ["basic","enhanced"])
                error("sixgr:pdsch:InvalidDMRSMultiplexingMode", ...
                    "DMRSMultiplexing must be basic or enhanced.");
            end
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                logicalPort, 0, 23, ...
                "DMRSPortUnsupportedForConfiguration", ...
                "The logical PDSCH DM-RS port must be in 0...23.");

            validPorts = sixgr.pdsch.PDSCHDMRSValidator. ...
                validPortIndices(configType, dmrsLength, multiplexing);
            if ~ismember(double(logicalPort), validPorts)
                error("sixgr:pdsch:DMRSPortUnsupportedForConfiguration", ...
                    "Logical DM-RS port %d is not supported for type %d, " + ...
                    "length %d, %s multiplexing.", logicalPort, configType, ...
                    dmrsLength, multiplexing);
            end

            if configType == 1
                lambda = floor(mod(logicalPort, 4) / 2);
                delta = lambda;
                if logicalPort < 8
                    if mod(logicalPort, 2) == 0
                        wf = [1 1 1 1];
                    else
                        wf = [1 -1 1 -1];
                    end
                elseif mod(logicalPort, 2) == 0
                    wf = [1 1 -1 -1];
                else
                    wf = [1 -1 -1 1];
                end
                block = floor(logicalPort / 4);
            else
                lambda = floor(mod(logicalPort, 6) / 2);
                delta = 2 * lambda;
                block = floor(logicalPort / 6);
                if block == 0
                    if mod(logicalPort, 2) == 0
                        wf = [1 1 1 1];
                    else
                        wf = [1 -1 1 -1];
                    end
                elseif mod(logicalPort, 2) == 0
                    wf = [1 1 -1 -1];
                else
                    wf = [1 -1 -1 1];
                end
            end
            if mod(block, 2) == 0
                wt = [1 1];
            else
                wt = [1 -1];
            end
            if dmrsLength == 2
                supportedLPrime = [0 1];
            else
                supportedLPrime = 0;
            end
            portInfo = struct( ...
                "LogicalPort", double(logicalPort), ...
                "PhysicalAntennaPort", 1000 + double(logicalPort), ...
                "SupportedLPrime", double(supportedLPrime), ...
                "CDMGroupLambda", double(lambda), ...
                "Delta", double(delta), ...
                "WF", double(wf), "WT", double(wt));
        end

        function ports = resolvePortSet(configType, dmrsLength, ...
                multiplexing, logicalPortSet, varargin)
            p = inputParser;
            addParameter(p, "NumLayers", []);
            addParameter(p, "NumCDMGroupsWithoutData", []);
            parse(p, varargin{:});

            if ~isnumeric(logicalPortSet) || isempty(logicalPortSet) || ...
                    ~isvector(logicalPortSet) || ...
                    any(~isfinite(logicalPortSet)) || ...
                    any(logicalPortSet ~= floor(logicalPortSet))
                error("sixgr:pdsch:InvalidDMRSPortSet", ...
                    "DMRSPortSet must be a nonempty vector of integer ports.");
            end
            logicalPortSet = double(logicalPortSet(:).');
            if numel(unique(logicalPortSet, "stable")) ~= numel(logicalPortSet)
                error("sixgr:pdsch:DuplicateDMRSPort", ...
                    "DMRSPortSet must not contain duplicate ports.");
            end
            if ~isempty(p.Results.NumLayers)
                numLayers = p.Results.NumLayers;
                sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                    numLayers, 1, 8, "InvalidPDSCHRank", ...
                    "NumLayers must be in the range 1...8.");
                if numel(logicalPortSet) ~= numLayers
                    error("sixgr:pdsch:DMRSPortLayerMismatch", ...
                        "DMRSPortSet contains %d ports for %d layers.", ...
                        numel(logicalPortSet), numLayers);
                end
            end
            if ~isempty(p.Results.NumCDMGroupsWithoutData)
                groups = p.Results.NumCDMGroupsWithoutData;
                if configType == 1
                    maxGroups = 2;
                else
                    maxGroups = 3;
                end
                sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                    groups, 1, maxGroups, ...
                    "InvalidNumCDMGroupsWithoutData", ...
                    sprintf("NumCDMGroupsWithoutData must be in 1...%d.", ...
                    maxGroups));
            end

            emptyPort = struct( ...
                "LogicalPort", 0, "PhysicalAntennaPort", 1000, ...
                "SupportedLPrime", 0, "CDMGroupLambda", 0, ...
                "Delta", 0, "WF", zeros(1, 4), "WT", zeros(1, 2));
            ports = repmat(emptyPort, 1, numel(logicalPortSet));
            for i = 1:numel(logicalPortSet)
                ports(i) = sixgr.pdsch.PDSCHDMRSValidator.resolvePort( ...
                    configType, dmrsLength, multiplexing, logicalPortSet(i));
            end
        end
    end

    methods (Static, Access = private)
        function row = positionTableRow(mappingType, dmrsLength, ld)
            row = {};
            if mappingType == "A" && dmrsLength == 1
                switch ld
                    case {3,4,5,6,7}
                        row = {[-1],[-1],[-1],[-1]};
                    case {8,9}
                        row = {[-1],[-1 7],[-1 7],[-1 7]};
                    case {10,11}
                        row = {[-1],[-1 9],[-1 6 9],[-1 6 9]};
                    case 12
                        row = {[-1],[-1 9],[-1 6 9],[-1 5 8 11]};
                    case {13,14}
                        row = {[-1],[-1 -2],[-1 7 11],[-1 5 8 11]};
                end
            elseif mappingType == "B" && dmrsLength == 1
                switch ld
                    case {2,3,4}
                        row = {[-1],[-1],[-1],[-1]};
                    case {5,6,7}
                        row = {[-1],[-1 4],[-1 4],[-1 4]};
                    case 8
                        row = {[-1],[-1 6],[-1 3 6],[-1 3 6]};
                    case {9,10}
                        row = {[-1],[-1 7],[-1 4 7],[-1 4 7]};
                    case 11
                        row = {[-1],[-1 8],[-1 4 8],[-1 3 6 9]};
                    case {12,13}
                        row = {[-1],[-1 9],[-1 5 9],[-1 3 6 9]};
                end
            elseif mappingType == "A" && dmrsLength == 2
                switch ld
                    case {4,5,6,7,8,9}
                        row = {[-1],[-1],[]};
                    case {10,11,12}
                        row = {[-1],[-1 8],[]};
                    case {13,14}
                        row = {[-1],[-1 10],[]};
                end
            elseif mappingType == "B" && dmrsLength == 2
                switch ld
                    case {5,6,7}
                        row = {[-1],[-1],[]};
                    case {8,9}
                        row = {[-1],[-1 5],[]};
                    case {10,11}
                        row = {[-1],[-1 7],[]};
                    case {12,13}
                        row = {[-1],[-1 8],[]};
                end
            end
        end

        function ports = validPortIndices(configType, dmrsLength, multiplexing)
            enhanced = multiplexing == "enhanced";
            if ~enhanced && dmrsLength == 1
                if configType == 1
                    ports = 0:3;
                else
                    ports = 0:5;
                end
            elseif ~enhanced && dmrsLength == 2
                if configType == 1
                    ports = 0:7;
                else
                    ports = 0:11;
                end
            elseif enhanced && dmrsLength == 1
                if configType == 1
                    ports = [0:3 8:11];
                else
                    ports = [0:5 12:17];
                end
            elseif configType == 1
                ports = 0:15;
            else
                ports = 0:23;
            end
        end

        function validateNIDNSCID(value)
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                value, 0, 65535, "InvalidNIDNSCID", ...
                "NIDNSCID must be an integer in 0...65535.");
        end

        function validateNSCID(value)
            sixgr.pdsch.PDSCHDMRSValidator.requireInteger( ...
                value, 0, 1, "InvalidNSCID", ...
                "NSCID must be 0 or 1.");
        end

        function requireInteger(value, minimum, maximum, token, message)
            if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                    value ~= floor(value) || value < minimum || value > maximum
                error("sixgr:pdsch:" + string(token), "%s", message);
            end
        end
    end
end
