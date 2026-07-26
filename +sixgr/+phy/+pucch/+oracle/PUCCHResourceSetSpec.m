classdef PUCCHResourceSetSpec
    %PUCCHRESOURCESETSPEC Independent O_UCI threshold selection.
    methods (Static)
        function out = resolve(ouci,resourceSetsJSON)
            limits=jsondecode(char(string(resourceSetsJSON)));
            ids=sort(str2double(erase(string(fieldnames(limits)),"x")));
            selected=NaN;
            for id=reshape(ids,1,[])
                field=string(id);
                if isfield(limits,char(field))
                    limit=double(limits.(char(field)));
                else
                    limit=double(limits.("x"+field));
                end
                if double(ouci)<=limit,selected=id;break;end
            end
            out=struct("SelectedSetID",selected,"Valid",isfinite(selected), ...
                "Metadata",sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "PUCCHResourceSetSpec"));
        end
    end
end
