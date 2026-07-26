classdef PUCCHResourceOwnershipMap
    %PUCCHRESOURCEOWNERSHIPMAP Zero-based exact RE ownership.

    properties (SetAccess=private)
        Table
        CollisionCount
        DataRECount
        DMRSRECount
        IndexDigest
        CyclicShift
        OCCIndex
        Digest
    end

    methods
        function obj = PUCCHResourceOwnershipMap(tableValue,resource)
            obj.Table = tableValue;
            obj.CollisionCount = height(tableValue)- ...
                numel(unique(string(tableValue.REKey)));
            obj.DataRECount = sum(string(tableValue.REOwner)=="UCI");
            obj.DMRSRECount = sum(string(tableValue.REOwner)=="DMRS");
            obj.IndexDigest = sixgr.phy.pucch.PUCCHUtil.hash( ...
                string(tableValue.REKey).');
            obj.CyclicShift = double(resource.Data.InitialCyclicShift);
            obj.OCCIndex = double(resource.Data.OCCIndex);
            obj.Digest = obj.IndexDigest;
        end
    end

    methods (Static)
        function obj = build(carrier,assignment)
            if ~isa(assignment,"sixgr.phy.pucch.PUCCHTransmissionAssignment")
                error("sixgr:phy:pucch:WrongResource", ...
                    "Ownership mapping requires a typed assignment.");
            end
            resource = assignment.Resource;
            pucch = resource.toolboxConfig();
            [dataIndices,~] = nrPUCCHIndices(carrier,pucch);
            dmrs = sixgr.phy.pucch.PUCCHDMRS.generate(carrier,resource);
            value = [localRows(carrier,dataIndices,"UCI",assignment); ...
                localRows(carrier,dmrs.Indices,"DMRS",assignment)];
            if isempty(value)
                error("sixgr:phy:pucch:WrongResource", ...
                    "PUCCH resource produced no owned resource elements.");
            end
            obj = sixgr.phy.pucch.PUCCHResourceOwnershipMap(value,resource);
            if obj.CollisionCount ~= 0
                error("sixgr:phy:pucch:CollisionUnresolved", ...
                    "PUCCH ownership contains %d duplicate RE keys.", ...
                    obj.CollisionCount);
            end
        end
    end
end

function rows = localRows(carrier,indices,owner,assignment)
indices = indices(:);
if isempty(indices)
    rows = table();
    return;
end
K = 12*carrier.NSizeGrid;
L = carrier.SymbolsPerSlot;
[subcarrier,symbol,port] = ind2sub([K L max(1,ceil(max(indices)/(K*L)))], ...
    double(indices));
prb = floor((subcarrier-1)/12);
subcarrierInPRB = mod(subcarrier-1,12);
slot = repmat(double(carrier.NSlot),numel(indices),1);
format = repmat(assignment.Format,numel(indices),1);
hop = double(prb ~= assignment.Resource.Data.StartPRB);
repetition = zeros(numel(indices),1);
REOwner = repmat(string(owner),numel(indices),1);
resourceID = repmat(assignment.Resource.ID,numel(indices),1);
reportID = repmat(assignment.ReportID,numel(indices),1);
REKey = string(slot) + ":" + string(symbol-1) + ":" + string(prb) + ...
    ":" + string(subcarrierInPRB) + ":" + string(port-1);
rows = table();
rows.Slot = slot;
rows.Symbol = symbol-1;
rows.PRB = prb;
rows.Subcarrier = subcarrierInPRB;
rows.Format = format;
rows.Hop = hop;
rows.Repetition = repetition;
rows.REOwner = REOwner;
rows.Port = port-1;
rows.ResourceID = resourceID;
rows.ReportID = reportID;
rows.REKey = REKey;
end
