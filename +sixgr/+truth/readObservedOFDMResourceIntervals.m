function [intervals,audit]=readObservedOFDMResourceIntervals(path,expectedSHA256,carrier,readSize)
%READOBSERVEDOFDMRESOURCEINTERVALS Recover occupancy from retained TX evidence.
% Bounded-memory reader of exact per-port RE runs. No configured/planned
% allocations are accepted. This returns derived evidence, not replacement
% receiver trials, and does not infer RX activity or missing circuit states.
arguments
    path (1,1) string
    expectedSHA256 (1,1) string
    carrier
    readSize (1,1) double {mustBeInteger,mustBePositive}=8192
end
assert(isfile(path) && ~isempty(regexp(char(expectedSHA256),'^[a-f0-9]{64}$','once')), ...
    'sixgr:truth:MissingObservedResourceSnapshot','Require a retained file and expected SHA-256.');
assert(sixgr.util.sha256File(path)==expectedSHA256, ...
    'sixgr:truth:ObservedResourceHashMismatch','Resource snapshot hash does not match its receipt.');
% AbsoluteTime accepts a resolved numerology, not a Toolbox carrier object.
% Preserve the carrier's CP and symbol count: passing SCS alone would turn
% an extended-CP capture into a normal-CP accounting grid.
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct( ...
    'SubcarrierSpacing',double(carrier.SubcarrierSpacing), ...
    'CyclicPrefix',string(carrier.CyclicPrefix), ...
    'SymbolsPerSlot',double(carrier.SymbolsPerSlot)));
