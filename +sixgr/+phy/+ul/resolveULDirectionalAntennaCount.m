function count = resolveULDirectionalAntennaCount(cfg, role, fallback)
%RESOLVEULDIRECTIONALANTENNACOUNT Resolve truthful UL Tx/Rx antenna counts.
% In this repository, cfg.phy.nTxAnt/cfg.phy.nRxAnt are DL-oriented globals:
% gNB Tx and UE Rx. UL waveform execution must instead use UE Tx for the
% transmitter side and gNB Rx for the receiver side.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2
    role = "tx";
end
if nargin < 3 || ~(isnumeric(fallback) && isscalar(fallback) && isfinite(fallback) && fallback >= 1)
    fallback = 1;
end

role = upper(string(role));
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());

if role == "TX"
    meta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
    antenna = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    cfgCandidates = [ ...
        sixgr.util.structGet(cfg, "antenna.ue.numElements", NaN), ...
        sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", NaN), ...
        sixgr.util.structGet(cfg, "channel.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", NaN), ...
        sixgr.util.structGet(cfg, "phy.pusch.numPorts", NaN), ...
        sixgr.util.structGet(cfg, "channel.nTxAntUL", NaN)];
else
    meta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
    antenna = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    cfgCandidates = [ ...
        sixgr.util.structGet(cfg, "antenna.bs.numElements", NaN), ...
        sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "channel.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "channel.nRxAntUL", NaN), ...
        sixgr.util.structGet(cfg, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", NaN)];
end

count = localFirstValidCount([ ...
    localRuntimeAntennaCount(meta, antenna), ...
    double(cfgCandidates(:).'), ...
    double(fallback)]);

count = max(1, round(double(count)));
end

function count = localRuntimeAntennaCount(meta, antenna)
count = NaN;
metaCandidates = [ ...
    sixgr.util.structGet(meta, "NumPorts", NaN), ...
    sixgr.util.structGet(meta, "NumElements", NaN)];
count = localFirstValidCount(metaCandidates);
if isfinite(count)
    return;
end

arrCandidates = [ ...
    sixgr.util.structGet(antenna, "Nant", NaN), ...
    localArraySizeCount(sixgr.util.structGet(antenna, "Size", []))];
count = localFirstValidCount(arrCandidates);
end

function count = localArraySizeCount(sizeValue)
count = NaN;
sizeVec = double(sizeValue(:).');
sizeVec = sizeVec(isfinite(sizeVec) & sizeVec >= 1);
if isempty(sizeVec)
    return;
end
if numel(sizeVec) >= 3
    count = prod(sizeVec(1:3));
else
    count = prod(sizeVec);
end
end

function count = localFirstValidCount(values)
count = NaN;
values = double(values(:));
values = values(isfinite(values) & values >= 1);
if isempty(values)
    return;
end
count = values(1);
end
