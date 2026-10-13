function msg3 = buildMsg3Payload(varargin)
%BUILDMSG3PAYLOAD Build CCCH SDU style Msg3 contention identity bytes.
p = inputParser;
p.addParameter("UEId", 1, @(x)isnumeric(x) && isscalar(x));
p.addParameter("ContentionIdentity", [], @(x)isempty(x) || isnumeric(x));
p.addParameter("RRCSetupRequest", true, @(x)islogical(x) || isnumeric(x));
p.addParameter("UEIdentity", "", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

if isempty(opt.ContentionIdentity)
    % This is the explicitly bounded codec, not ASN.1 UL-CCCH. Preserve a
    % distinct, exact 48-bit local identity for each configured UE. The old
    % double-valued LCG lost every UE-specific low bit before its modulus.
    validateattributes(opt.UEId,{'numeric'}, ...
        {'scalar','real','finite','integer','positive','<=',2^48-1});
    identity = uint64(opt.UEId);
    bytes = zeros(6, 1, "uint8");
    for ii = 1:6
        bytes(ii) = uint8(bitand(bitshift(identity,-8*(6-ii)),uint64(255)));
    end
    identitySource="bounded_codec_exact_configured_UE_identity_not_NR_CCCH";
else
    validateattributes(opt.ContentionIdentity,{'numeric'}, ...
        {'vector','numel',6,'real','finite','integer','>=',0,'<=',255});
    bytes = uint8(opt.ContentionIdentity(:));
    identitySource="explicit_local_48_bit_identity";
end
payload = uint8([1; 6; bytes(:)]);
ueIdentity = string(opt.UEIdentity);
if strlength(strtrim(ueIdentity)) == 0
    ueIdentity = "UE-" + string(round(double(opt.UEId)));
end
requestBytes = uint8(unicode2native(char(ueIdentity), "UTF-8"));
if numel(requestBytes) > 255
    error("sixgr:mac:ra:RRCSetupRequestTooLarge", ...
        "The bounded RRCSetupRequest UE identity exceeds 255 octets.");
end
if logical(opt.RRCSetupRequest)
    payload = [payload; uint8(49); uint8(numel(requestBytes)); ...
        requestBytes(:)]; %#ok<AGROW>
end
msg3 = struct();
msg3.PayloadBytes = payload(:);
msg3.PayloadBits = localBytesToBits(payload);
msg3.PayloadHex = upper(string(reshape(dec2hex(payload(:), 2).', 1, [])));
msg3.ContentionIdentityBytes = bytes(:);
msg3.ContentionIdentity = upper(string(reshape(dec2hex(bytes(:), 2).', 1, [])));
msg3.ContentionIdentitySource = identitySource;
msg3.RRCSetupRequestPresent = logical(opt.RRCSetupRequest);
msg3.RRCSetupRequest = struct( ...
    "MessageType", "RRCSetupRequest", ...
    "UEIdentity", ueIdentity, ...
    "EstablishmentCause", "mo-Signalling");
msg3.RRCSetupRequestSHA256 = sixgr.rrc.asn1.asn1SHA256Hex( ...
    uint8([49; uint8(numel(requestBytes)); requestBytes(:)]));
msg3.PayloadHash = sixgr.rrc.asn1.asn1SHA256Hex(payload);
end

function bits = localBytesToBits(bytes)
bytes = uint8(bytes(:));
bits = zeros(numel(bytes)*8, 1, "int8");
for ii = 1:numel(bytes)
    for jj = 1:8
        bits((ii-1)*8 + jj) = int8(bitand(bitshift(bytes(ii), -(8-jj)), 1));
    end
end
end
