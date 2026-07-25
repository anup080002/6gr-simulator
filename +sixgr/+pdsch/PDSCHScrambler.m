function [out, info] = PDSCHScrambler(input, varargin)
%PDSCHSCRAMBLER Apply the TS 38.211 PDSCH scrambling transform.
%
%   SCRAMBLED = sixgr.pdsch.PDSCHScrambler(BITS,RNTI,Q,NID)
%   LLR = sixgr.pdsch.PDSCHScrambler(LLR,RNTI,Q,NID, ...
%       "Operation","llr-descramble")
%
% Q is the zero-based codeword index.  LLR descrambling follows the
% convention that a positive LLR favours bit zero.
%
if isstruct(input) && numel(varargin) == 2
    error("sixgr:pdsch:PDSCHScrambler:LegacyMetadataForbidden", ...
        "PDSCH scrambling requires materialized bits plus explicit RNTI, codeword index, and NID; configuration-only metadata inference is forbidden.");
end

[rnti, q, nid, options] = localParseTransformArguments(varargin{:});
operation = options.Operation;
localValidateContext(rnti, q, nid);

sequence = localGoldSequence(localCInit(rnti, q, nid), numel(input));
switch operation
    case "scramble"
        localRequireBinary(input);
        transformed = bitxor(uint8(input(:)), sequence);
        out = reshape(cast(transformed, "like", input), size(input));
    case {"llr-descramble", "descramble-llr", "llr_descramble"}
        if ~(isnumeric(input) && isreal(input) && all(isfinite(input(:))))
            error("sixgr:pdsch:PDSCHScrambler:InvalidLLRInput", ...
                "PDSCH LLR descrambling requires finite real numeric LLRs.");
        end
        signs = 1 - 2 * double(sequence);
        transformed = double(input(:)) .* signs;
        out = reshape(cast(transformed, "like", input), size(input));
    otherwise
        error("sixgr:pdsch:PDSCHScrambler:UnsupportedOperation", ...
            "Unsupported PDSCH scrambling operation '%s'.", operation);
end

info = struct();
info.Operation = operation;
info.RNTI = rnti;
info.CodewordIndex = q;
info.DataScramblingIdentityNID = nid;
info.CInit = localCInit(rnti, q, nid);
info.Length = numel(input);
info.Sequence = int8(sequence);
info.LLRConvention = "positive_favours_bit_zero";
end

function [rnti, q, nid, options] = localParseTransformArguments(varargin)
if isempty(varargin)
    error("sixgr:pdsch:PDSCHScrambler:MissingContext", ...
        "RNTI, codeword index q, and data-scrambling identity NID are required.");
end

if isstruct(varargin{1})
    context = varargin{1};
    rnti = localStructField(context, ["RNTI", "nRNTI"]);
    q = localStructField(context, ["CodewordIndex", "Q", "q"]);
    nid = localStructField(context, ...
        ["DataScramblingIdentityNID", "DataScramblingIdentity", "NID", "nID"]);
    nv = varargin(2:end);
else
    if numel(varargin) < 3
        error("sixgr:pdsch:PDSCHScrambler:MissingContext", ...
            "RNTI, codeword index q, and data-scrambling identity NID are required.");
    end
    rnti = varargin{1};
    q = varargin{2};
    nid = varargin{3};
    nv = varargin(4:end);
end

options = struct("Operation", "scramble");
if mod(numel(nv), 2) ~= 0
    error("sixgr:pdsch:PDSCHScrambler:BadNameValue", ...
        "PDSCH scrambler options must be supplied as name-value pairs.");
end
for idx = 1:2:numel(nv)
    name = lower(strtrim(string(nv{idx})));
    switch name
        case "operation"
            options.Operation = lower(strtrim(string(nv{idx + 1})));
        otherwise
            error("sixgr:pdsch:PDSCHScrambler:UnknownOption", ...
                "Unknown PDSCH scrambler option '%s'.", name);
    end
end
end

function value = localStructField(context, names)
value = [];
for name = names
    fieldName = char(name);
    if isfield(context, fieldName) && ~isempty(context.(fieldName))
        value = context.(fieldName);
        break;
    end
end
if isempty(value)
    error("sixgr:pdsch:PDSCHScrambler:MissingContext", ...
        "Scrambling context is missing required field %s.", strjoin(names, "/"));
end
end

function localValidateContext(rnti, q, nid)
if ~(isnumeric(rnti) && isscalar(rnti) && isfinite(rnti) ...
        && rnti == fix(rnti) && rnti >= 0 && rnti <= 65535)
    error("sixgr:pdsch:PDSCHScrambler:RNTIOutOfRange", ...
        "PDSCH RNTI must be an integer in [0,65535].");
end
if ~(isnumeric(q) && isscalar(q) && isfinite(q) && any(q == [0 1]))
    error("sixgr:pdsch:PDSCHScrambler:CodewordIndexOutOfRange", ...
        "PDSCH codeword index q must be zero or one.");
end
if ~(isnumeric(nid) && isscalar(nid) && isfinite(nid) ...
        && nid == fix(nid) && nid >= 0 && nid <= 1023)
    error("sixgr:pdsch:PDSCHScrambler:NIDOutOfRange", ...
        "PDSCH data-scrambling identity NID must be an integer in [0,1023].");
end
end

function localRequireBinary(bits)
if ~((isnumeric(bits) || islogical(bits)) && isreal(bits) ...
        && all(isfinite(double(bits(:)))) && all(bits(:) == 0 | bits(:) == 1))
    error("sixgr:pdsch:PDSCHScrambler:NonBinaryInput", ...
        "PDSCH scrambling input must contain only binary values zero and one.");
end
end

function cInit = localCInit(rnti, q, nid)
cInit = double(rnti) * 2^15 + double(q) * 2^14 + double(nid);
end

function sequence = localGoldSequence(cInit, outputLength)
% Direct implementation of TS 38.211 clause 5.2.1.
nc = 1600;
totalLength = nc + outputLength + 31;
x1 = zeros(totalLength, 1, "uint8");
x2 = zeros(totalLength, 1, "uint8");
x1(1) = 1;
for bitIndex = 0:30
    x2(bitIndex + 1) = uint8(bitget(uint32(cInit), bitIndex + 1));
end
for n = 0:(totalLength - 32)
    x1(n + 32) = bitxor(x1(n + 4), x1(n + 1));
    x2(n + 32) = bitxor(bitxor(x2(n + 4), x2(n + 3)), ...
        bitxor(x2(n + 2), x2(n + 1)));
end
sequence = bitxor(x1(nc + (1:outputLength)), x2(nc + (1:outputLength)));
sequence = sequence(:);
end
