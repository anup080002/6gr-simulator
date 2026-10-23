function expanded=expandExecutedResourceIntervals(T,cfg)
% Expand reporting-only RS observations to exact mapped carrier symbols.
% Original receiver tables are unchanged. This does not invent historical
% occupancy from configured RB counts or widen sparse symbols to a slot.
expanded=T;
if isempty(T) || ~ismember('ExecutedResourceIntervalsJSON',T.Properties.VariableNames), return; end
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(cfg.phy.carrier);
gridRB=double(cfg.phy.carrier.NSizeGrid);
chunks=cell(height(T),1);
for i=1:height(T)
    row=T(i,:); raw=string(row.ExecutedResourceIntervalsJSON);
    if ismissing(raw) || strlength(strtrim(raw))==0
        chunks{i}=row; continue;
    end
    assert(all(ismember({'ExecutedResourceIntervalSource','ResourceGridPRBCount', ...
        'ResourceSymbolsPerSlot'},row.Properties.VariableNames)) && ...
        any(string(row.ExecutedResourceIntervalSource)==[ ...
        "mapped_TX_grid_nonzero_PRB_symbol_union_not_RF_activity", ...
        "executed_TX_RE_runs_PRB_symbol_union_not_RF_activity", ...
        "retained_executed_TX_RE_occupancy_not_RF_activity"]) && ...
        row.ResourceGridPRBCount==gridRB && row.ResourceSymbolsPerSlot==spec.SymbolsPerSlot, ...
        'sixgr:truth:ResourceIntervalAuthorityMismatch', ...
        'Executed resource intervals must retain their actual carrier dimensions and source.');
    intervals=jsondecode(raw);
    assert(isstruct(intervals) && ~isempty(intervals) && ...
        all(isfield(intervals,{'AbsoluteSlotIndex0','SymbolIndex0','PRBSet0Based'})), ...
        'sixgr:truth:InvalidExecutedResourceIntervals', ...
        'Expected nonempty absolute-slot/symbol/PRB occupancy records.');
    pieces=cell(numel(intervals),1); keys=zeros(numel(intervals),2);
    slotBase=1;
    if ismember('SlotIndexBase',row.Properties.VariableNames)
        slotBase=double(row.SlotIndexBase);
    end
    assert(isscalar(slotBase)&&ismember(slotBase,[0 1]),'sixgr:truth:InvalidEnergySlotBase', ...
        'Explicit slot numbering must be zero-based or one-based.');
    for k=1:numel(intervals)
        r=intervals(k);
        validateattributes(r.AbsoluteSlotIndex0,{'numeric'},{'scalar','finite','integer','nonnegative'});
        validateattributes(r.SymbolIndex0,{'numeric'},{'scalar','finite','integer','nonnegative','<',spec.SymbolsPerSlot});
        validateattributes(r.PRBSet0Based,{'numeric'},{'vector','nonempty','finite','integer','nonnegative','<',gridRB});
        prbs=reshape(double(r.PRBSet0Based),1,[]);
        assert(isequal(prbs,unique(prbs,'sorted')),'sixgr:truth:NoncanonicalExecutedPRBSet', ...
            'Mapped PRB sets must be sorted, unique and carrier-relative.');
        piece=row;
        piece.Slot=r.AbsoluteSlotIndex0+slotBase;
        piece.RuntimeAbsoluteSlotIndex0=r.AbsoluteSlotIndex0;
        piece.SlotIndexBase=slotBase;
        piece.SymbolStart=r.SymbolIndex0;
        piece.NumSymbols=1;
        piece.PRBs=numel(prbs);
        piece.EnergyAllocatedPRBSetJSON=string(jsonencode(prbs));
        pieces{k}=piece;
        keys(k,:)=[r.AbsoluteSlotIndex0 r.SymbolIndex0];
    end
    assert(size(unique(keys,'rows'),1)==size(keys,1), ...
        'sixgr:truth:DuplicateExecutedSymbolInterval', ...
        'Each physical symbol must contain one union of its occupied PRBs.');
    chunks{i}=vertcat(pieces{:});
end
% Missing legacy rows need typed empty extension columns, never copied
% coordinates/PRB sets from a neighbouring measured observation.
names={'RuntimeAbsoluteSlotIndex0','SlotIndexBase','SymbolStart','NumSymbols','PRBs','EnergyAllocatedPRBSetJSON'};
for i=1:numel(chunks)
    for k=1:numel(names)
        name=names{k};
        if ismember(name,chunks{i}.Properties.VariableNames), continue; end
        value=NaN;
        if strcmp(name,'SlotIndexBase'), value=1; end
        if strcmp(name,'EnergyAllocatedPRBSetJSON'), value=""; end
        chunks{i}.(name)=repmat(value,height(chunks{i}),1);
    end
    chunks{i}=chunks{i}(:,[T.Properties.VariableNames setdiff(names,T.Properties.VariableNames,'stable')]);
end
expanded=vertcat(chunks{:});
end
