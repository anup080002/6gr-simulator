classdef ToneReservationEngine
    %TONERESERVATIONENGINE Bounded iterative clipping-noise projection study.
    methods (Static)
        function result=apply(dataGrid,reservedBins,iterations,clipRatio)
            reservedBins=unique(double(reservedBins(:)));
            if isempty(reservedBins) || any(reservedBins<1|reservedBins>size(dataGrid,1))
                error("WAVEFORM:UnsupportedResearchCandidate","Reserved-tone ownership is invalid.");
            end
            grid=dataGrid; grid(reservedBins,:)=0;
            for iteration=1:double(iterations)
                x=ifft(grid,[],1)*sqrt(size(grid,1));
                limit=double(clipRatio)*sqrt(mean(abs(x).^2,"all"));
                clipped=x.*min(1,limit./max(abs(x),eps));
                correction=fft(clipped-x,[],1)/sqrt(size(grid,1));
                update=complex(zeros(size(grid),"like",grid));
                update(reservedBins,:)=correction(reservedBins,:);
                grid=grid+update;
            end
            result=struct("Grid",grid,"DataGrid",dataGrid, ...
                "ReservedBins",reservedBins,"Iterations",double(iterations), ...
                "NormativeClaimAllowed",false);
        end
    end
end
