classdef PUCCHFormatSpec
    %PUCCHFORMATSPEC Independent format/payload allocation bounds.
    methods (Static)
        function out = validate(format,numSymbols,uciBits,numPRBs)
            f=double(format);s=double(numSymbols);a=double(uciBits);m=double(numPRBs);
            valid=ismember(f,0:4)&&s>=1&&s<=14&&a>=0&&m>=1;
            if valid
                switch f
                    case 0, valid=s<=2&&a<=2&&m==1;
                    case 1, valid=s>=4&&a<=2&&m==1;
                    case 2, valid=s<=2&&a>2;
                    case 3, valid=s>=4&&a>2;
                    case 4, valid=s>=4&&a>2&&m==1;
                end
            end
            out=struct("Valid",logical(valid),"ParameterMutated",false, ...
                "Metadata",sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "PUCCHFormatSpec"));
        end
    end
end
