function [bound,audit,unbound]=bindObservedResourcesToTrials(raw,cfg,R,configHash,sourceHash)
% Bind compact, hash-verified TX occupancy to reporting copies of RX rows.
% Caller verifies the retained file hashes before supplying R. This adapter
% never changes receiver outcomes, invents trials, or infers RF active time.
% Legacy allocation keys below are the committed producer contracts, not a
% nearest-slot join. Ambiguous identities remain unbound.
arguments
    raw (1,1) struct
    cfg (1,1) struct
    R table
    configHash (1,1) string
    sourceHash (1,1) string
end
bound=raw;
required={'Direction','Channel','CellID','UEID','AllocationID','AbsoluteSlotIndex0', ...
    'SymbolIndex0','ResourceGridPRBCount','ResourceSymbolsPerSlot', ...
    'PRBSet0BasedJSON','PopulationScopeJSON','SourceSHA256','Source'};
assert(all(ismember(required,R.Properties.VariableNames)) && ...
    all(string(R.Source)=="retained_executed_TX_RE_occupancy_not_RF_activity") && ...
    all(string(R.SourceSHA256)==sourceHash) && ...
    ~isempty(regexp(char(sourceHash),'^[a-f0-9]{64}$','once')), ...
    'sixgr:truth:ResourceBindingAuthority','Require verified executed occupancy and its source identity.');
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(cfg.phy.carrier);
assert(all(R.ResourceGridPRBCount==cfg.phy.carrier.NSizeGrid) && ...
    all(R.ResourceSymbolsPerSlot==spec.SymbolsPerSlot), ...
    'sixgr:truth:ResourceBindingCarrier','Resource grid differs from executed carrier.');
scope=cell(height(R),1);
for j=1:height(R)
    scope{j}=jsondecode(string(R.PopulationScopeJSON(j)));
    assert(isfield(scope{j},'ConfigHash') && string(scope{j}.ConfigHash)==configHash, ...
        'sixgr:truth:ResourceBindingScope','Retained resources belong to a different configuration.');
end
prototype=struct('Domain',"",'TrialRow',NaN,'Slot',NaN,'AllocationIDsJSON',"", ...
    'BoundIntervalCount',0,'Status',"",'SourceSHA256',sourceHash);
