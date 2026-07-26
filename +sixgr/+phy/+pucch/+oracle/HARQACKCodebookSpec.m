classdef HARQACKCodebookSpec
    %HARQACKCODEBOOKSPEC Independent event ordering and state mapping.
    methods (Static)
        function out = resolve(codebookType,eventsJSON)
            events=jsondecode(char(string(eventsJSON)));
            if isempty(events),events=struct([]);end
            if ~isempty(events)
                key=[[events.ServingCell].' [events.Priority].' ...
                    [events.DAI].' [events.EventIndex].'];
                [~,order]=sortrows(key,[1 2 3 4]);
                events=events(order);
            end
            states=upper(string({events.State}));
            bits=int8(states=="ACK");
            dtx=states=="DTX";
            out=struct("CodebookType",upper(string(codebookType)), ...
                "OrderedEvents",events,"Bits",bits(:), ...
                "DTXMask",dtx(:),"Metadata", ...
                sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "HARQACKCodebookSpec"));
        end
    end
end
