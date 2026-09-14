function snapshot=snapshotHARQSchedulingState(entity)
% Read-only diagnostic projection, not a restorable full HARQ checkpoint.
snapshot=struct('Schema',"harq_scheduling_diagnostic/v1", ...
    'Available',false,'EntityClass',"",'Direction',"",'NumProcesses',NaN, ...
    'MaxRetx',NaN,'RVSequence',[],'UEList',[],'Processes',{{}},'Stats',struct(), ...
    'ExcludedEntityFields',["Logger","DeliveryLedger","StoreTB","StaleProcessTimeoutSlots"], ...
    'ExcludedProcessFields',["TB","LastGrant","TBContext","SoftBuffer"]);
if isempty(entity), return; end
assert(isa(entity,'sixgr.l2.mac.HARQEntity') && isscalar(entity), ...
    'sixgr:report:InvalidHARQDiagnosticEntity','Expected one live HARQ entity or explicit absence.');
snapshot.Available=true;
snapshot.EntityClass=string(class(entity));
snapshot.Direction=string(entity.Direction);
snapshot.NumProcesses=entity.NumProcesses;
snapshot.MaxRetx=entity.MaxRetx;
snapshot.RVSequence=entity.RVSequence;
snapshot.UEList=entity.UEList;
snapshot.Stats=entity.Stats;
names=["Active","NDI","NDIEpoch","RVIdx","RV","TxCount", ...
    "AwaitingFeedback","NeedsRetx","TBSBytes","LastTxSlot","FirstTxSlot", ...
    "TBIdentity","LastDropReason","SoftBufferKey"];
snapshot.Processes=cell(size(entity.UEProcs));
for index=1:numel(entity.UEProcs)
    source=entity.UEProcs{index};
    assert(isstruct(source) && all(isfield(source,names)), ...
        'sixgr:report:MissingHARQDiagnosticFields','Retain the defined scheduling lifecycle fields.');
    excluded=setdiff(string(fieldnames(source)),names,'stable');
    snapshot.Processes{index}=rmfield(source,cellstr(excluded));
    snapshot.ExcludedProcessFields=union(snapshot.ExcludedProcessFields,excluded','stable');
end
localRequireValues(snapshot);
end

function localRequireValues(value)
if isstruct(value)
    for index=1:numel(value)
        for name=string(fieldnames(value))'
            localRequireValues(value(index).(name));
        end
    end
elseif iscell(value)
    for index=1:numel(value), localRequireValues(value{index}); end
else
    assert(isnumeric(value)||islogical(value)||ischar(value)||isstring(value), ...
        'sixgr:report:NonValueHARQDiagnosticField','Do not serialize handles or opaque objects in this projection.');
end
end
