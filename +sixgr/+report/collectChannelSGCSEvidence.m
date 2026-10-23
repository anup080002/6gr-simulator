function result=collectChannelSGCSEvidence(runRoot,dl,ul)
% Recompute SGCS from immutable paired channel resources, never condition
% number, applied rank, a beam index, or a configured-SNR proxy. Read-only.
% Each observation keeps its own point/seed/reference plane; no pooling.
root=string(java.io.File(char(runRoot)).getCanonicalPath());
records=struct([]);
tables={dl,ul}; directions=["DL","UL"]; channels=["PDSCH","PUSCH"];
for d=1:2
    trials=tables{d};
    if ~istable(trials) || isempty(trials), continue; end
    names=string(trials.Properties.VariableNames);
    if ~ismember('ChannelEstimateResourcesCSV',names), continue; end
    for k=1:height(trials)
        trial=trials(k,:);
        relative=string(trial.ChannelEstimateResourcesCSV);
        if ismissing(relative) || strlength(strtrim(relative))==0, continue; end
        row=localObservation(root,trial,relative,channels(d));
        row.Direction=directions(d);
        if isempty(records), records=row; else, records(end+1)=row; end %#ok<AGROW>
    end
end
if isempty(records)
    result=struct2table(localPrototype()); result(1,:)=[];
else
    result=struct2table(records);
end
end

function row=localObservation(root,trial,relative,channel)
names=string(trial.Properties.VariableNames);
required=["ChannelEstimateResourcesCSVSHA256","ChannelEstimateObservationID", ...
    "ChannelEstimateComparedValues","ChannelEstimateReferencePlane", ...
    "Slot","UEIndex","ConfiguredSNR_dB"];
assert(all(ismember(required,names)), 'sixgr:report:SGCSBinding', ...
    'A declared channel-resource artifact must retain its complete observation binding.');
