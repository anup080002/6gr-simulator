classdef CrossDomainCausalityLedger
    %CROSSDOMAINCAUSALITYLEDGER Build edges only from observed artifact rows.
    methods (Static)
        function T = build(ctx)
            registry = ctx.Profile.SelectedArtifactRegistry;
            rows = repmat(localEmpty(),0,1);
            eventIndex = 0;
            previous = struct();
            for index = 1:height(registry)
                if registry.ArtifactType(index) ~= "CSV" || ...
                        startsWith(registry.FileName(index),"full_stack_")
                    continue;
                end
                path = localFindUniqueOrEmpty(ctx.RunFolder, ...
                    registry.FileName(index));
                if strlength(path)==0, continue; end
                try
                    Tsrc = readtable(path,"TextType","string", ...
                        "VariableNamingRule","preserve");
                catch
                    continue;
                end
                if isempty(Tsrc), continue; end
                ids = localEventIDs(Tsrc,registry.ArtifactID(index));
                times = localEventTimes(Tsrc);
                domain = string(registry.Domain(index));
                take = min(height(Tsrc),25);
                for rowIndex=1:take
                    current = struct("ID",ids(rowIndex),"Layer",domain, ...
                        "Time",times(rowIndex));
                    if ~isempty(fieldnames(previous))
                        eventIndex=eventIndex+1;
                        timeValid = ~isfinite(previous.Time) || ...
                            ~isfinite(current.Time) || current.Time>=previous.Time;
                        identityValid = strlength(previous.ID)>0 && ...
                            strlength(current.ID)>0;
                        passed=timeValid&&identityValid;
                        rows(end+1,1)=struct( ... %#ok<AGROW>
                            "RunID",char(ctx.RunID), ...
                            "CausalityID",char("CAUSE-"+compose("%05d",eventIndex)), ...
                            "SourceEventID",char(previous.ID), ...
                            "SourceLayer",char(previous.Layer), ...
                            "DestinationEventID",char(current.ID), ...
                            "DestinationLayer",char(current.Layer), ...
                            "TimeOrderValid",logical(timeValid), ...
                            "IdentityValid",logical(identityValid), ...
                            "Status",char(localStatus(passed)), ...
                            "FailureCode",char(localFailure(passed)));
                    end
                    previous=current;
                end
                if numel(rows)>=300, break; end
            end
            if isempty(rows)
                T=struct2table(repmat(localEmpty(),0,1),"AsArray",true);
            else
                T=struct2table(rows,"AsArray",true);
            end
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_cross_domain_causality.csv"),T);
        end
    end
end

function row=localEmpty()
row=struct("RunID","","CausalityID","","SourceEventID","", ...
    "SourceLayer","","DestinationEventID","","DestinationLayer","", ...
    "TimeOrderValid",false,"IdentityValid",false,"Status","FAIL", ...
    "FailureCode","FULLSTACK:CausalityEvidenceMissing");
end

function ids=localEventIDs(T,prefix)
n=height(T);
for candidate=["EventID","PacketID","TBID","GrantID","CaseID", ...
        "TrialID","TaskID","Sequence","Slot","TTI"]
    if ismember(candidate,string(T.Properties.VariableNames))
        raw=string(T.(char(candidate)));
        ids=string(prefix)+":"+candidate+":"+raw;
        return;
    end
end
ids=string(prefix)+":ROW:"+compose("%06d",(1:n)');
end

function values=localEventTimes(T)
n=height(T);values=NaN(n,1);
for candidate=["AbsoluteTime_s","Time_s","Timestamp_s","Slot", ...
        "TTI","Sequence","PointIndex"]
    if ismember(candidate,string(T.Properties.VariableNames))
        raw=T.(char(candidate));
        if isnumeric(raw)||islogical(raw)
            values=double(raw);
        else
            values=str2double(string(raw));
        end
        return;
    end
end
end

function path=localFindUniqueOrEmpty(root,name)
listing=dir(fullfile(root,"**",char(name)));
listing=listing(~[listing.isdir]);
paths=unique(string(fullfile({listing.folder},{listing.name})));
if numel(paths)==1,path=paths(1);else,path="";end
end

function value=localStatus(tf)
if tf,value="PASS";else,value="FAIL";end
end

function value=localFailure(tf)
if tf,value="";else,value="FULLSTACK:CausalityInvariantFailed";end
end