rows=repmat(prototype,0,1); used=false(height(R),1);
domains=["DL","UL","PBCH","PDCCH","PUCCH","SRS","CSIRS","TRS"];
channels=["PDSCH","PUSCH","SSB","PDCCH","PUCCH","SRS","CSI-RS","TRS"];
for d=1:numel(domains)
    domain=domains(d);
    if ~isfield(raw,domain) || isempty(raw.(domain)), continue; end
    if domain=="PBCH" && sixgr.util.structGet(cfg,'phy.ssb.scs_kHz', ...
            sixgr.util.structGet(cfg,'phy.ssb.timing.SSBSubcarrierSpacingKHz',cfg.phy.carrier.SubcarrierSpacing)) ...
            ~=cfg.phy.carrier.SubcarrierSpacing
        % The native SSB binder owns this population. Never require its
        % 30-kHz symbols to appear in a 15-kHz carrier-coordinate ledger.
        continue;
    end
    T=raw.(domain);
    assert(istable(T),'sixgr:truth:ResourceBindingTable','Expected raw receiver table.');
    defaults=sixgr.truth.executedResourceIntervals();
    for name=string(fieldnames(defaults)).'
        if ~ismember(name,T.Properties.VariableNames)
            T.(name)=repmat(defaults.(name),height(T),1);
        end
    end
    T.ResourceBindingSourceSHA256=repmat(sourceHash,height(T),1);
    T.ResourceBindingStatus=repmat("no_exact_resource_identity",height(T),1);
    for i=1:height(T)
        row=T(i,:); a=prototype; a.Domain=domain; a.TrialRow=i;
        a.Slot=number(row,"Slot");
        assert(textValue(row,"ConfigHash")==configHash, ...
            'sixgr:truth:ResourceBindingScope', ...
            'Receiver %s row %d (slot %g) ConfigHash=%s does not match executed resources ConfigHash=%s.', ...
            domain,i,a.Slot,textValue(row,"ConfigHash"),configHash);
        cellID=number(row,["CellID","BaseStationID","ServingCell"]);
        ue=number(row,["UEIndex","UEID"]);
        slotBase=number(row,"SlotIndexBase");
        if isnan(slotBase), slotBase=1; end
        slot0=a.Slot-slotBase;
        assert(ismember(slotBase,[0 1]) && isfinite(slot0) && slot0>=0 && slot0==fix(slot0), ...
            'sixgr:truth:ResourceBindingClock','Require an explicit, valid absolute trial clock.');
        mask=string(R.Channel)==channels(d) & R.CellID==cellID;
        [mask,identityStatus]=selectIdentity(R,scope,mask,row,domain,slot0,cellID,ue,spec);
        selected=find(mask);
        if ~isempty(selected)
            expectedDirection="DL";
            if any(domain==["UL","PUCCH","SRS"]), expectedDirection="UL"; end
            assert(all(string(R.Direction(selected))==expectedDirection), ...
                'sixgr:truth:ResourceBindingDirection','Physical channel direction differs from its resource ledger.');
            for j=reshape(selected,1,[])
                broadcast=any(domain==["PBCH","CSIRS","TRS"]);
                assert((broadcast && isnan(R.UEID(j))) || R.UEID(j)==ue, ...
                    'sixgr:truth:ResourceBindingUE','Allocation is owned by another UE.');
                checkPopulation(row,scope{j});
            end
            S=R(selected,:);
            entries=repmat(struct('AbsoluteSlotIndex0',NaN,'SymbolIndex0',NaN,'PRBSet0Based',[]),height(S),1);
            for j=1:height(S)
                entries(j).AbsoluteSlotIndex0=S.AbsoluteSlotIndex0(j);
                entries(j).SymbolIndex0=S.SymbolIndex0(j);
                entries(j).PRBSet0Based=jsondecode(string(S.PRBSet0BasedJSON(j)));
            end
            candidate=row;
            candidate.ExecutedResourceIntervalsJSON=string(jsonencode(entries));
            candidate.ExecutedResourceIntervalSource="retained_executed_TX_RE_occupancy_not_RF_activity";
            candidate.ResourceGridPRBCount=cfg.phy.carrier.NSizeGrid;
            candidate.ResourceSymbolsPerSlot=spec.SymbolsPerSlot;
            % The shared validator rejects duplicate clocks and malformed
            % PRB sets before they can enter endpoint power accounting.
            recovered=sixgr.truth.expandExecutedResourceIntervals(candidate,cfg);
            if hasText(row.ExecutedResourceIntervalsJSON)
                existing=sixgr.truth.expandExecutedResourceIntervals(row,cfg);
                names={'RuntimeAbsoluteSlotIndex0','SymbolStart','EnergyAllocatedPRBSetJSON'};
                assert(isequal(sortrows(existing(:,names)),sortrows(recovered(:,names))), ...
                    'sixgr:truth:ResourceBindingConflict','Producer and retained occupancy disagree.');
                identityStatus="producer_evidence_matches_retained_occupancy";
            else
                for name=string(fieldnames(defaults)).'
                    T.(name)(i)=candidate.(name);
                end
                identityStatus="bound_exact_executed_resource_identity";
            end
            used(selected)=true;
            a.AllocationIDsJSON=string(jsonencode(unique(string(S.AllocationID),'stable')));
            a.BoundIntervalCount=height(S);
        end
        T.ResourceBindingStatus(i)=identityStatus;
        a.Status=identityStatus; rows(end+1)=a; %#ok<AGROW>
    end
    bound.(domain)=T;
end
audit=struct2table(prototype); audit=audit([],:);
if ~isempty(rows), audit=struct2table(rows); end
unbound=R(~used,:);
end

function [mask,status]=selectIdentity(R,scope,mask,row,domain,slot0,cellID,ue,spec)
status="no_exact_resource_identity";
explicit=textValue(row,"ExecutedAllocationID");
if hasText(explicit)
    mask=mask & string(R.AllocationID)==explicit;
elseif any(domain==["DL","UL"])
    mask=mask & string(R.AllocationID)==textValue(row,"GrantContextId") & R.AbsoluteSlotIndex0==slot0;
