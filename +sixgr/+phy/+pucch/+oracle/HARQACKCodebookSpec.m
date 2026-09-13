classdef HARQACKCodebookSpec
    %HARQACKCODEBOOKSPEC Independent event ordering and state mapping.
    methods (Static)
        function out = resolve(codebookType,eventsJSON)
            events=jsondecode(char(string(eventsJSON)));
            if isempty(events),events=struct([]);end
            dynamic=upper(string(codebookType))=="TYPE2_DYNAMIC";
            if ~isempty(events) && dynamic
                % Independent ordinal search, not the production wrap counter.
                if isfield(events,'MonitoringOccasionIndex')
                    key=[[events.MonitoringOccasionIndex].' [events.ServingCell].' [events.EventIndex].'];
                else
                    key=[[events.EventIndex].' [events.ServingCell].' [events.EventIndex].'];
                end
                [key,order]=sortrows(key,[1 2 3]); events=events(order);
                assert(all(ismember([events.DAI],1:4)), ...
                    'sixgr:oracle:InvalidDAI','Counter DAI must be in 1:4.');
                positions=zeros(numel(events),1); cursor=0;
                for k=1:numel(events)
                    cursor=cursor+1;
                    while mod(cursor-1,4)+1~=events(k).DAI, cursor=cursor+1; end
                    positions(k)=cursor;
                end
                if isfield(events,'TotalDAI')
                    last=events(key(:,1)==key(end,1));
                    indicated=[last.TotalDAI]; indicated=indicated(isfinite(indicated));
                    assert(all(ismember(indicated,1:4)) && numel(unique(indicated))<=1, ...
                        'sixgr:oracle:InvalidDAI','Total DAI must agree and lie in 1:4.');
                    if ~isempty(indicated)
                        while mod(cursor-1,4)+1~=indicated(1), cursor=cursor+1; end
                    end
                end
                states=upper(string({events.State}));
                bits=zeros(cursor,1,'int8'); dtx=false(cursor,1);
                bits(positions)=int8(states=="ACK"); dtx(positions)=states=="DTX";
            elseif ~isempty(events)
                key=[[events.ServingCell].' [events.Priority].' ...
                    [events.DAI].' [events.EventIndex].'];
                [~,order]=sortrows(key,[1 2 3 4]);
                events=events(order);
                states=upper(string({events.State}));
                bits=int8(states=="ACK"); dtx=states=="DTX";
            else
                bits=zeros(0,1,'int8'); dtx=false(0,1);
            end
            out=struct("CodebookType",upper(string(codebookType)), ...
                "OrderedEvents",events,"Bits",bits(:), ...
                "DTXMask",dtx(:),"Metadata", ...
                sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "HARQACKCodebookSpec"));
        end
    end
end
