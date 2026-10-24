function ok=testCSIRSCDMModelReference()
% Actual measurement producer on DECLARED grids, not a waveform qualification.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng;
c=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',3, ...
    'Density','one','SymbolLocations',2,'SubcarrierLocations',0,'NumRB',24);
reference=nrResourceGrid(c,rs.NumCSIRSPorts);
reference(nrCSIRSIndices(c,rs))=nrCSIRS(c,rs);
K=size(reference,1); L=size(reference,2); nfft=512;
idx=find(reference(:,:,1)~=0); [k,l]=ind2sub([K L],idx); support=[k-1 l-1];
cfg.phy.csiim=struct('enabled',true,'resource_id',0,'pattern',1, ...
    'subcarrier',4,'symbol',13,'starting_rb',0,'num_rbs',24,'period_slots',5,'offset_slots',0);
[kk,ll]=ndgrid(0:K-1,0:L-1);
base=double(reference(:,:,1)); other=double(reference(:,:,2));
T=cat(3,base,.6i*base); O=cat(3,.8*other,-.4i*other);
R=.002*cat(3,complex(sin(.17*kk),cos(.21*ll)),complex(cos(.19*kk),sin(.13*ll)));
X=.01*cat(3,complex(cos(.31*kk+.11*ll),sin(.29*kk-.17*ll)), ...
    complex(sin(.23*kk+.27*ll),cos(.37*kk-.09*ll)));
parts={T,O,R,X};
for unit=["normalized_complex_baseband","sqrt_mW"]
    [a,m,raw,Y]=evaluate(parts,unit);
    assert(a.Available&&a.OperatorMatchedModelComparisonAvailable&& ...
        a.OriginalCSIIMSecondMomentReproduced&&~a.DenominatorIndependentlyReferenced&& ...
        ~a.IndependentAccuracyQualified&&~a.StandardizedAccuracyQualified&& ...
        ~a.UniqueNonlinearPortAttributionQualified&&~a.ReferenceUsedByReceiver);
    near(a.OriginalProjectedNoisyPowerPerReceiveColumn,m.SignalPowerEstimation.RawPort3000PowerPerBranch);
    near(a.OriginalMeasuredSignedPowerPerReceiveColumn,m.DesiredPowerPerReceiveAntenna);
    assert(isequal(a.OriginalObservedCSIIMTotalPowerPerReceiveColumn,m.NoiseInterferencePowerPerReceiveAntenna));
    near(a.MeasuredMinusTargetPowerPerReceiveColumn,a.NonTargetPlusCrossMinusBiasPerReceiveColumn);
    assert(a.OriginalSINRSelectedColumn1==m.ReceiveBranch1Based);
    saved=m;
    again=call(raw,Y,m,unit);
    assert(isequaln(a,again)&&isequaln(saved,m),'Post-receiver arithmetic cannot mutate the measurement.');
end
fprintf('CSI_CDM_MODEL_REFERENCE group=actual_producer_normalized_absolute PASS\n');

% Intra-tile variation produces real projection loss and other-port leakage.
% Q(T) is NOT automatically raw target-RE power, even with matched operators.
vary=parts; phase=exp(1i*.8*kk);
vary{1}=T.*phase; vary{2}=O.*exp(-1i*.6*kk);
[a,~,~,~]=evaluate(vary,"normalized_complex_baseband");
assert(any(abs(a.TargetProjectionMinusRawREPowerPerReceiveColumn)>1e-3)&& ...
    any(a.ProjectedPowerPerTermPerReceiveColumn(2,:)>1e-3)&& ...
    ~a.TargetProjectionIsPhysicalREPower);
assert(any(abs(a.ProjectedSignedCrossPowerPerReceiveColumn)>1e-5,'all'));
fprintf('CSI_CDM_MODEL_REFERENCE group=within_tile_variation_leakage_and_cross_terms PASS\n');

% Target leakage on CSI-IM is retained in the shared observed denominator.
leaking=parts; leaking{1}(:,14,:)=.3+.1i;
[a,m,~,~]=evaluate(leaking,"normalized_complex_baseband");
assert(all(a.CSIIMTerms.TargetLeakagePowerPerReceiveColumn>0)&& ...
    ~a.CSIIMTerms.TargetLeakageSubtracted&&~a.DenominatorIndependentlyReferenced);
near(a.OriginalObservedCSIIMTotalPowerPerReceiveColumn,m.InterferenceMeasurement.PowerPerReceiveAntenna);
fprintf('CSI_CDM_MODEL_REFERENCE group=CSIIM_target_leakage_not_subtracted PASS\n');

% Zero observed IM with positive signal gives Inf/Inf, NEVER zero error.
zero=complex(zeros(size(T)));
[a,zeroIM,zeroRaw,zeroY]=evaluate({T,O,zero,zero},"normalized_complex_baseband");
assert(all(isinf(a.MeasuredSINR_dB))&&all(isinf(a.ModelSINR_dB))&& ...
    isnan(a.ReportedSINRLogRatioDifference_dB)&& ...
    all(isnan(a.SINRLogRatioDifferencePerReceiveColumn_dB))&& ...
    all(a.NumericTokens.ModelSINR_dB=="Inf"));
