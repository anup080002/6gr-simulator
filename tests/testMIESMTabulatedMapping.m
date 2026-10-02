function ok=testMIESMTabulatedMapping()
% Algebraic interpolation fixtures only; these are NOT calibrated MI curves.
lookup=struct('SINRGrid_dB',[-10 0 10], ...
    'MutualInformation_bitsPerSymbol',[.1 .6 1.7],'ModulationOrder',4,'BetaLinear',1);
f=@(v,l)sixgr.phy.rsla.MIESMMapper.map(v,l,"test_only_not_phy_calibration");
r=f([-10 10],lookup);
assert(abs(r.MeanMutualInformation-.9)<1e-12);
assert(abs(r.EffectiveSINRDb-30/11)<1e-12);
assert(r.MutualInformationUnits=="bits_per_modulation_symbol");
% Identity for uniform input and explicit linear-beta scaling in dB.
flat=f([2 2 2],lookup); assert(abs(flat.EffectiveSINRDb-2)<1e-12);
shifted=lookup; shifted.BetaLinear=2;
mapped=f([-10 10]+10*log10(2),shifted);
assert(abs(mapped.EffectiveSINRDb-r.EffectiveSINRDb-10*log10(2))<1e-12);
assert(mapped.LookupSHA256~=r.LookupSHA256);
localReject(@()f([0 11],lookup),'RSLA:MIOutsideCalibration');
localReject(@()f(0,1.2),'RSLA:MissingEffectiveSINRCalibration');
bad=lookup; bad.MutualInformation_bitsPerSymbol=[.1 .6 .6];
localReject(@()f(0,bad),'RSLA:InvalidMILookup');
bad=lookup; bad.MutualInformation_bitsPerSymbol=[.1 .6 2.1];
localReject(@()f(0,bad),'RSLA:InvalidMILookup');
ok=true; fprintf('MIESM_TABULATED_MAPPING_PASS numerical_fixture_only=1\n');
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s.',id,ME.identifier); return; end
error('test:ExpectedError','Expected %s.',id);
end
