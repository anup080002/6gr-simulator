function ok=testCSIRSCDMProjectionReceipt()
% Actual practical CDM producer on declared native CSI-RS grids. No shared
% waveform/channel/RF authority or independent accuracy population is claimed.
setup6GRSimToolkit('Verbose',false);
beforeRNG=rng;
c=nrCarrierConfig('NSizeGrid',24,'NStartGrid',7,'SubcarrierSpacing',30);
cases=0;
for row=[2 3 8 18]
    [rs,reference,grid,terms]=fixture(c,row);
    cdm=sixgr.phy.refsig.csirsCDMLengths(rs.CDMType);
    for numericClass=["double","single"]
        input=cast(grid,numericClass); savedInput=input; savedReference=reference;
        noise=cast([.13 .27],numericClass);
        expected=originalRecurrence(c,reference,input,cdm,noise);
        measured=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,reference,input,cdm,noise);
        old=rmfield(measured,{'CDMProjectionReceipt','CDMProjectionReceiptSHA256'});
        assert(isequaln(old,expected)&&isequal(input,savedInput)&&isequal(reference,savedReference), ...
            'Receipt collection must preserve every original practical result bit-for-bit.');
        r=measured.CDMProjectionReceipt;
        assert(measured.CDMProjectionReceiptSHA256==sixgr.util.sha256Hex(char(jsonencode(r))));
        verifyReceipt(c,reference,input,noise,measured);
        decoded=jsondecode(jsonencode(r));
        [coefficients,raw]=project(decoded,input);
        assert(isequal(coefficients,complex(r.ProjectedCoefficientsReal,r.ProjectedCoefficientsImag))&& ...
            isequal(raw,measured.RawPort3000PowerPerBranch), ...
            'Explicit real/imaginary serialization must retain the executed operator.');
        if numericClass=="double", componentClosure(r,input,terms); end
        cases=cases+1;
    end
end
assert(cases==8);
fprintf('CSI_CDM_PROJECTION_RECEIPT group=native_rows_and_exact_original_recurrence cases=%d PASS\n',cases);

% Original single reference conversion is distinct from an assumed double
% pilot: both typed and actually used double-support hashes are retained.
[rs,reference,grid]=fixture(c,8); reference=single(reference); grid=single(grid);
cdm=sixgr.phy.refsig.csirsCDMLengths(rs.CDMType);
measured=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,reference,grid,cdm,[.1 .2]);
verifyReceipt(c,reference,grid,[.1 .2],measured);
assert(~measured.CDMProjectionReceipt.ArithmeticReferenceHashReusesTypedSupportHash);
fprintf('CSI_CDM_PROJECTION_RECEIPT group=typed_reference_conversion PASS\n');

% Receipt binds only samples actually read by the CDM operator, not unused
% resource-grid samples. Full original grid identity belongs to its caller.
r=measured.CDMProjectionReceipt;
used=r.TileIndices1Based(:); K=size(grid,1); L=size(grid,2);
outside=find(~ismember((1:K*L).',used),1);
changed=grid; changed(outside)=changed(outside)+single(.25i);
again=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,reference,changed,cdm,[.1 .2]);
assert(isequaln(again,measured),'Unused input samples are not read or rehashed by the primitive.');
changed=grid; changed(used(1))=changed(used(1))+single(.25i);
again=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,reference,changed,cdm,[.1 .2]);
assert(again.CDMProjectionReceipt.InputUsedSupportSHA256~=r.InputUsedSupportSHA256&& ...
    again.CDMProjectionReceiptSHA256~=measured.CDMProjectionReceiptSHA256);
fprintf('CSI_CDM_PROJECTION_RECEIPT group=exact_used_support_identity PASS\n');

