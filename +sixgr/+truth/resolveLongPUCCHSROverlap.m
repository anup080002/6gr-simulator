function result=resolveLongPUCCHSROverlap(calendar,slot,startSymbol,numSymbols,priority,format)
% TS 38.213 9.2.5.1: Format 2/3/4 SR count for same-priority multiplexing.
% No pending-positive SR state or transmitted/decoded values are accepted.
% This does not decide PUSCH transport, cross-priority dropping or MAC state.
assert(isnumeric(format) && isreal(format) && isscalar(format) && ismember(format,[2 3 4]), ...
    'sixgr:truth:UnsupportedSRMultiplexFormat','Format 0/1 use different SR procedures.');
validateattributes(startSymbol,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(numSymbols,{'numeric'},{'scalar','real','finite','integer','positive'});
result=sixgr.truth.resolveConfiguredSROverlap(calendar,slot,[startSymbol numSymbols],priority);
end
