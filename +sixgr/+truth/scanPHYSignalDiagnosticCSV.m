function summary=scanPHYSignalDiagnosticCSV(filePath,readSize)
% Validate EVERY source row with bounded import memory, not a preview cap.
% The lossless source CSV remains authoritative. Only panel counts, identity
% consistency and availability are reduced here; no measurements are made.
if nargin<2, readSize=8192; end
validateattributes(readSize,{'numeric'},{'scalar','integer','positive','finite'});
summary=struct('Present',false,'Columns',strings(1,0),'RowCount',0, ...
    'MaxChunkRows',0,'PanelSeriesCounts',table(), ...
    'TruthOK',true,'ConstructionOK',true,'SourceOK',true, ...
    'StatusOK',true,'DirectionOK',true);
emptyDirection=struct('RowCount',0,'SnapshotIDs',strings(0,1), ...
    'SnapshotMissing',false,'Panels',strings(0,1), ...
    'Tuple',strings(1,0),'TupleConsistent',true);
summary.DL=emptyDirection; summary.UL=emptyDirection;
if ~isfile(filePath), return; end
summary.Present=true;
% Supply the schema before datastore construction: a legitimate header-only
% artifact has no first data row from which formats could be inferred.
fid=fopen(filePath,'rt','n','UTF-8');
assert(fid>=0,'sixgr:truth:DiagnosticCSVOpen','Cannot open diagnostic source.');
closeHeader=onCleanup(@() fclose(fid));
header=fgetl(fid);
if ~ischar(header), return; end
header=erase(header,char(65279));
parsed=textscan(header,'%q','Delimiter',',','Whitespace','');
names=string(parsed{1}(:).'); summary.Columns=names;
clear closeHeader;
if isempty(names), return; end
ds=tabularTextDatastore(char(filePath),'Delimiter',',','ReadSize',readSize, ...
    'TextType','string','VariableNamingRule','preserve','ReadVariableNames',false, ...
    'NumHeaderLines',1,'VariableNames',cellstr(names), ...
    'TextscanFormats',repmat({'%q'},size(names)));
% %q parses quoted CSV (including embedded commas/newlines) and prevents
% hex hashes or an early numeric row from controlling later string import.
tupleColumns=["Frame","Slot","UEIndex","RNTI","TBId"];
needed=["SnapshotID","Panel","Series","Direction","CurveConstruction", ...
    "truth_status","SourceArtifact","Status",tupleColumns];
selected=names(ismember(names,needed));
if isempty(selected), selected=names(1); end
ds.SelectedVariableNames=cellstr(selected);
countMap=containers.Map('KeyType','char','ValueType','double');
while hasdata(ds)
    T=read(ds); n=height(T);
    summary.RowCount=summary.RowCount+n;
    summary.MaxChunkRows=max(summary.MaxChunkRows,n);
    summary.TruthOK=summary.TruthOK && localAll(T,'truth_status','real_lls_evidence');
    summary.ConstructionOK=summary.ConstructionOK && ...
        localAll(T,'CurveConstruction','runtime_same_trial_phy_signal_snapshot');
    summary.SourceOK=summary.SourceOK && localAll(T,'SourceArtifact','runtime_phy_arrays_same_trial');
    summary.StatusOK=summary.StatusOK && localAll(T,'Status','available');
    directions=upper(localText(T,'Direction'));
    summary.DirectionOK=summary.DirectionOK && all(ismember(directions,["DL","UL"]));
    panel=lower(localText(T,'Panel')); series=lower(localText(T,'Series'));
    pairs=unique([panel series],'rows','stable');
    for j=1:size(pairs,1)
        key=char(jsonencode(cellstr(pairs(j,:))));
        count=sum(panel==pairs(j,1) & series==pairs(j,2));
        if isKey(countMap,key), count=count+countMap(key); end
        countMap(key)=count;
    end
    for direction=["DL","UL"]
        mask=directions==direction;
        if ~any(mask), continue; end
        d=summary.(direction); d.RowCount=d.RowCount+sum(mask);
        ids=strtrim(localText(T(mask,:),'SnapshotID'));
        d.SnapshotMissing=d.SnapshotMissing || any(strlength(ids)==0);
        ids=unique([d.SnapshotIDs;ids(strlength(ids)>0)],'stable');
        % Two distinct IDs suffice to preserve a failed uniqueness check.
        d.SnapshotIDs=ids(1:min(2,numel(ids)));
        d.Panels=unique([d.Panels;panel(mask)],'stable');
        if ~all(ismember(tupleColumns,names)), d.TupleConsistent=false; end
        if d.TupleConsistent
            values=strings(sum(mask),numel(tupleColumns));
            for j=1:numel(tupleColumns)
                values(:,j)=strtrim(localText(T(mask,:),tupleColumns(j)));
            end
            if isempty(d.Tuple), d.Tuple=values(1,:); end
            invalid=strlength(values)==0 | ismember(lower(values),["nan","missing","<missing>"]);
            d.TupleConsistent=~any(invalid,'all') && all(values==d.Tuple,'all');
        end
        summary.(direction)=d;
    end
end
keys=countMap.keys;
Panel=strings(numel(keys),1); Series=Panel; RowCount=zeros(numel(keys),1);
for j=1:numel(keys)
    pair=string(jsondecode(keys{j})); Panel(j)=pair(1); Series(j)=pair(2);
    RowCount(j)=countMap(keys{j});
end
summary.PanelSeriesCounts=table(Panel,Series,RowCount);
end

function values=localText(T,name)
if ismember(string(name),string(T.Properties.VariableNames))
    values=strtrim(string(T.(name))); values(ismissing(values))="";
else
    values=repmat("",height(T),1);
end
end
function tf=localAll(T,name,value)
tf=all(lower(localText(T,name))==string(value));
end
