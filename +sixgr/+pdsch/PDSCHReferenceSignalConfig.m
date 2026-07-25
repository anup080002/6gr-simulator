classdef PDSCHReferenceSignalConfig
    %PDSCHREFERENCESIGNALCONFIG Immutable strict PDSCH RS configuration.
    %
    % The object contains configuration only.  Callers cannot inject
    % pre-built DM-RS/PT-RS symbols into the canonical transmitter.

    properties (SetAccess = immutable)
        Data (1,1) struct
        ConfigurationDigest (1,1) string
    end

    methods
        function obj = PDSCHReferenceSignalConfig(data)
            arguments
                data (1,1) struct
            end
            forbidden = ["DMRSSymbolsPerPort","PTRSSymbolsPerPort", ...
                "DMRSSymbols","PTRSSymbols"];
            injected = forbidden(isfield(data,forbidden));
            if ~isempty(injected)
                error("sixgr:pdsch:CallerBuiltReferenceSymbolsForbidden", ...
                    "Canonical PDSCH reference configuration cannot contain " + ...
                    "caller-built symbols: %s.", ...
                    strjoin(cellstr(injected),", "));
            end
            required = [ ...
                "NID","DataScramblingIdentityNID", ...
                "DMRSConfigurationType","DMRSTypeAPosition", ...
                "DMRSAdditionalPosition","DMRSLength", ...
                "NumCDMGroupsWithoutData","NIDNSCID","NSCID", ...
                "DMRSMultiplexing","EnablePTRS", ...
                "NPhysicalTxAntennas","OFDMOptions", ...
                "DMRSAmplitudeScale","PTRSAmplitudeScale"];
            missing = required(~isfield(data,required));
            if ~isempty(missing)
                error("sixgr:pdsch:IncompleteReferenceSignalConfiguration", ...
                    "PDSCH reference configuration is missing: %s.", ...
                    strjoin(cellstr(missing),", "));
            end
            if logical(data.EnablePTRS)
                ptrsRequired = [ ...
                    "PTRSTimeDensity","PTRSFrequencyDensity", ...
                    "PTRSREOffset"];
                missing = ptrsRequired(~isfield(data,ptrsRequired));
                if ~isempty(missing)
                    error("sixgr:pdsch:IncompleteReferenceSignalConfiguration", ...
                        "Enabled PT-RS configuration is missing: %s.", ...
                        strjoin(cellstr(missing),", "));
                end
            end

            localInteger(data.NID,0,1023,"InvalidReferenceNID");
            localInteger(data.DataScramblingIdentityNID,0,1023, ...
                "InvalidScramblingIdentity");
            localInteger(data.DMRSConfigurationType,1,2, ...
                "InvalidDMRSConfigurationType");
            localInteger(data.DMRSTypeAPosition,2,3, ...
                "InvalidDMRSTypeAPosition");
            localInteger(data.DMRSAdditionalPosition,0,3, ...
                "UnsupportedDMRSPositionCombination");
            localInteger(data.DMRSLength,1,2,"InvalidDMRSLength");
            maxCDM = 2 + double(data.DMRSConfigurationType == 2);
            localInteger(data.NumCDMGroupsWithoutData,1,maxCDM, ...
                "InvalidNumCDMGroupsWithoutData");
            localInteger(data.NIDNSCID,0,65535,"InvalidNIDNSCID");
            localInteger(data.NSCID,0,1,"InvalidNSCID");
            mux = lower(strtrim(string(data.DMRSMultiplexing)));
            if ~isscalar(mux) || ~any(mux == ["basic","enhanced"])
                error("sixgr:pdsch:InvalidDMRSMultiplexingMode", ...
                    "DMRSMultiplexing must be basic or enhanced.");
            end
            if ~(islogical(data.EnablePTRS) && isscalar(data.EnablePTRS))
                error("sixgr:pdsch:InvalidPTRSEnable", ...
                    "EnablePTRS must be an explicit logical scalar.");
            end
            localInteger(data.NPhysicalTxAntennas,1,1024, ...
                "InvalidPhysicalTxAntennaCount");
            if ~iscell(data.OFDMOptions) ...
                    || mod(numel(data.OFDMOptions),2) ~= 0
                error("sixgr:pdsch:InvalidOFDMOptions", ...
                    "OFDMOptions must be a cell array of name-value pairs.");
            end
            localPositiveScale(data.DMRSAmplitudeScale, ...
                "InvalidDMRSAmplitudeScale");
            localPositiveScale(data.PTRSAmplitudeScale, ...
                "InvalidPTRSAmplitudeScale");
            if logical(data.EnablePTRS)
                if ~ismember(double(data.PTRSTimeDensity),[1 2 4])
                    error("sixgr:pdsch:InvalidPTRSTimeDensity", ...
                        "PTRSTimeDensity must be 1, 2, or 4.");
                end
                if ~ismember(double(data.PTRSFrequencyDensity),[2 4])
                    error("sixgr:pdsch:InvalidPTRSFrequencyDensity", ...
                        "PTRSFrequencyDensity must be 2 or 4.");
                end
                offset = string(data.PTRSREOffset);
                if ~isscalar(offset) || ...
                        ~any(offset == ["00","01","10","11"])
                    error("sixgr:pdsch:InvalidPTRSREOffset", ...
                        "PTRSREOffset must be 00, 01, 10, or 11.");
                end
            end

            canonical = orderfields(data);
            canonical.DMRSMultiplexing = mux;
            canonical.EnablePTRS = logical(data.EnablePTRS);
            canonical.OFDMOptions = reshape(data.OFDMOptions,1,[]);
            obj.Data = canonical;
            obj.ConfigurationDigest = localDigest(canonical);
        end

        function value = get(obj,name)
            name = char(string(name));
            if ~isfield(obj.Data,name)
                error("sixgr:pdsch:UnknownReferenceConfigurationField", ...
                    "Reference configuration has no field '%s'.",name);
            end
            value = obj.Data.(name);
        end

        function value = toStruct(obj)
            value = obj.Data;
        end

        function digest = validateForExecution(obj)
            digest = localDigest(obj.Data);
            if digest ~= obj.ConfigurationDigest
                error("sixgr:pdsch:ReferenceConfigurationDigestMismatch", ...
                    "Immutable PDSCH reference configuration changed.");
            end
        end
    end
end

function localInteger(value,minimum,maximum,token)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) ...
        || value ~= floor(value) || value < minimum || value > maximum
    error("sixgr:pdsch:" + string(token), ...
        "Reference configuration integer is outside [%g,%g].", ...
        minimum,maximum);
end
end

function localPositiveScale(value,token)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
    error("sixgr:pdsch:" + string(token), ...
        "Reference-signal amplitude scale must be positive and finite.");
end
end

function value = localDigest(data)
bytes = uint8(unicode2native(jsonencode(orderfields(data)),"UTF-8"));
value = string(sixgr.util.sha256Hex(bytes));
end
