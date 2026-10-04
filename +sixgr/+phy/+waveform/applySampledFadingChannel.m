function [received,finalState]=applySampledFadingChannel(transmitted,pathFilters,pathGains,initialState)
%APPLYSAMPLEDFADINGCHANNEL Finite linear channel with explicit filter memory.
% Numeric operator for SLS/LLS comparison, not a receiver channel estimate.
% No cyclic convolution, tap truncation, receive-count normalization, power
% scaling, noise, interpolation, or implicit reset of an ongoing stream.
% Gains are sample-by-path-by-TX-by-RX; one snapshot declares constant gains.
arguments
    transmitted (:,:) double {mustBeFinite}
    pathFilters (:,:) double {mustBeFinite}
    pathGains double {mustBeFinite}
    initialState double {mustBeFinite}
end
[ns,nt]=size(transmitted); [nh,np]=size(pathFilters); nr=size(pathGains,4);
assert(ns>0 && nt>0 && nh>0 && np>0 && isreal(pathFilters) && ndims(pathGains)<=4 && ...
    any(size(pathGains,1)==[1 ns]) && size(pathGains,2)==np && size(pathGains,3)==nt, ...
    'sixgr:phy:waveform:SampledChannelDimensions', ...
    'Require an explicit constant or per-sample gain realization matching every path and TX port.');
assert(ndims(initialState)<=3 && size(initialState,1)==nh-1 && ...
    size(initialState,2)==nt && size(initialState,3)==np, ...
    'sixgr:phy:waveform:SampledChannelState', ...
    'Supply exactly filter-length-minus-one by TX by path filter state; do not silently reset it.');
received=complex(zeros(ns,nr)); finalState=complex(zeros(size(initialState)));
for p=1:np
    [delayed,finalState(:,:,p)]=filter(pathFilters(:,p),1,transmitted,initialState(:,:,p),1);
    if size(pathGains,1)==1
        received=received+delayed*reshape(pathGains(1,p,:,:),nt,nr);
    else
        for r=1:nr
            received(:,r)=received(:,r)+sum(delayed.*reshape(pathGains(:,p,:,r),ns,nt),2);
        end
    end
end
end