gridRB=double(carrier.NSizeGrid);
validateattributes(gridRB,{'numeric'},{'scalar','finite','integer','positive'});
fid=fopen(path,'rt','n','UTF-8');
assert(fid>=0,'sixgr:truth:ObservedResourceOpen','Cannot open retained resource snapshot.');
closer=onCleanup(@()fclose(fid));
header=fgetl(fid);
assert(ischar(header),'sixgr:truth:MissingObservedResourceHeader','Resource snapshot has no schema.');
parsed=textscan(erase(header,char(65279)),'%q','Delimiter',',','Whitespace','');
names=string(parsed{1}(:).'); clear closer;
required=["absolute_slot","symbol_index","subcarrier_start","subcarrier_count", ...
    "direction","channel","cell_id","ue_id","allocation_id","grid_domain", ...
    "evidence_scope","active_flag","authority"];
assert(all(ismember(required,names)),'sixgr:truth:ObservedResourceSchema', ...
    'Retained occupancy must include exact coordinates and executed-source authority.');
identity=names(ismember(names,["RunID","ExecutionID","ScenarioID","ConfigHash", ...
    "SweepPointIndex","SweepRealizationIndex","ConfiguredSNR_dB","Seed","TrialIndex", ...
    "ObservationUEIndex","ssb_index0","ra_stage","ra_attempt_id","rnti"]));
[~,~,extension]=fileparts(path);
ds=tabularTextDatastore(char(path),'FileExtensions',char(extension), ...
    'Delimiter',',','ReadSize',readSize, ...
    'TextType','string','VariableNamingRule','preserve','ReadVariableNames',false, ...
    'NumHeaderLines',1,'VariableNames',cellstr(names), ...
    'TextscanFormats',repmat({'%q'},size(names)));
ds.SelectedVariableNames=cellstr(unique([required identity],'stable'));
prototype=struct('Direction',"",'Channel',"",'CellID',NaN,'UEID',NaN, ...
    'AllocationID',"",'AbsoluteSlotIndex0',NaN,'SymbolIndex0',NaN, ...
    'ResourceGridPRBCount',gridRB,'ResourceSymbolsPerSlot',spec.SymbolsPerSlot, ...
    'PRBSet0BasedJSON',"",'PopulationScopeJSON',"",'SourceRowCount',0, ...
    'SourceSHA256',expectedSHA256,'Source',"retained_executed_TX_RE_occupancy_not_RF_activity");
map=containers.Map('KeyType','char','ValueType','any');
audit=struct('SourceSHA256',expectedSHA256,'SourceRows',0,'MaxChunkRows',0, ...
    'IntervalRows',0,'ReceiverActivityInferred',false,'OriginalFilesChanged',false, ...
    'EvidenceType',"derived_executed_TX_occupancy_not_energy_or_performance_qualification");
while hasdata(ds)
    T=read(ds); n=height(T);
    audit.SourceRows=audit.SourceRows+n;
    audit.MaxChunkRows=max(audit.MaxChunkRows,n);
    assert(all(string(T.grid_domain)=="carrier_cp_ofdm") && ...
        all(string(T.evidence_scope)=="runtime_observed_tx_occupancy") && ...
        all(str2double(string(T.active_flag))==1) && ...
        all(strlength(string(T.authority))>0 & ~ismissing(string(T.authority))), ...
        'sixgr:truth:NonExecutedOFDMResourceEvidence', ...
        'Only actual active carrier-OFDM occupancy is accepted; PRACH native clocks need their separate adapter.');
    slot=str2double(T.absolute_slot); symbol=str2double(T.symbol_index);
    first=str2double(T.subcarrier_start); count=str2double(T.subcarrier_count);
    coordinates=[slot symbol first count];
    assert(all(isfinite(coordinates)&coordinates==fix(coordinates),'all') && ...
        all(slot>=0 & symbol>=0 & symbol<spec.SymbolsPerSlot & first>=0 & ...
        count>0 & first+count<=12*gridRB), ...
        'sixgr:truth:InvalidObservedResourceCoordinates','Executed RE runs leave the declared carrier grid.');
    % JSON encoding prevents delimiter collisions in allocation identifiers.
    keyColumns=["direction","channel","cell_id","ue_id","allocation_id", ...
        "absolute_slot","symbol_index",identity];
    values=strings(n,numel(keyColumns));
    for k=1:numel(keyColumns)
        values(:,k)=string(T.(keyColumns(k)));
    end
    values(ismissing(values))="";
    [groups,~,member]=unique(values,'rows','stable');
    for g=1:size(groups,1)
        selected=find(member==g); j=selected(1);
        key=char(jsonencode(cellstr(groups(g,:))));
        if isKey(map,key)
            saved=map(key);
        else
            r=prototype;
            r.Direction=values(j,1); r.Channel=values(j,2);
            r.CellID=str2double(values(j,3)); r.UEID=str2double(values(j,4));
            r.AllocationID=values(j,5); r.AbsoluteSlotIndex0=slot(j); r.SymbolIndex0=symbol(j);
            assert(strlength(r.AllocationID)>0 && any(r.Direction==["DL","UL"]), ...
                'sixgr:truth:MissingObservedAllocationIdentity','Actual allocation identity and direction are mandatory.');
            scope=struct();
            for k=1:numel(identity), scope.(identity(k))=values(j,7+k); end
            r.PopulationScopeJSON=string(jsonencode(scope));
            saved=struct('Row',r,'Mask',false(1,gridRB));
        end
        % Deduplicate ports and contiguous runs before updating the tiny
        % per-symbol PRB mask. No RE power or port count is synthesized.
        ranges=unique([floor(first(selected)/12),floor((first(selected)+count(selected)-1)/12)],'rows');
        for k=1:size(ranges,1), saved.Mask(ranges(k,1)+1:ranges(k,2)+1)=true; end
        saved.Row.SourceRowCount=saved.Row.SourceRowCount+numel(selected);
        map(key)=saved;
    end
end
assert(sixgr.util.sha256File(path)==expectedSHA256, ...
    'sixgr:truth:ObservedResourceHashMismatch','Retained resource snapshot changed during recovery.');
rows=repmat(prototype,map.Count,1); keys=sort(string(map.keys));
for k=1:numel(keys)
    saved=map(char(keys(k)));
    saved.Row.PRBSet0BasedJSON=string(jsonencode(find(saved.Mask)-1));
    rows(k)=saved.Row;
end
intervals=struct2table(prototype); intervals=intervals([],:);
if ~isempty(rows), intervals=struct2table(rows); end
audit.IntervalRows=height(intervals);
end
