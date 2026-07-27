classdef WaveformContinuityChecker
    %WAVEFORMCONTINUITYCHECKER One-shot/chunk equivalence and sample ownership.
    methods (Static)
        function result=compare(reference,actual)
            if size(reference,1)~=size(actual,1)
                error("WAVEFORM:StreamDiscontinuity","Chunked sample count changed.");
            end
            errorSignal=double(reference(:))-double(actual(:));
            nmse=sum(abs(errorSignal).^2)/max(sum(abs(double(reference(:))).^2),eps);
            result=struct("SampleCountExpected",size(reference,1), ...
                "SampleCountActual",size(actual,1),"NMSE",nmse, ...
                "BoundaryJump",max(abs(errorSignal),[],"omitnan"), ...
                "Status",string(nmse<=1e-12));
            if nmse>1e-12
                error("WAVEFORM:StreamDiscontinuity", ...
                    "Chunked waveform NMSE %.3g exceeds 1e-12.",nmse);
            end
        end
    end
end
