function rnti = computeRARNTIFromOccasion(occasion, varargin)
%COMPUTERARNTIFROMOCCASION Derive TS 38.321 RA-RNTI from a materialized occasion.
%
% The materialized PRACH occasion is authoritative for the first OFDM
% symbol, slot within the radio frame, and frequency-domain occasion.  This
% keeps MAC state bound to the waveform that is actually transmitted.
p = inputParser;
p.addRequired("occasion", @isstruct);
p.addParameter("ULCarrierId", 0, @(x)isnumeric(x) && isscalar(x) && ...
    isfinite(x) && x == fix(x));
p.parse(occasion, varargin{:});

required = ["RARNTISymbolIndex","RARNTISlotIndex","FrequencyIndex","Carrier"];
missing = required(~isfield(occasion, required));
if ~isempty(missing)
    error("sixgr:phy:ra:IncompletePRACHOccasion", ...
        "Materialized PRACH occasion is missing: %s.", strjoin(missing, ", "));
end
carrier = occasion.Carrier;
if ~isstruct(carrier) || ~isfield(carrier, "NSlot")
    error("sixgr:phy:ra:IncompletePRACHOccasion", ...
        "Materialized PRACH occasion must contain Carrier.NSlot.");
end

rnti = sixgr.phy.ra.computeRARNTI( ...
    "SymbolIndex", double(occasion.RARNTISymbolIndex), ...
    "SlotIndex", double(occasion.RARNTISlotIndex), ...
    "FrequencyIndex", double(occasion.FrequencyIndex), ...
    "ULCarrierId", double(p.Results.ULCarrierId));
end
