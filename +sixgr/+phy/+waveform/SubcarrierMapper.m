classdef SubcarrierMapper
    %SUBCARRIERMAPPER Explicit zero-based RE/subcarrier/FFT-bin contract.

    methods (Static)
        function map = build(nfft,occupiedCount,varargin)
            ip = inputParser;
            ip.addParameter("BWPStartSubcarrier",0,@(x)isnumeric(x)&&isscalar(x));
            ip.addParameter("BWPID","BWP-0",@(x)ischar(x)||isstring(x));
            ip.addParameter("Owner","UNASSIGNED",@(x)ischar(x)||isstring(x));
            ip.parse(varargin{:});
            nfft = double(nfft);
            occupiedCount = double(occupiedCount);
            offset = double(ip.Results.BWPStartSubcarrier);
            if any(~isfinite([nfft occupiedCount offset])) || ...
                    nfft < 1 || nfft ~= fix(nfft) || occupiedCount < 1 || ...
                    occupiedCount ~= fix(occupiedCount) || occupiedCount > nfft || ...
                    offset ~= fix(offset)
                error("WAVEFORM:InvalidSubcarrierMap", ...
                    "Nfft, occupied count and BWP offset define an invalid map.");
            end
            coordinates = (-floor(occupiedCount/2):ceil(occupiedCount/2)-1).' + offset;
            bins = mod(coordinates,nfft);
            if numel(unique(bins)) ~= occupiedCount
                error("WAVEFORM:InvalidSubcarrierMap", ...
                    "Occupied resource elements do not own unique FFT bins.");
            end
            re = (0:occupiedCount-1).';
            map = table(re,coordinates,bins,coordinates==0, ...
                repmat(string(ip.Results.BWPID),occupiedCount,1), ...
                repmat(string(ip.Results.Owner),occupiedCount,1), ...
                'VariableNames',{'REIndex','Subcarrier','FFTBin','IsDC', ...
                'BWPID','Owner'});
        end

        function fftGrid = place(grid,nfft,varargin)
            k = size(grid,1);
            map = sixgr.phy.waveform.SubcarrierMapper.build(nfft,k,varargin{:});
            shape = size(grid);
            if numel(shape)<3, shape(3)=1; end
            fftGrid = complex(zeros(nfft,shape(2),shape(3),"like",grid));
            fftGrid(double(map.FFTBin)+1,:,:) = grid;
        end

        function grid = extract(fftGrid,occupiedCount,varargin)
            map = sixgr.phy.waveform.SubcarrierMapper.build( ...
                size(fftGrid,1),occupiedCount,varargin{:});
            grid = fftGrid(double(map.FFTBin)+1,:,:);
        end
    end
end
