function lengths = csirsCDMLengths(cdmType)
%CSIRSCDMLENGTHS Resolve CSI-RS CDM geometry for nrChannelEstimate.
%
% The returned [frequency time] lengths describe the orthogonal CSI-RS
% code-division group defined by the runtime nrCSIRSConfig. Keeping this
% conversion in one production function prevents the transmitter, receiver,
% and oracle validators from silently using different pilot geometry.

token = upper(strtrim(string(cdmType)));
token = replace(token, "_", "-");
if ~(isscalar(token) && strlength(token) > 0)
    error("sixgr:phy:csirs:MissingCDMType", ...
        "CSI-RS channel estimation requires the resolved runtime CDMType.");
end

switch token
    case "NOCDM"
        lengths = [1 1];
    case "FD-CDM2"
        lengths = [2 1];
    case "CDM4-FD2-TD2"
        lengths = [2 2];
    case "CDM8-FD2-TD4"
        lengths = [2 4];
    otherwise
        error("sixgr:phy:csirs:UnsupportedCDMType", ...
            "Unsupported runtime CSI-RS CDMType '%s'.", char(token));
end
end
