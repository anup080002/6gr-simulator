function ok = testConformanceFRCContract()
%TESTCONFORMANCEFRCCONTRACT Lightweight catalog and Tx setup regression.
%
% The direct testConformanceFRC() entry point remains the real, potentially
% long-running conformance gate. The ordinary regression suite intentionally
% invokes this explicit contract-only profile, which cannot report any FRC
% performance point as passed.

ok = testConformanceFRC( ...
    "Profile", "contract-only", ...
    "Verbose", false);
end
