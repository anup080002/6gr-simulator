classdef QualificationArtifactCompleteness
    %QUALIFICATIONARTIFACTCOMPLETENESS Deterministic canonical reduction.
    methods (Static)
        function T=reduce(audit)
            domains=unique(string(audit.Domain),"stable");
            rows=repmat(localRow(),numel(domains),1);
            for index=1:numel(domains)
                domain=domains(index);
                selected=audit(audit.Domain==domain & audit.Required,:);
                csv=selected.ArtifactType=="CSV";
                png=selected.ArtifactType=="PNG";
                valid=selected.Status=="PASS";
                required=height(selected);
                passed=nnz(valid);
                row=localRow();
                row.Domain=domain;
                row.RequiredCSV=nnz(csv);
                row.PresentCSV=nnz(csv & selected.Present);
                row.ValidCSV=nnz(csv & valid);
                row.RequiredPNG=nnz(png);
                row.PresentPNG=nnz(png & selected.Present);
                row.ValidPNG=nnz(png & valid);
                row.CompletenessPct=100*passed/max(required,1);
                row.Status=localPass(passed==required);
                rows(index)=row;
            end
            T=struct2table(rows,"AsArray",true);
        end
    end
end

function value=localPass(tf)
if tf,value="PASS";else,value="FAIL";end
end

function row=localRow()
row=struct("Domain","","RequiredCSV",0,"PresentCSV",0, ...
    "ValidCSV",0,"RequiredPNG",0,"PresentPNG",0,"ValidPNG",0, ...
    "CompletenessPct",0,"Status","FAIL");
end
