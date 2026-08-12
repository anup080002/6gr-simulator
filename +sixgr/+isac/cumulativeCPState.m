function q = cumulativeCPState(cpLengths,nFFT,resetSymbols0)
%CUMULATIVECPSTATE Derive W3 state from absolute physical OFDM symbols.
%
% q(l) includes the CP of absolute symbol l, as required by the 10.8.3 W3
% definition. A punctured sensing occasion is deliberately absent from the
% interface: physical-symbol time advances whether or not an RS is sent.

arguments
    cpLengths (:,1) double {mustBeFinite,mustBeNonnegative}
    nFFT (1,1) double {mustBeInteger,mustBePositive}
    resetSymbols0 (:,1) double {mustBeInteger,mustBeNonnegative} = 0
end
if isempty(cpLengths)
    error("sixgr:isac:EmptyCPPattern","The physical CP-length pattern is empty.");
end
nSymbols = numel(cpLengths);
if any(resetSymbols0 >= nSymbols) || ~ismember(0,resetSymbols0)
    error("sixgr:isac:InvalidW3ResetSymbols", ...
        "W3 reset symbols must be zero-based physical symbols in the interval and include zero.");
end
reset = false(nSymbols,1);
reset(unique(resetSymbols0)+1) = true;
q = zeros(nSymbols,1);
for symbol = 1:nSymbols
    if reset(symbol)
        q(symbol) = mod(cpLengths(symbol),nFFT);
    else
        q(symbol) = mod(q(symbol-1)+cpLengths(symbol),nFFT);
    end
end
end