% Real production propagation through the dedicated CSI-IM branch. The
% native no-CSIIM branch must not acquire this operator or be qualified.
[rs,reference,grid]=fixture(c,8);
cfg.phy.csiim=struct('enabled',true,'resource_id',0,'pattern',1, ...
    'subcarrier',4,'symbol',13,'starting_rb',0,'num_rbs',24,'period_slots',5,'offset_slots',0);
for numericClass=["double","single"]
    input=cast(grid,numericClass);
    im=sixgr.phy.refsig.measureCSIIM(c,cfg,input);
    direct=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,reference,input,cdm,im.PowerPerReceiveAntenna);
    actual=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,input,cfg);
    assert(isequal(actual.SignalPowerEstimation.CDMProjectionReceipt,direct.CDMProjectionReceipt)&& ...
        actual.SignalPowerEstimation.CDMProjectionReceiptSHA256==direct.CDMProjectionReceiptSHA256&& ...
        isequal(actual.DesiredPowerPerReceiveAntenna,direct.SignedPort3000PowerPerBranch)&& ...
        isequal(actual.NoiseInterferencePowerPerReceiveAntenna,im.PowerPerReceiveAntenna));
    logs=nan(1,2); linear=direct.SignedPort3000PowerPerBranch./im.PowerPerReceiveAntenna;
    positive=linear>0; logs(positive)=10*log10(linear(positive));
    [value,column]=max(logs,[],'omitnan'); if isnan(value), column=NaN; end
    assert(isequaln(actual.CSI_SINRPerReceiveAntenna_dB,logs)&& ...
        isequaln(actual.CSI_SINR_dB,value)&&isequaln(actual.ReceiveBranch1Based,column));
end
noIM=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,grid,struct());
assert(~isfield(noIM.SignalPowerEstimation,'CDMProjectionReceipt')&& ...
    noIM.DisturbanceSource=="nrChannelEstimate_received_reference_residual");
fprintf('CSI_CDM_PROJECTION_RECEIPT group=actual_CSIIM_propagation_and_noIM_boundary PASS\n');

% Signed/no-signal estimates and existing invalid-reference guards remain.
zero=complex(zeros(size(grid)));
negative=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,reference,zero,cdm,[1 2]);
assert(all(negative.SignedPort3000PowerPerBranch<0)&&~negative.ClippedToNonnegative&& ...
    all(negative.CDMProjectionReceipt.ProjectedCoefficientsReal==0,'all')&& ...
    all(negative.CDMProjectionReceipt.ProjectedCoefficientsImag==0,'all'));
verifyReceipt(c,reference,zero,[1 2],negative);
bothZero=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,reference,zero,cdm,[0 0]);
assert(all(bothZero.SignedPort3000PowerPerBranch==0));
bad=reference; first=find(bad(:,:,1)~=0,1); bad(first)=0;
reject(@()sixgr.phy.refsig.measureCSIRSCDMPortPower(c,bad,grid,cdm,[0 0]), ...
    'sixgr:refsig:CSICDMPowerTile');
bad=reference; bad(:,:,2)=bad(:,:,1);
reject(@()sixgr.phy.refsig.measureCSIRSCDMPortPower(c,bad,grid,cdm,[0 0]), ...
    'sixgr:refsig:CSICDMPowerOrthogonality');
assert(isequal(rng,beforeRNG),'Receipt construction must not draw or reseed randomness.');
fprintf('CSI_CDM_PROJECTION_RECEIPT group=signed_zero_existing_guards_and_RNG PASS\n');
ok=true;
end

function [rs,reference,grid,terms]=fixture(c,row)
offsets=0; if row==8, offsets=[0 2]; elseif row==18, offsets=[0 2 4 6]; end
rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',row,'Density','one', ...
    'SymbolLocations',2,'SubcarrierLocations',offsets,'RBOffset',3,'NumRB',9);
