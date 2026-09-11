function [chunk,firstIndex]=contiguousPRBChunk(available,startIndex,maxCount,minCount)
%CONTIGUOUSPRBCHUNK First ascending contiguous run satisfying grant limits.
% Never bridge a reserved frequency gap in a type-1 PRB allocation.
available=double(available(:).');
validateattributes(available,{'numeric'},{'real','finite','integer','nonnegative'});
validateattributes(startIndex,{'numeric'},{'scalar','integer','positive'});
validateattributes(maxCount,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(minCount,{'numeric'},{'scalar','integer','positive','finite'});
assert(all(diff(available)>0),'sixgr:mac:UnorderedAvailablePRBs', ...
    'Available PRBs must be unique and ascending; do not silently reorder allocations.');
chunk=zeros(1,0); firstIndex=numel(available)+1;
if minCount>maxCount, return; end
i=startIndex;
while i<=numel(available)
    last=i;
    while last<numel(available) && available(last+1)==available(last)+1
        last=last+1;
    end
    count=min(maxCount,last-i+1);
    if count>=minCount
        firstIndex=i; chunk=available(i:i+count-1); return;
    end
    i=last+1;
end
end
