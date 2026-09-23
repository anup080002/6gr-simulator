function groups = groupReceiverTimeSeries(T)
%GROUPRECEIVERTIMESERIES Keep separate receivers/sweep clocks in plots.
% Return original row indices; do not pool, average or replace measurements.
arguments
    T table
end
groups=repmat(struct('Direction',"",'Label',"",'Rows',[]),0,1);
if isempty(T) || ~ismember('Direction',T.Properties.VariableNames), return; end
keys=table(upper(string(T.Direction)),'VariableNames',{'Direction'});
fields=["UeId" "CellId" "SweepPointIndex" "ConfiguredSNR_dB"];
labels=[" UE=" " cell=" " point=" " reference_dB="];
for field=fields
    if ismember(field,string(T.Properties.VariableNames))
        keys.(field)=string(T.(field));
        keys.(field)(ismissing(keys.(field)))="<unavailable>";
    end
end
groupID=findgroups(keys);
for id=reshape(unique(groupID(isfinite(groupID)),'stable'),1,[])
    rows=find(groupID==id); first=rows(1);
    direction=keys.Direction(first);
    if ~ismember(direction,["DL" "UL"]), continue; end
    label=direction;
    for k=1:numel(fields)
        if ismember(fields(k),string(keys.Properties.VariableNames))
            label=label+labels(k)+keys.(fields(k))(first);
        end
    end
    groups(end+1,1)=struct('Direction',direction,'Label',label,'Rows',rows); %#ok<AGROW>
end
end