reference=nrResourceGrid(c,rs.NumCSIRSPorts);
reference(nrCSIRSIndices(c,rs))=nrCSIRS(c,rs);
K=size(reference,1); L=size(reference,2); [k,l]=ndgrid(0:K-1,0:L-1);
phase=exp(1i*(.013*k+.027*l));
target=reference(:,:,1).*phase;
other=complex(zeros(K,L));
for port=2:rs.NumCSIRSPorts
    other=other+(1+.2i*port)*reference(:,:,port).*exp(1i*(.017*k+.021*l));
end
residual=.003*complex(sin(.17*k+.2*l),cos(.11*k-.3*l));
external=.005*complex(cos(.21*k+.1*l),sin(.19*k-.07*l));
terms={cat(3,target,.3i*target),cat(3,other,-.4*other), ...
    cat(3,residual,.7i*residual),cat(3,external,1.3*external)};
grid=terms{1}+terms{2}+terms{3}+terms{4};
end
function verifyReceipt(c,reference,input,noise,e)
r=e.CDMProjectionReceipt; hash=@sixgr.phy.waveform.WaveformHash.runtimeArray;
assert(r.ContractVersion=="sixgr.csirs.original_cdm_projection/v1"&& ...
    r.Source=="original_practical_CDM_port3000_projection"&& ...
    ~r.WaveformAmplitudeUnitBound&&~r.ResourceIdentityBound&&~r.OriginalSharedOwnerBound&& ...
    ~r.IndependentReferenceAvailable&&~r.StandardizedAccuracyQualified&&~r.ReferenceUsedByReceiver);
assert(r.CarrierIdentity.NStartGrid==c.NStartGrid&&r.CarrierIdentity.NFrame==c.NFrame&& ...
    r.CarrierIdentity.NSlot==c.NSlot&&r.ReceiveColumnCount==size(input,3)&& ...
    r.ReferencePortCount==size(reference,3)&&r.ReferencePortNumber==3000&& ...
    isequal(r.InputGridSize,size(input))&&isequal(r.ReferenceGridSize,size(reference)));
indices=r.TileIndices1Based; used=indices(:);
assert(numel(unique(used))==r.NormalizationPilotCount&& ...
    isequal(sort(used),find(reference(:,:,1)~=0))&&r.TileCount*r.TileSize==r.NormalizationPilotCount);
inputFlat=reshape(input,[],size(input,3)); refFlat=reshape(reference,[],size(reference,3));
assert(r.InputUsedSupportSHA256==hash(inputFlat(used,:))&& ...
    r.ReferenceUsedSupportSHA256==hash(refFlat(used,:))&& ...
    r.ArithmeticInputUsedSupportSHA256==hash(double(inputFlat(used,:)))&& ...
    r.ArithmeticReferenceUsedSupportSHA256==hash(double(refFlat(used,:))));
weights=complex(r.ProjectionWeightsReal,r.ProjectionWeightsImag);
for b=1:r.TileCount
    pilot=double(refFlat(indices(:,b),1)); energy=sum(abs(pilot).^2);
    assert(isequal(weights(:,b),conj(pilot)/energy)&&r.ReferenceEnergyPerTile(b)==energy&& ...
        r.UnitNoiseGainPerTile(b)==sum(abs(weights(:,b)).^2));
