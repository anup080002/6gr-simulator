classdef DMRSIndexSpec
    %DMRSINDEXSPEC Independent TS 38.211 PDSCH DM-RS index oracle.
    %
    % This implementation calls neither production reference code nor a
    % MATLAB nr* primitive.  Indices are zero based and grouped by logical
    % DM-RS port.

    methods (Static)
        function result = resolve(request)
            required = ["GridNumPRB","PRBSet","DMRSSymbols", ...
                "DMRSConfigurationType","DMRSPortSet"];
            if ~isstruct(request) || ~isscalar(request)
                error("sixgr:pdsch:oracle:InvalidDMRSIndexRequest", ...
                    "DM-RS index request must be a scalar struct.");
            end
            missing = required(~isfield(request,required));
            if ~isempty(missing)
                error("sixgr:pdsch:oracle:IncompleteDMRSIndexRequest", ...
                    "DM-RS index request is missing: %s.", ...
                    strjoin(cellstr(missing),", "));
            end
            nPRB = localInteger(request.GridNumPRB,1,inf);
            prbs = localVector(request.PRBSet,0,nPRB-1);
            symbols = localVector(request.DMRSSymbols,0,13);
            configType = localInteger( ...
                request.DMRSConfigurationType,1,2);
            ports = localVector(request.DMRSPortSet,0,23);
            K = 12*nPRB;
            byPort = cell(1,numel(ports));
            coordinates = cell(1,numel(ports));
            for p = 1:numel(ports)
                if configType == 1
                    delta = floor(mod(ports(p),4)/2);
                    localSubcarriers = delta + [0 2 4 6 8 10];
                else
                    delta = 2*floor(mod(ports(p),6)/2);
                    localSubcarriers = delta + [0 1 6 7];
                end
                count = numel(prbs)*numel(symbols)* ...
                    numel(localSubcarriers);
                coords = zeros(count,2);
                cursor = 0;
                for symbol = symbols
                    for prb = prbs
                        rows = cursor + (1:numel(localSubcarriers));
                        coords(rows,:) = [ ...
                            12*prb + localSubcarriers(:), ...
                            repmat(symbol,numel(localSubcarriers),1)];
                        cursor = cursor + numel(localSubcarriers);
                    end
                end
                coordinates{p} = coords;
                byPort{p} = (coords(:,1) + K*coords(:,2)).';
            end
            result = struct( ...
                "IndicesPerPort",{byPort}, ...
                "CoordinatesPerPort",{coordinates}, ...
                "DMRSPortSet",double(ports(:).'), ...
                "IndexBase","zero_based", ...
                "StandardReference","TS_38.211_7.4.1.1.2");
        end
    end
end

function value = localInteger(value,minimum,maximum)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) ...
        || value ~= floor(value) || value < minimum || value > maximum
    error("sixgr:pdsch:oracle:InvalidDMRSIndexField", ...
        "DM-RS index-oracle integer is outside its explicit range.");
end
value = double(value);
end

function value = localVector(value,minimum,maximum)
if ~isnumeric(value) || isempty(value) || ~isvector(value) ...
        || any(~isfinite(value)) || any(value ~= floor(value)) ...
        || any(value < minimum) || any(value > maximum) ...
        || numel(unique(value,"stable")) ~= numel(value)
    error("sixgr:pdsch:oracle:InvalidDMRSIndexField", ...
        "DM-RS index-oracle vectors must be explicit unique integers.");
end
value = double(value(:).');
end
