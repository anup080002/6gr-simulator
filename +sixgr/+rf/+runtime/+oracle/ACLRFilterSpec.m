classdef ACLRFilterSpec
%ACLRFILTERSPEC Pure-math explicit-band ACLR reference.
    methods(Static)
        function result=measure(samples,sampleRateHz,assignedCenterHz, ...
                adjacentOffsetHz,bandwidthHz)
            scalars={sampleRateHz,assignedCenterHz,adjacentOffsetHz,bandwidthHz};
            valid=cellfun(@(x)isnumeric(x)&&isscalar(x)&&isreal(x)&&isfinite(x),scalars);
            if ~isnumeric(samples)||~isvector(samples)||isempty(samples)|| ...
                    any(~isfinite(samples(:)))||~all(valid)||sampleRateHz<=0|| ...
                    bandwidthHz<=0||adjacentOffsetHz<=bandwidthHz/2
                error("RFOracle:ACLRInvalid","ACLR reference inputs are invalid.");
            end
            centers=[assignedCenterHz assignedCenterHz-adjacentOffsetHz ...
                assignedCenterHz+adjacentOffsetHz];
            if any(abs(centers)+bandwidthHz/2>sampleRateHz/2)
                error("RFOracle:ACLRInvalid","Reference filters exceed sampled bandwidth.");
            end
            n=max(4096,2^nextpow2(numel(samples)));
            % Integrate per-bin PSD times bin width. Observation length,
            % not zero-padded FFT length, determines the periodogram density.
            density=abs(fftshift(fft(double(samples(:)),n))).^2/(sampleRateHz*numel(samples));
            frequency=(-n/2:n/2-1).'*sampleRateHz/n;
            values=zeros(1,3);
            for k=1:3
                mask=frequency>=centers(k)-bandwidthHz/2 & frequency<centers(k)+bandwidthHz/2;
                if ~any(mask)
                    error("RFOracle:ACLRInvalid","Reference filter contains no frequency bin.");
                end
                values(k)=sum(density(mask))*(sampleRateHz/n);
            end
            result=struct("AssignedPower",values(1), ...
                "AdjacentLowerPower",values(2), ...
                "AdjacentUpperPower",values(3), ...
                "ACLRLower_dB",10*log10(values(1)/values(2)), ...
                "ACLRUpper_dB",10*log10(values(1)/values(3)));
        end
    end
end