end
[coefficients,raw,weighted,biasWeighted]=project(r,input);
assert(isequal(coefficients,complex(r.ProjectedCoefficientsReal,r.ProjectedCoefficientsImag))&& ...
    isequal(raw,e.RawPort3000PowerPerBranch)&& ...
    isequal(weighted,r.WeightedSquaredCoefficientSumPerBranch)&& ...
    isequal(biasWeighted,r.UnitNoiseBiasWeightedSum)&& ...
    isequal(r.DisturbancePowerPerBranch,double(noise(:).'))&& ...
    isequal(r.EstimatedNoiseBiasPerBranch,e.EstimatedNoiseBiasPerBranch)&& ...
    isequal(r.SignedPort3000PowerPerBranch,e.SignedPort3000PowerPerBranch));
end
function [coefficients,raw,weighted,biasWeighted]=project(r,grid)
indices=reshape(double(r.TileIndices1Based),r.TileSize,r.TileCount);
weights=reshape(complex(r.ProjectionWeightsReal,r.ProjectionWeightsImag),r.TileSize,r.TileCount);
flat=reshape(double(grid),[],r.ReceiveColumnCount);
coefficients=complex(zeros(r.TileCount,r.ReceiveColumnCount));
weighted=zeros(1,r.ReceiveColumnCount); biasWeighted=0;
for b=1:r.TileCount
    coefficient=weights(:,b).'*flat(indices(:,b),:);
    coefficients(b,:)=coefficient;
    weighted=weighted+r.ReferenceEnergyPerTile(b)*abs(coefficient).^2;
    biasWeighted=biasWeighted+r.ReferenceEnergyPerTile(b)*sum(abs(weights(:,b)).^2);
end
raw=weighted/r.NormalizationPilotCount;
end
function componentClosure(r,grid,terms)
% Applying the SAME recorded projection is real linear here. Retain all
% coherent cross terms; these are not four independently additive powers.
[original,total]=project(r,grid); coefficients=cell(1,4); energies=cell(1,4);
for k=1:4, [coefficients{k},energies{k}]=project(r,terms{k}); end
sumCoefficients=coefficients{1}+coefficients{2}+coefficients{3}+coefficients{4};
assert(max(abs(original-sumCoefficients),[],'all')<1e-12);
sumPower=energies{1}+energies{2}+energies{3}+energies{4};
for j=1:4
    for k=j+1:4
        cross=zeros(1,r.ReceiveColumnCount);
        for b=1:r.TileCount
            cross=cross+r.ReferenceEnergyPerTile(b)* ...
                2*real(coefficients{j}(b,:).*conj(coefficients{k}(b,:)));
        end
        sumPower=sumPower+cross/r.NormalizationPilotCount;
    end
end
assert(max(abs(total-sumPower))<1e-12*max(1,max(abs(total))));
end
function e=originalRecurrence(carrier,reference,received,cdm,disturbance)
% Test-only original pre-receipt arithmetic, preserving operation order.
K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
nRx=size(received,3); ports=size(reference,3);
X=reshape(double(reference),K*L,ports); Y=reshape(double(received),K*L,nRx);
remaining=X(:,1)~=0; count=nnz(remaining); rawSum=zeros(1,nRx); biasSum=0; groups=0;
while any(remaining)
    first=find(remaining,1); [k,l]=ind2sub([K L],first);
    [kk,ll]=ndgrid(k+(0:cdm(1)-1),l+(0:cdm(2)-1)); tile=sub2ind([K L],kk(:),ll(:));
    pilot=X(tile,1); energy=sum(abs(pilot).^2); weights=conj(pilot)/energy;
    coefficient=weights.'*Y(tile,:);
    rawSum=rawSum+energy*abs(coefficient).^2;
    biasSum=biasSum+energy*sum(abs(weights).^2);
    remaining(tile)=false; groups=groups+1;
end
raw=rawSum/count; unitBias=biasSum/count; bias=unitBias*double(disturbance(:).');
e=struct('RawPort3000PowerPerBranch',raw,'EstimatedNoiseBiasPerBranch',bias, ...
    'SignedPort3000PowerPerBranch',raw-bias,'UnitDisturbancePowerBias',unitBias,'PilotCount',count, ...
    'CDMGroupCount',groups,'CDMLengths',double(cdm(:).'),'ClippedToNonnegative',false, ...
    'NoiseBiasModel',"locally_uncorrelated_disturbance_CSI_IM_matched_second_moment", ...
    'SignalModel',"per_CDM_tile_effective_channel_no_wideband_coherent_average", ...
    'RatioInterpretation',"signed_power_debiased_not_unbiased_ratio_dB_or_selected_max", ...
    'Source',"received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power");
end
function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Unexpected error: %s',cause.identifier); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