elseif domain=="PDCCH"
    control=number(row,"DecodedDCIControlAbsoluteSlot");
    data=number(row,"DecodedDCIDataAbsoluteSlot"); rnti=number(row,"RNTI");
    direction=textValue(row,"GrantDirection");
    if ~all(isfinite([control data rnti ue])) || control~=slot0 || ~any(direction==["DL","UL"])
        mask(:)=false; return;
    end
    key=compose("pdcch_%s_ue_%d_rnti_%d_control_%d_data_%d",direction,ue,rnti,control+1,data+1);
    mask=mask & string(R.AllocationID)==key & R.AbsoluteSlotIndex0==control;
elseif domain=="CSIRS"
    mask=mask & string(R.AllocationID)==compose("csirs_cell_%d_slot_%d",cellID,slot0) & R.AbsoluteSlotIndex0==slot0;
elseif domain=="SRS"
    mask=mask & string(R.AllocationID)==compose("srs_slot_%d",slot0) & R.AbsoluteSlotIndex0==slot0;
elseif domain=="PUCCH"
    keys=[compose("pucch_slot_%d_ue_%d",slot0,ue),compose("pucch_csi_slot_%d_ue_%d",slot0,ue)];
    mask=mask & ismember(string(R.AllocationID),keys) & R.AbsoluteSlotIndex0==slot0;
elseif domain=="PBCH"
    beam=number(row,"SSBIndex"); actualSlot=number(row,"SSBCandidateCarrierSlot0Based");
    first=number(row,"SSBCandidateSymbolWithinSlot0Based");
    beamMask=false(height(R),1);
    for j=reshape(find(mask),1,[])
        beamMask(j)=isfield(scope{j},'ssb_index0') && str2double(string(scope{j}.ssb_index0))==beam;
    end
    mask=mask & beamMask & R.AbsoluteSlotIndex0==actualSlot;
    ids=unique(string(R.AllocationID(mask & R.SymbolIndex0==first)));
    mask=mask & ismember(string(R.AllocationID),ids);
elseif domain=="TRS"
    % A TRS receiver observation can contain resources in multiple slots.
    % Its actual capture window, not completion/delivery time, bounds them.
    start=number(row,"ObservationStartSample"); stop=number(row,"ObservationEndSampleExclusive");
    fs=number(row,"ObservationSampleRateHz");
    if ~all(isfinite([start stop fs])) || fs<=0 || stop<=start
        mask(:)=false; return;
    end
    for j=reshape(find(mask),1,[])
        t=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(R.AbsoluteSlotIndex0(j),R.SymbolIndex0(j),spec);
        e=t.plusSymbols(1,spec);
        mask(j)=t.seconds()*fs>=start-1e-6 && e.seconds()*fs<=stop+1e-6 && ...
            R.AbsoluteSlotIndex0(j)>=slot0 && ...
            string(R.AllocationID(j))==compose("trs_slot_%d",R.AbsoluteSlotIndex0(j));
    end
end
if domain~="TRS" && numel(unique(string(R.AllocationID(mask))))>1
    mask(:)=false; status="ambiguous_executed_resource_identity";
end
end

function checkPopulation(row,s)
for field=["RunID","ExecutionID","ScenarioID","SweepPointIndex","SweepRealizationIndex", ...
        "ConfiguredSNR_dB","Seed","TrialIndex"]
    if ~isfield(s,field) || ~ismember(field,row.Properties.VariableNames), continue; end
    left=textValue(row,field); right=string(s.(field));
    if hasText(left) && hasText(right)
        assert(left==right,'sixgr:truth:ResourceBindingPopulation','Resource and receiver population differ: %s.',field);
    end
end
end

function value=number(row,names)
value=NaN;
for name=names
    if ~ismember(name,row.Properties.VariableNames), continue; end
    x=str2double(string(row.(name)));
    if isscalar(x)&&isfinite(x), value=x; return; end
end
end

function value=textValue(row,name)
value="";
if ismember(name,row.Properties.VariableNames), value=string(row.(name)); end
end

function tf=hasText(value)
tf=isscalar(value) && ~ismissing(value) && strlength(strtrim(value))>0 && ...
    ~any(lower(value)==["nan","na","unavailable"]);
end
