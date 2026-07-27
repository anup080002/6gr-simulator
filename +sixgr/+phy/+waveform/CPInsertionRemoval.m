classdef CPInsertionRemoval
    %CPINSERTIONREMOVAL Exact cyclic-prefix math with typed validation.

    methods (Static)
        function output = insert(useful,cpLength)
            cpLength = sixgr.phy.waveform.CPInsertionRemoval.validate( ...
                useful,cpLength);
            if cpLength == 0
                output = useful;
            else
                output = [useful(end-cpLength+1:end,:); useful];
            end
        end

        function useful = remove(input,cpLength,usefulLength)
            if nargin < 3
                usefulLength = size(input,1)-double(cpLength);
            end
            cpLength = double(cpLength);
            usefulLength = double(usefulLength);
            if any(~isfinite([cpLength usefulLength])) || ...
                    any([cpLength usefulLength] < 0) || ...
                    any([cpLength usefulLength] ~= fix([cpLength usefulLength])) || ...
                    cpLength+usefulLength > size(input,1)
                error("WAVEFORM:InvalidOFDMParameters", ...
                    "CP removal lengths exceed the available samples.");
            end
            useful = input(cpLength+(1:usefulLength),:);
        end
    end

    methods (Static, Access=private)
        function cp = validate(useful,cp)
            cp = double(cp);
            if ~isscalar(cp) || ~isfinite(cp) || cp < 0 || ...
                    cp ~= fix(cp) || cp > size(useful,1)
                error("WAVEFORM:InvalidOFDMParameters", ...
                    "CP length must be an integer in [0,useful length].");
            end
        end
    end
end
