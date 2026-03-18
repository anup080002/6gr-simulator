function st = getToolboxStatus()
%GETTOOLBOXSTATUS Robust capability detection by symbol existence.
%
% This is intentionally NOT based on license('test',...) because license
% feature names vary by release and can cause false negatives.
%
% Output fields are booleans:
%   st.fiveg, st.comm, st.dl, st.pct, st.phased, st.wns, st.siteviewer,
%   st.rfprop, st.pathloss
%
% Also includes per-symbol flags under st.symbols.

st = struct();
st.symbols = struct();

% 5G Toolbox symbols
st.symbols.nrOFDMInfo        = localHave("nrOFDMInfo");
st.symbols.nrPUSCH           = localHave("nrPUSCH");
st.symbols.nrPDSCH           = localHave("nrPDSCH");
st.symbols.nrLDPCEncode      = localHave("nrLDPCEncode");
st.symbols.nrRateRecoverLDPC = localHave("nrRateRecoverLDPC");
st.symbols.nrPathLoss        = localHave("nrPathLoss");

% Core toolboxes
st.symbols.awgn         = localHave("awgn");
st.symbols.trainNetwork = localHave("trainNetwork");
st.symbols.parpool      = localHave("parpool");
st.symbols.phasedURA    = localHave("phased.URA");

% Wireless Network Simulation Library (class with static init in current releases)
st.symbols.wirelessNetworkSimulator = localHave("wirelessNetworkSimulator");

% Site Viewer (constructor)
st.symbols.siteviewer = localHave("siteviewer");

% RF Propagation/Antenna Toolbox
st.symbols.txsite = localHave("txsite");

% Roll-up flags
st.fiveg       = st.symbols.nrOFDMInfo && st.symbols.nrPUSCH && st.symbols.nrPDSCH;
st.pathloss    = st.symbols.nrPathLoss;
st.comm        = st.symbols.awgn;
st.dl          = st.symbols.trainNetwork;
st.pct         = st.symbols.parpool;
st.phased      = st.symbols.phasedURA;
st.wns         = st.symbols.wirelessNetworkSimulator;
st.siteviewer  = st.symbols.siteviewer;
st.rfprop      = st.symbols.txsite;

end

function tf = localHave(sym)
% Handles functions, built-ins, p-files, mex-files, and classes.
sym = char(sym);

fileHit  = any(exist(sym,"file") == [2 3 5 6]);
classHit = (exist(sym,"class") == 8);

tf = fileHit || classHit;

% Some classes only show up via which()
if ~tf
    w = which(sym);
    tf = ~isempty(w);
end

end
