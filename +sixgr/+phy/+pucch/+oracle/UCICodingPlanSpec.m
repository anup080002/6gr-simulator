classdef UCICodingPlanSpec
    %UCICODINGPLANSPEC Independent TS 38.212 UCI coding boundaries.
    methods (Static)
        function out = resolve(A,E)
            A=double(A);E=double(E);
            if ~(isscalar(A)&&isscalar(E)&&A>=0&&E>=0&& ...
                    A==fix(A)&&E==fix(E))
                error("sixgr:phy:pucch:oracle:InvalidCodingPlan", ...
                    "A and E must be nonnegative integers.");
            end
            if A==0, family="NO_UCI"; crc=0;
            elseif A<=2, family="SMALL_BLOCK_1_2"; crc=0;
            elseif A<=11, family="SMALL_BLOCK_3_11"; crc=0;
            elseif A<=19, family="POLAR"; crc=6;
            else, family="POLAR"; crc=11;
            end
            out=struct("A",A,"E",E,"CodingFamily",family, ...
                "CRCBits",crc,"Metadata", ...
                sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "UCICodingPlanSpec"));
        end
    end
end