portable=replace(relative,'\','/');
assert(~isempty(regexp(char(portable),'^channel_estimation/csv/[^/]+\.csv$','once')), ...
    'sixgr:report:SGCSRunScope','Channel resources must be run-relative channel_estimation/csv artifacts.');
target=string(java.io.File(char(fullfile(root,relative))).getCanonicalPath());
assert(startsWith(target,root+filesep,'IgnoreCase',ispc), ...
    'sixgr:report:SGCSRunScope','Do not borrow measurements from another run.');
assert(isfile(target),'sixgr:report:SGCSMissingResource','Missing declared channel-resource artifact %s.',relative);
digest=string(trial.ChannelEstimateResourcesCSVSHA256);
assert(isscalar(digest) && ~ismissing(digest) && ...
    ~isempty(regexp(char(digest),'^[0-9a-f]{64}$','once')) && ...
    string(sixgr.util.sha256File(target))==digest, ...
    'sixgr:report:SGCSChecksum','Channel-resource checksum mismatch.');
T=sixgr.util.csvReadTable(target,'TextType','string');
assert(string(sixgr.util.sha256File(target))==digest, ...
    'sixgr:report:SGCSChecksum','Channel resources changed while being read.');
resourceFields=["Channel","Slot","UEIndex","ConfiguredSNR_dB", ...
    "SubcarrierIndex0","SymbolIndex0","RxBranchIndex0","ReferencePortIndex0", ...
    "HReal","HImag","ReferenceHReal","ReferenceHImag", ...
    "ChannelEstimateObservationID","ChannelReferencePlane", ...
    "ChannelEstimateSource","ChannelReferenceSource", ...
    "ReferenceUsedByReceiver","GainOrPhaseFitted"];
assert(~isempty(T) && all(ismember(resourceFields,string(T.Properties.VariableNames))), ...
    'sixgr:report:SGCSResourceSchema','Complete paired resource values and provenance are required.');
id=string(trial.ChannelEstimateObservationID); plane=string(trial.ChannelEstimateReferencePlane);
assert(~ismissing(id) && strlength(id)>0 && ~ismissing(plane) && strlength(plane)>0 && ...
    all(string(T.ChannelEstimateObservationID)==id) && all(string(T.Channel)==channel) && ...
    all(string(T.ChannelReferencePlane)==plane), ...
    'sixgr:report:SGCSObservationIdentity','The paired resources belong to a different channel/observation/plane.');
for field=["Slot","UEIndex","ConfiguredSNR_dB"]
    v=sixgr.truth.numericMeasurementColumn(T.(field),field);
    expected=sixgr.truth.numericMeasurementColumn(trial.(field),field);
    assert(isequaln(v,repmat(expected,height(T),1)), ...
        'sixgr:report:SGCSObservationIdentity','Resource %s differs from its owning trial.',field);
end
count=sixgr.truth.numericMeasurementColumn(trial.ChannelEstimateComparedValues,'ChannelEstimateComparedValues');
indices=zeros(height(T),4); fields=["SubcarrierIndex0","SymbolIndex0","RxBranchIndex0","ReferencePortIndex0"];
for i=1:4, indices(:,i)=sixgr.truth.numericMeasurementColumn(T.(fields(i)),fields(i)); end
assert(isscalar(count) && isfinite(count) && count>0 && count==height(T) && ...
    all(isfinite(indices),'all') && all(indices>=0 & indices==fix(indices),'all') && ...
    size(unique(indices,'rows'),1)==height(T), ...
    'sixgr:report:SGCSPopulation','Every paired pilot/branch/port value must occur exactly once.');
for field=["ReferenceUsedByReceiver","GainOrPhaseFitted"]
    v=sixgr.truth.numericMeasurementColumn(T.(field),field);
    assert(all(isfinite(v) & v==0),'sixgr:report:SGCSReferenceLeakage', ...
        'Independent scoring cannot use a receiver reference oracle or fitted channel values.');
end
for field=["ChannelEstimateSource","ChannelReferenceSource"]
    v=unique(string(T.(field)));
    assert(isscalar(v) && ~ismissing(v) && strlength(v)>0, ...
        'sixgr:report:SGCSResourceSchema','One explicit %s is required per observation.',field);
end
h=complex(sixgr.truth.numericMeasurementColumn(T.HReal,'HReal'), ...
    sixgr.truth.numericMeasurementColumn(T.HImag,'HImag'));
r=complex(sixgr.truth.numericMeasurementColumn(T.ReferenceHReal,'ReferenceHReal'), ...
    sixgr.truth.numericMeasurementColumn(T.ReferenceHImag,'ReferenceHImag'));
s=sixgr.phy.rx.squaredGeneralizedCosineSimilarity(h,r);
row=localPrototype(); row.Channel=channel;
row.Slot=double(trial.Slot); row.UEIndex=double(trial.UEIndex);
row.ConfiguredSNR_dB=double(trial.ConfiguredSNR_dB);
row.ChannelEstimateObservationID=id;
row.ChannelSGCS=s.Value; row.ChannelSGCSAvailable=s.Available;
row.ChannelSGCSStatus=s.Status; row.ChannelSGCSDefinition=s.Definition;
row.ChannelSGCSEstimateEnergy=s.EstimateEnergy; row.ChannelSGCSReferenceEnergy=s.ReferenceEnergy;
row.ChannelSGCSInnerProductReal=s.InnerProductReal; row.ChannelSGCSInnerProductImag=s.InnerProductImag;
row.ChannelSGCSComparedValues=s.ComparedValues;
row.ChannelSGCSReferencePlane=plane; row.ChannelSGCSReferenceSource=string(T.ChannelReferenceSource(1));
row.ChannelEstimateSource=string(T.ChannelEstimateSource(1));
row.ChannelEstimateResourcesCSV=portable; row.ChannelEstimateResourcesCSVSHA256=digest;
for field=["SweepPointIndex","Seed"]
    if ismember(field,names), row.(field)=sixgr.truth.numericMeasurementColumn(trial.(field),field); end
end
for field=["ExecutionID","ConfigHash"]
    if ismember(field,names), row.(field)=string(trial.(field)); end
end
% Old captures may lack trial SGCS while retaining all exact paired values.
% New producer fields, when present, must agree with independent readback.
for field=string(fieldnames(row)).'
    if ~startsWith(field,"ChannelSGCS") || ~ismember(field,names), continue; end
    expected=row.(field); actual=trial.(field);
    if isstring(expected)
        valid=isequal(string(actual),expected);
    else
        actual=sixgr.truth.numericMeasurementColumn(actual,field);
        valid=isequaln(actual,double(expected));
        if isfinite(expected) && isfinite(actual)
            valid=abs(actual-double(expected))<=256*eps(max(abs([actual double(expected)])));
        end
    end
    assert(valid,'sixgr:report:SGCSOperandClosure', ...
        'Published %s disagrees with independently read paired channel resources.',field);
end
end

function row=localPrototype()
row=struct('Direction',"",'Channel',"",'Slot',NaN,'UEIndex',NaN, ...
    'ConfiguredSNR_dB',NaN,'SweepPointIndex',NaN,'Seed',NaN,'ExecutionID',"",'ConfigHash',"", ...
    'ChannelEstimateObservationID',"",'ChannelSGCS',NaN,'ChannelSGCSAvailable',false, ...
    'ChannelSGCSStatus',"",'ChannelSGCSDefinition',"", ...
    'ChannelSGCSVectorization',"all_executed_pilot_resources_receive_branches_and_logical_ports", ...
    'ChannelSGCSEstimateEnergy',NaN,'ChannelSGCSReferenceEnergy',NaN, ...
    'ChannelSGCSInnerProductReal',NaN,'ChannelSGCSInnerProductImag',NaN, ...
    'ChannelSGCSComparedValues',NaN,'ChannelSGCSReferencePlane',"", ...
    'ChannelSGCSReferenceSource',"",'ChannelEstimateSource',"", ...
    'ChannelEstimateResourcesCSV',"",'ChannelEstimateResourcesCSVSHA256',"", ...
    'ReferenceUsedByReceiver',false,'GainOrPhaseFitted',false);
end
