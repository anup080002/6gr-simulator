function out = generateTRSSymbolsAndIndices(cfg)
%GENERATETRSSYMBOLSANDINDICES Generate NZP-CSI-RS/TRS symbols and indices.

resourceSet = sixgr.phy.trs.buildNZPCSIRSResourceSetForTRS(cfg);
slots = double(resourceSet.SlotNumbers(:).');
resourceIDs=double(sixgr.util.structGet(cfg,"NZPCSIRSResourceIDs",[]));
if ~isempty(resourceIDs)
    validateattributes(resourceIDs,{'numeric'},{'vector','finite','integer','>=',0,'<=',191});
    assert(numel(resourceIDs)==numel(slots)*numel(resourceSet.Resources) && ...
        numel(unique(resourceIDs))==numel(resourceIDs), ...
        'sixgr:qcl:InvalidTRSResourceIDs','Declare one distinct NZP-CSI-RS ID per tracking resource.');
end
slotResources = repmat(localSlotResource(), numel(slots), 1);
mappingTables = cell(numel(slots),1);
for ii = 1:numel(slots)
    carrier = resourceSet.Carrier;
    carrier.NSlot = mod(slots(ii),double(carrier.SlotsPerFrame));
    carrier.NFrame = mod(floor(slots(ii)/double(carrier.SlotsPerFrame)),1024);
    ind=[]; sym=[]; resourceOrdinals=[];
    for resourceIndex=1:numel(resourceSet.Resources)
        resource=resourceSet.Resources{resourceIndex};
        resourceIndices=nrCSIRSIndices(carrier,resource);
        resourceSymbols=nrCSIRS(carrier,resource);
        ind=[ind;resourceIndices(:)]; %#ok<AGROW>
        sym=[sym;resourceSymbols(:)]; %#ok<AGROW>
        resourceOrdinals=[resourceOrdinals;repmat(resourceIndex-1,numel(resourceIndices),1)]; %#ok<AGROW>
    end
    assert(numel(unique(ind))==numel(ind),'sixgr:phy:trs:ResourceCollision', ...
        'Distinct tracking resources cannot occupy the same RE.');
    K = double(carrier.NSizeGrid) * 12;
    L = double(carrier.SymbolsPerSlot);
    P = double(resourceSet.CSIRS.NumCSIRSPorts);
    [sc, symIdx, portIdx] = ind2sub([K L P], double(ind(:)));
    res = localSlotResource();
    res.Slot = double(slots(ii));
    res.Carrier = carrier;
    res.Indices = ind(:);
    res.Symbols = sym(:);
    res.K = K;
    res.L = L;
    res.Ports = P;
    res.NRE = numel(ind);
    slotResources(ii, 1) = res;
    % Preserve the exact prior row order/types/values without constructing
    % one scalar struct per RE. This is also used during strict allocation
    % validation, where repeated full-band table growth dominated scheduling.
    n=numel(ind);
    ids=nan(n,1);
    if ~isempty(resourceIDs)
        ids=reshape(resourceIDs((ii-1)*numel(resourceSet.Resources)+ ...
            resourceOrdinals+1),[],1);
    end
    mappingTables{ii}=table(repmat(string(cfg.RunId),n,1), ...
        repmat(string(cfg.ConfigHash),n,1),repmat(double(slots(ii)),n,1), ...
        (1:n).',double(resourceOrdinals),double(ids),double(ind(:)), ...
        double(sc(:)-1),double(symIdx(:)-1),double(portIdx(:)-1), ...
        repmat("TRS_NZP_CSI_RS",n,1), ...
        repmat(double(resourceSet.CSIRS.RowNumber),n,1), ...
        repmat(double(resourceSet.CSIRS.NumCSIRSPorts),n,1), ...
        repmat(string(resourceSet.CSIRS.CDMType),n,1), ...
        repmat(string(resourceSet.CSIRS.Density),n,1), ...
        repmat("real_lls_evidence",n,1), ...
        'VariableNames',fieldnames(localMappingRow()).');
end

out = struct();
out.ResourceSet = resourceSet;
out.SlotResources = slotResources;
if isempty(mappingTables)
    out.ResourceMappingTable=struct2table(repmat(localMappingRow(),0,1),"AsArray",true);
else
    out.ResourceMappingTable=vertcat(mappingTables{:});
end
end

function row = localSlotResource()
row = struct("Slot", NaN, "Carrier", [], "Indices", [], "Symbols", [], ...
    "K", NaN, "L", NaN, "Ports", NaN, "NRE", NaN);
end

function row = localMappingRow()
row = struct("RunId", "", "ConfigHash", "", "Slot", NaN, "ResourceIndex", NaN, ...
    "CSIRSResourceWithinSlot0Based",NaN, ...
    "NZPCSIRSResourceID",NaN, ...
    "LinearIndex1Based", NaN, "Subcarrier0Based", NaN, "Symbol0Based", NaN, ...
    "Port0Based", NaN, "ReferenceSignal", "", "CSIRSRowNumber", NaN, ...
    "NumCSIRSPorts", NaN, "CDMType", "", "Density", "", "TruthStatus", "");
end
