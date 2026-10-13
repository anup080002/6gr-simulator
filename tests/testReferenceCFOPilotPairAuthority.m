function ok = testReferenceCFOPilotPairAuthority(estimator)
% Common-frequency evidence must cancel the same unknown channel response.
% Analytic grid tests isolate estimator algebra, not waveform/BLER coverage.
arguments
    estimator (1,1) function_handle = @sixgr.phy.rx.estimateCFOFromReferenceSymbols
end
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30,'NSlot',1);
sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
K=12*carrier.NSizeGrid; L=carrier.SymbolsPerSlot;
lengths=sampling.Nfft+double(sampling.CyclicPrefixLengthsPerSlot(:));
times=(cumsum(lengths)-.5*lengths)/sampling.SampleRateHz;
pilotSymbols=[3 8 12]; % MATLAB one-based, native DM-RS positions 2/7/11.
k=(1:2:47).';
indices=reshape(k+K*(pilotSymbols-1),[],1);
references=ones(size(indices));
% Static frequency-selective, two-branch channel; there is no channel truth
% argument or injected CFO field supplied to the production estimator.
response=exp(1i*.17*k).*[ones(size(k)),.7i*ones(size(k))];
for frequency=[0 40 2100 -2100]
    grid=complex(zeros(K,L,2));
    for n=1:numel(pilotSymbols)
        symbol=pilotSymbols(n);
        grid(k,symbol,:)=reshape(response*exp(2i*pi*frequency*times(symbol)),[],1,2);
    end
    [estimated,info]=estimator( ...
        grid,indices,references,carrier,sampling.SampleRateHz);
    assert(info.EstimateAvailable && abs(estimated-frequency)<1e-6, ...
        'sixgr:test:ReferenceCFOPairAlias', ...
        'Matched pilot CFO=%g Hz returned %g Hz. Wrapped pair frequencies must not be averaged linearly.', ...
        frequency,estimated);
    order=numel(indices):-1:1;
    [alternate,alternateInfo]=estimator(grid(:,:,end:-1:1)*1e-9, ...
        indices(order),references(order),carrier,sampling.SampleRateHz);
    assert(alternateInfo.EstimateAvailable && alternateInfo.Source==info.Source && ...
        abs(alternate-estimated)<1e-6, ...
        'sixgr:test:ReferenceCFOOrdering', ...
        'Reference ordering, RX branch ordering and a common amplitude cannot change the CFO.');
end

% Disjoint pilot frequencies cannot identify a frequency slope on an
% otherwise unspecified frequency-selective channel. Zero CFO plus different
% static channel phases must not become a successful nonzero CFO estimate.
grid=complex(zeros(K,L,2));
grid(1:24,3,:)=1;
grid(25:48,12,:)=1i;
disjoint=[(1:24).'+K*2;(25:48).'+K*11];
[estimated,info]=estimator( ...
    grid,disjoint,ones(size(disjoint)),carrier,sampling.SampleRateHz);
assert(~info.EstimateAvailable && isnan(estimated), ...
    'sixgr:test:ReferenceCFOChannelPhaseOracle', ...
    'Unmatched frequency supports cannot supply an identifiable common-frequency estimate.');

% Equal subcarrier and port numbers are insufficient when the installed
% resource/beam changes. Resource IDs come from configuration, not TX IQ.
grid=complex(zeros(K,L,2));
grid(k,3,:)=1; grid(k,12,:)=1i;
indices=[k+K*2;k+K*11]; references=ones(size(indices));
groupIDs=[zeros(size(k));ones(size(k))];
[estimated,info]=estimator(grid,indices,references,carrier,sampling.SampleRateHz, ...
    'ReferenceGroupIDs',groupIDs);
assert(~info.EstimateAvailable && isnan(estimated), ...
    'sixgr:test:ReferenceCFOBeamPhaseOracle', ...
    'The phase change of different configured beams is not a CFO observation.');

% A time-domain cover-code change mixes different unknown channel ports.
% Correlating each nominal port against the same received mixture is wrong.
% Three ports ensure the invalid per-port contributions do not simply cancel.
symbolsUsed=[3 4 10 11];
signatures=[1 1 1;1 1 -1;1i 1i 1i;-1i -1i 1i];
portChannel=[1 .2 .7i]; frequency=40;
indices=zeros(0,1); references=complex(zeros(0,1));
grid=complex(zeros(K,L,2));
for n=1:numel(symbolsUsed)
    symbol=symbolsUsed(n);
    for port=1:3
        indices=[indices;k+K*(symbol-1)+K*L*(port-1)]; %#ok<AGROW>
        references=[references;repmat(signatures(n,port),numel(k),1)]; %#ok<AGROW>
    end
    received=sum(portChannel.*signatures(n,:))*exp(2i*pi*frequency*times(symbol));
    grid(k,symbol,1)=received; grid(k,symbol,2)=.6i*received;
