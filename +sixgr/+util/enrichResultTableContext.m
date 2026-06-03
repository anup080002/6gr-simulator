function T = enrichResultTableContext(T, cfg)
%ENRICHRESULTTABLECONTEXT Add shared radio/UE tracking columns to result tables.

if nargin < 1 || ~istable(T)
    return;
end
if nargin < 2 || ~(builtin("isstruct", cfg) && isscalar(cfg))
    cfg = struct();
end

n = height(T);
slotsPerFrame = localSlotsPerFrame(cfg);

T = localEnsureNumericColumn(T, "Slot", ...
    ["Slot","TTI","GenerationSlot","GrantSlot","TriggerTTI","StartTTI","CompleteTTI"], NaN(n,1));
T = localEnsureNumericColumn(T, "Frame", ...
    ["Frame","TriggerTTI","StartTTI","CompleteTTI"], NaN(n,1));
if ismember("Frame", string(T.Properties.VariableNames)) && ismember("Slot", string(T.Properties.VariableNames))
    frameCol = double(T.Frame);
    slotCol = double(T.Slot);
    miss = ~isfinite(frameCol) & isfinite(slotCol);
    if any(miss)
        frameCol(miss) = floor(max(slotCol(miss) - 1, 0) ./ max(slotsPerFrame, 1)) + 1;
        T.Frame = frameCol;
    end
end

T = localEnsureNumericColumn(T, "SFN", ["SFN"], NaN(n,1));
if ismember("SFN", string(T.Properties.VariableNames)) && ismember("Frame", string(T.Properties.VariableNames))
    sfnCol = double(T.SFN);
    frameCol = double(T.Frame);
    miss = ~isfinite(sfnCol) & isfinite(frameCol);
    if any(miss)
        sfnCol(miss) = mod(max(frameCol(miss) - 1, 0), 1024);
        T.SFN = sfnCol;
    end
end

T = localEnsureNumericColumn(T, "UEID", ["UEID","UE","UEIndex"], localDefaultUEID(cfg, n));
T = localEnsureNumericColumn(T, "RNTI", ["RNTI","TempCRNTI","AttachRNTI"], NaN(n,1));
T = localEnsureNumericColumn(T, "BaseStationID", ...
    ["BaseStationID","CellID","ServingCell","ToCell","FromCell"], localDefaultBaseStationID(cfg, n));
T = localEnsureNumericColumn(T, "PRBCount", ["PRBCount","PRBs","NumPRB","NPRB"], NaN(n,1));
T = localEnsureNumericColumn(T, "AllocatedPRBCount", ["AllocatedPRBCount","PRBCount","PRBs","NumPRB","NPRB"], NaN(n,1));
T = localEnsureNumericColumn(T, "PRBStart", ["PRBStart"], NaN(n,1));
T = localEnsureNumericColumn(T, "MCS", ["MCS","MCSIndex"], NaN(n,1));
T = localEnsureNumericColumn(T, "Layers", ["Layers","NumLayers","ConfiguredLayers"], NaN(n,1));
T = localEnsureNumericColumn(T, "Rank", ...
    ["Rank","Layers","NumLayers","ConfiguredLayers"], NaN(n,1));
T = localEnsureNumericColumn(T, "TBSize_bits", ...
    ["TBSize_bits","TBSBits","TransportBlockSize"], NaN(n,1));
if ismember("TBSize_bits", string(T.Properties.VariableNames)) && ismember("TBSBytes", string(T.Properties.VariableNames))
    tbBits = double(T.TBSize_bits);
    bytes = double(T.TBSBytes);
    miss = ~isfinite(tbBits) & isfinite(bytes);
    if any(miss)
        tbBits(miss) = 8 .* bytes(miss);
        T.TBSize_bits = tbBits;
    end
end
T = localEnsureNumericColumn(T, "PortCount", ["PortCount","NumTxPorts","NumPorts"], NaN(n,1));
end

function T = localEnsureNumericColumn(T, targetName, candidateNames, defaultColumn)
vars = string(T.Properties.VariableNames);
if ismember(targetName, vars)
    target = localAsNumericColumn(T.(char(targetName)), height(T));
else
    target = localAsNumericColumn(defaultColumn, height(T));
end

for i = 1:numel(candidateNames)
    candName = string(candidateNames(i));
    if candName == targetName || ~ismember(candName, vars)
        continue;
    end
    cand = localAsNumericColumn(T.(char(candName)), height(T));
    miss = ~isfinite(target) & isfinite(cand);
    if any(miss)
        target(miss) = cand(miss);
    end
end

miss = ~isfinite(target);
if any(miss)
    def = localAsNumericColumn(defaultColumn, height(T));
    fill = miss & isfinite(def);
    if any(fill)
        target(fill) = def(fill);
    end
end

T.(char(targetName)) = target;
end

function col = localAsNumericColumn(value, n)
if nargin < 2
    n = numel(value);
end
if islogical(value)
    col = double(value(:));
elseif isnumeric(value)
    col = double(value(:));
elseif isstring(value) || ischar(value) || iscellstr(value)
    try
        col = double(str2double(string(value(:))));
    catch
        col = NaN(numel(value), 1);
    end
else
    col = NaN(numel(value), 1);
end

if isempty(col)
    col = NaN(n, 1);
elseif numel(col) == 1 && n > 1
    col = repmat(col, n, 1);
elseif numel(col) ~= n
    col = reshape(col, [], 1);
    if numel(col) < n
        col(end+1:n, 1) = NaN;
    else
        col = col(1:n);
    end
end
end

function slotsPerFrame = localSlotsPerFrame(cfg)
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 15));
mu = log2(scs / 15);
if ~(isfinite(mu) && mu >= 0)
    mu = 0;
end
slotsPerFrame = max(1, round(10 * (2 ^ mu)));
end

function value = localDefaultUEID(cfg, n)
value = NaN(n,1);
ueID = double(sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", NaN));
if isfinite(ueID) && ueID >= 1
    value(:) = ueID;
end
end

function value = localDefaultBaseStationID(cfg, n)
value = NaN(n,1);
bsID = double(sixgr.util.structGet(cfg, "scenario.bs.cell_id", ...
    sixgr.util.structGet(cfg, "scenario.cell_id", ...
    sixgr.util.structGet(cfg, "scenario.base_station_id", NaN))));
if isfinite(bsID) && bsID >= 0
    value(:) = bsID;
end
end
