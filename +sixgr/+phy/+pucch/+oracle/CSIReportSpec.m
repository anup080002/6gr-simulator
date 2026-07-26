classdef CSIReportSpec
    %CSIREPORTSPEC Independent CSI field-width and bit serialization.
    methods (Static)
        function out = resolve(reportsJSON)
            reports=jsondecode(char(string(reportsJSON)));
            p1=int8([]);p2=int8([]);names1=strings(0,1);names2=strings(0,1);
            for r=reshape(reports,1,[])
                for f=reshape(r.Part1Fields,1,[])
                    b=sixgr.phy.pucch.oracle.SpecSupport.bitText(f.Bits);
                    if numel(b)~=double(f.Width)
                        error("sixgr:phy:pucch:oracle:CSIWidthMismatch", ...
                            "CSI Part-1 field width does not match its bits.");
                    end
                    p1=[p1;b];names1(end+1,1)=string(f.Name); %#ok<AGROW>
                end
                for f=reshape(r.Part2Fields,1,[])
                    b=sixgr.phy.pucch.oracle.SpecSupport.bitText(f.Bits);
                    if numel(b)~=double(f.Width)
                        error("sixgr:phy:pucch:oracle:CSIWidthMismatch", ...
                            "CSI Part-2 field width does not match its bits.");
                    end
                    p2=[p2;b];names2(end+1,1)=string(f.Name); %#ok<AGROW>
                end
            end
            out=struct("Part1Bits",p1,"Part2Bits",p2, ...
                "Part1FieldNames",names1,"Part2FieldNames",names2, ...
                "Metadata",sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "CSIReportSpec"));
        end
    end
end