end
firstPair=mod(floor((indices-1)/K),L)<4;
[estimated,info]=estimator(grid,indices(firstPair),references(firstPair),carrier,sampling.SampleRateHz);
assert(~info.EstimateAvailable && isnan(estimated) && info.NumRejectedPilotMixtures>0, ...
    'sixgr:test:ReferenceCFOPortMixture', ...
    'Different port mixtures cannot supply an identifiable CFO even at matching subcarriers.');
[estimated,info]=estimator(grid,indices,references,carrier,sampling.SampleRateHz);
assert(info.EstimateAvailable && abs(estimated-frequency)<1e-6 && ...
    info.NumRejectedPilotMixtures>0 && info.NumSymbolPairsUsed==2, ...
    'sixgr:test:ReferenceCFORepeatedPortMixture', ...
    'Repeated matching cover-code mixtures must retain usable inter-group frequency evidence.');

% Precoding can leave a physical antenna port exactly inactive. Its known
% zero must remain in the complete pilot vector, not be rejected as missing
% evidence and not become an additional received observation.
zeroPortIndices=reshape(k+K*(symbolsUsed-1)+K*L*3,[],1);
withZeroIndices=[indices;zeroPortIndices];
withZeroSymbols=[references;zeros(size(zeroPortIndices))];
[withZero,zeroInfo]=estimator(grid,withZeroIndices,withZeroSymbols,carrier,sampling.SampleRateHz);
assert(zeroInfo.EstimateAvailable && abs(withZero-estimated)<1e-9 && ...
    zeroInfo.NumCommonRESamplesUsed==info.NumCommonRESamplesUsed && ...
    zeroInfo.NumSymbolPairsUsed==info.NumSymbolPairsUsed, ...
    'sixgr:test:ReferenceCFOKnownZeroPort', ...
    'A known zero physical-port coefficient cannot alter common-frequency evidence.');
% No nonzero reference energy means no frequency authority, even when the
% received grid contains energy from noise or another transmission.
[emptyFrequency,emptyInfo]=estimator(grid,withZeroIndices,zeros(size(withZeroSymbols)), ...
    carrier,sampling.SampleRateHz);
assert(~emptyInfo.EstimateAvailable && isnan(emptyFrequency), ...
    'sixgr:test:ReferenceCFOAllZeroReference','All-zero pilots cannot identify CFO.');
% Switching the active port changes the unknown effective channel; these
% vectors must not become a matched pair just because zero entries exist.
switchIndices=[k+K*2;k+K*11;k+K*2+K*L;k+K*11+K*L];
switchSymbols=[ones(size(k));zeros(size(k));zeros(size(k));ones(size(k))];
[switched,switchInfo]=estimator(grid,switchIndices,switchSymbols,carrier,sampling.SampleRateHz);
assert(~switchInfo.EstimateAvailable && isnan(switched) && ...
    switchInfo.NumRejectedPilotMixtures>0, ...
    'sixgr:test:ReferenceCFOActivePortSwitch','Unknown channel phase cannot be interpreted as CFO.');

% Do not silently truncate, round, or drop malformed installed references.
localReject(@() estimator(grid,indices,references(2:end),carrier,sampling.SampleRateHz), ...
    'sixgr:phy:rx:ReferenceCFOShapeMismatch');
localReject(@() estimator(grid,indices+.1,references,carrier,sampling.SampleRateHz), ...
    'sixgr:phy:rx:ReferenceCFOInvalidIndex');
bad=references; bad(1)=NaN;
localReject(@() estimator(grid,indices,bad,carrier,sampling.SampleRateHz), ...
    'sixgr:phy:rx:ReferenceCFOInvalidSymbol');
localReject(@() estimator(grid,[indices;indices(1)],[references;references(1)],carrier,sampling.SampleRateHz), ...
    'sixgr:phy:rx:ReferenceCFODuplicateIndex');
localReject(@() estimator(grid,indices,references,carrier,sampling.SampleRateHz, ...
    'ReferenceGroupIDs',1), 'sixgr:phy:rx:ReferenceCFOInvalidGroups');
fprintf('REFERENCE_CFO_PILOT_PAIR_AUTHORITY_PASS estimator=%s matched=4 disjoint=1 different_resources=1 port_mixtures=2 zero_port_cases=3 malformed=5\n',func2str(estimator));
ok=true;
end

function localReject(action,identifier)
try
    action();
catch failure
    assert(strcmp(failure.identifier,identifier), ...
        'Expected %s but received %s.',identifier,failure.identifier);
    return;
end
error('sixgr:test:ReferenceCFOMalformedAccepted','Expected rejection %s.',identifier);
end