assert(all(abs(a.ProjectedPowerClosureResidual)<=a.ProjectedPowerClosureRoundoffBound)&& ...
    all(abs(a.MeasuredMinusTargetPowerPerReceiveColumn-a.NonTargetPlusCrossMinusBiasPerReceiveColumn)<= ...
        a.PowerDifferenceClosureRoundoffBound));
% A conditioned roundoff bound is not permission to change a component.
% The same original zero-IM capture must reject a meaningful target change,
% while accepting its naturally cancellation-dominated decomposition above.
tampered=zeroRaw; tampered{1}(idx(1))=tampered{1}(idx(1))+1e-6;
reject(@()call(tampered,zeroY,zeroIM,"normalized_complex_baseband"));
[a,~,~,~]=evaluate({zero,zero,zero,zero},"normalized_complex_baseband");
assert(all(isnan(a.ModelSINR_dB))&&isnan(a.ReportedSINRLogRatioDifference_dB));
% Noise only on muted support: signed debiased signal remains negative.
noiseOnIM=zero; noiseOnIM(:,14,:)=1;
[a,m,~,~]=evaluate({zero,zero,zero,noiseOnIM},"normalized_complex_baseband");
assert(all(m.DesiredPowerPerReceiveAntenna<0)&& ...
    all(a.OriginalMeasuredSignedPowerPerReceiveColumn<0)&&all(isnan(a.MeasuredSINR_dB))&& ...
    all(a.ModelSINR_dB==-Inf)&&all(a.NumericTokens.ModelSINR_dB=="-Inf"));
fprintf('CSI_CDM_MODEL_REFERENCE group=zero_Inf_and_negative_signed_measurements PASS\n');

[~,m,raw,Y]=evaluate(parts,"normalized_complex_baseband");
bad=m; bad.SignalPowerEstimation.CDMProjectionReceipt.ProjectionWeightsReal(1)= ...
    bad.SignalPowerEstimation.CDMProjectionReceipt.ProjectionWeightsReal(1)+.1;
reject(@()call(raw,Y,bad,"normalized_complex_baseband"));
bad=reseal(bad); reject(@()call(raw,Y,bad,"normalized_complex_baseband"));
bad=m;
bad.SignalPowerEstimation.CDMProjectionReceipt.TileIndices1Based=char( ...
    m.SignalPowerEstimation.CDMProjectionReceipt.TileIndices1Based);
bad=reseal(bad); reject(@()call(raw,Y,bad,"normalized_complex_baseband"));
bad=m; bad.SignalPowerEstimation.CDMProjectionReceipt.ProjectedCoefficientsReal(1)= ...
    bad.SignalPowerEstimation.CDMProjectionReceipt.ProjectedCoefficientsReal(1)+.2;
bad=reseal(bad); reject(@()call(raw,Y,bad,"normalized_complex_baseband"));
changed=raw; changed{1}(idx(1))=changed{1}(idx(1))+.2;
reject(@()call(changed,Y,m,"normalized_complex_baseband"));
reject(@()call(raw,Y,m,"sqrt_mW"));
fprintf('CSI_CDM_MODEL_REFERENCE group=original_receipt_and_component_corruption PASS\n');

native=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,Y,struct());
a=call(raw,Y,native,"normalized_complex_baseband");
assert(~a.Available&&~a.OperatorMatchedModelComparisonAvailable&& ...
    a.Status=="unavailable_original_CDM_projection_not_recorded");
assert(isequal(savedRNG,rng));
fprintf('CSI_CDM_MODEL_REFERENCE group=native_unmatched_and_RNG_preserved PASS\n');
ok=true;

    function [a,m,raw,Y]=evaluate(terms,unit)
        raw=terms;
        if unit=="sqrt_mW"
            for z=1:4, raw{z}=raw{z}*(nfft*sqrt(1000)); end
        end
        Y=raw{1}+raw{2}+raw{3}+raw{4}; measuredGrid=Y;
        if unit=="sqrt_mW", measuredGrid=Y./cast(nfft*sqrt(1000),'like',Y); end
        m=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,measuredGrid,cfg);
        a=call(raw,Y,m,unit);
    end
    function a=call(terms,Y,m,unit)
        a=sixgr.phy.refsig.compareCSIRSCDMModelReference(terms{1},terms{2},terms{3},terms{4}, ...
            Y,reference,support,nfft,m,unit);
    end
end
function m=reseal(m)
m.SignalPowerEstimation.CDMProjectionReceiptSHA256=sixgr.util.sha256Hex( ...
    char(jsonencode(m.SignalPowerEstimation.CDMProjectionReceipt)));
end
function near(a,b)
assert(isequal(size(a),size(b))&&all(abs(a-b)<=1e-10*max(1,abs(b)),'all'));
end
function reject(f)
try, f(); catch e
    assert(startsWith(string(e.identifier),"sixgr:refsig:CSIRSCDMModelReference")|| ...
        startsWith(string(e.identifier),"sixgr:refsig:CSIRSSINRReference")); return;
end
error('test:MissingRejection','Malformed original CDM evidence was accepted.');
end
