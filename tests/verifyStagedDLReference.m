function evidence=verifyStagedDLReference(completed,prepared,observation,arrival,variance)
% Component audit only: independent public primitives, original noisy samples.
% The supplied known test delay is never passed back to a production receiver.
tx=prepared.Tx; carrier=tx.Carrier; pdsch=tx.PDSCH;
assert(pdsch.NumLayers==1 && isnan(completed.TrialTable.EstimatedCFO_Hz), ...
    'This audit requires the explicit single-layer, uncorrected-CFO fixture.');
T=completed.ConstellationSamples;
assert(istable(T) && height(T)>0 && all(T.LayerIndex==1));
ofdm=nrOFDMInfo(carrier);
grid=nrOFDMDemodulate(carrier,observation(arrival+1:end,:), ...
    'Nfft',ofdm.Nfft);
K=12*carrier.NSizeGrid;
indices=double(T.SubcarrierIndex)+K*(double(T.OFDMSymbolIndex)-1);
reference=complex(T.ReferenceSymbolReal,T.ReferenceSymbolImag);
actual=complex(T.EqualizedReal,T.EqualizedImag);
dmrsIndices=nrPDSCHDMRSIndices(carrier,pdsch);
dmrsSymbols=nrPDSCHDMRS(carrier,pdsch)*tx.DMRSAmplitudeScale;
[hest,nvar]=nrChannelEstimate(carrier,grid,dmrsIndices,dmrsSymbols, ...
    'CDMLengths',pdsch.DMRS.CDMLengths,'AveragingWindow',[0 0]);
[received,h]=nrExtractResources(indices,grid,hest);
mmse=nrEqualizeMMSE(received,h,nvar);
% Rank-one LMMSE output has response |h|^2/(|h|^2+nvar).
% Convert to the production demapper's declared unit-desired-gain convention.
hPower=sum(abs(h).^2,2);
assert(all(isfinite(hPower) & hPower>0));
expected=mmse.*(hPower+nvar)./hPower;
if pdsch.EnablePTRS
    ptrsIndices=nrPDSCHPTRSIndices(carrier,pdsch);
    ptrsSymbols=nrPDSCHPTRS(carrier,pdsch);
    [ptrsReceived,ptrsH]=nrExtractResources(ptrsIndices,grid,hest);
    ptrsEqualized=nrEqualizeMMSE(ptrsReceived,ptrsH,nvar);
    symbols=floor(mod(double(ptrsIndices)-1,K*carrier.SymbolsPerSlot)/K)+1;
    for symbol=unique(symbols(:)).'
        mask=symbols==symbol;
        phase=angle(sum(ptrsEqualized(mask).*conj(ptrsSymbols(mask))));
        dataMask=double(T.OFDMSymbolIndex)==symbol;
        expected(dataMask)=expected(dataMask)*exp(-1i*phase);
    end
end
localRequireMatch(actual,expected);
% Mutation sensitivity: an altered receiver symbol must not pass this check.
changed=actual; changed(1)=changed(1)+1e-3;
caught=false;
try
    localRequireMatch(changed,expected);
catch cause
    assert(strcmp(cause.identifier,'sixgr:tests:StagedDLSymbolMismatch'));
    caught=true;
end
assert(caught);
referencePower=mean(abs(reference).^2);
expectedEVM=sqrt(mean(abs(expected-reference).^2)/referencePower);
assert(abs(completed.TrialTable.EVM_rms-expectedEVM)<1e-12);
assert(abs(completed.TrialTable.PreEqualizationNoiseVariance-nvar)<1e-20);
assert(abs(completed.TrialTable.ReplayGridNoiseVariance-ofdm.Nfft*variance)<1e-20);
evidence=struct('Scope','component_independent_public_receiver_not_run_qualification', ...
    'ExpectedEVM',expectedEVM,'MaxSymbolDifference',max(abs(actual-expected)), ...
    'PublicNoiseEstimate',nvar,'KnownGridNoiseVariance',ofdm.Nfft*variance);
fprintf('STAGED_DL_PUBLIC_REFERENCE_PASS symbols=%d max_difference=%.17g EVM=%.17g\n', ...
    numel(actual),evidence.MaxSymbolDifference,expectedEVM);
end

function localRequireMatch(actual,expected)
assert(isequal(size(actual),size(expected)) && all(isfinite(actual)) && ...
    all(isfinite(expected)) && max(abs(actual-expected))<1e-10, ...
    'sixgr:tests:StagedDLSymbolMismatch', ...
    'Actual layer symbols must match the independent public receiver stages.');
end
