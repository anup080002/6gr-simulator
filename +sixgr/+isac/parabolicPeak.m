function [peakIndex,offset] = parabolicPeak(power,integerIndex)
%PARABOLICPEAK Estimate a sub-bin peak with a common three-point estimator.
arguments
    power (:,1) double {mustBeNonnegative}
    integerIndex (1,1) double {mustBeInteger,mustBePositive}
end
if integerIndex>numel(power)
    error("sixgr:isac:PeakIndexOutsideVector","Peak index exceeds the power vector.");
end
offset=0;
if integerIndex>1 && integerIndex<numel(power)
    left=power(integerIndex-1); center=power(integerIndex); right=power(integerIndex+1);
    denominator=left-2*center+right;
    if isfinite(denominator) && abs(denominator)>eps(max(center,1))
        offset=max(-0.5,min(0.5,0.5*(left-right)/denominator));
    end
end
peakIndex=integerIndex+offset;
end
