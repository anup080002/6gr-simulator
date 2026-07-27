classdef LocalizedDFTMapper
    %LOCALIZEDDFTMAPPER Map DFT output to explicit contiguous/noncontiguous bins.
    methods (Static)
        function [grid,indices]=map(symbols,nfft,startIndex,varargin)
            ip=inputParser;
            ip.addParameter("Indices",[],@isnumeric);
            ip.addParameter("Strict",true,@(x)islogical(x)||isscalar(x));
            ip.parse(varargin{:});
            m=size(symbols,1);
            if isempty(ip.Results.Indices)
                indices=double(startIndex)+(0:m-1);
            else
                indices=double(ip.Results.Indices(:).');
            end
            if numel(indices)~=m || any(indices<0|indices>=nfft|indices~=fix(indices)) || ...
                    numel(unique(indices))~=m
                error("WAVEFORM:InvalidSubcarrierMap","Localized DFT map is invalid.");
            end
            if logical(ip.Results.Strict) && any(diff(indices)~=1)
                error("WAVEFORM:NoncontiguousTransformAllocation", ...
                    "Strict DFT-s-OFDM mapping must be contiguous.");
            end
            grid=complex(zeros(nfft,size(symbols,2),size(symbols,3),"like",symbols));
            grid(indices+1,:,:)=symbols;
            indices=indices(:);
        end
        function symbols=extract(grid,indices)
            symbols=grid(double(indices(:))+1,:,:);
        end
    end
end
