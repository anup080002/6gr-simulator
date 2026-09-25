function ok=testCSIDisturbanceAuthority()
% Analytical receiver/covariance fixtures, not an integrated PHY campaign.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15,'NCellID',17);
csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',4,'Density','one', ...
    'SymbolLocations',6,'SubcarrierLocations',0,'NumRB',25);
dmrs=nrPDSCHDMRSConfig;
H=repmat(reshape(eye(4),1,1,4,4),300,14,1,1);
nVar=.01;
U=fft(eye(4))/2;
interference=U*diag([10 2 .4 .2])*U';
total=interference+nVar*eye(4);
for codebook=["typeI-SinglePanel","typeII"]
    request=struct('ReportConfigID',"covariance_fixture",'Epoch',0, ...
        'CodebookType',codebook,'CodebookMode',1,'Panels',1, ...
        'Ports',4,'Rank',1,'MaxRank',2,'AllowedRanks',[1 2], ...
        'N1',2,'N2',1,'O1',4,'O2',1,'NumberOfBeams',2,'PhaseAlphabetSize',4, ...
        'ReportQuantity',"cri-ri-li-pmi-cqi",'NumCSIResources',1, ...
        'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
    cfg=struct('Strict',true,'RankDomain',[1 2],'CQITable',"table1", ...
        'ReportConfiguration',request,'CurrentSlot',0);
    run=@(state) sixgr.phy.mimo.NRCSIReportEngine.run(carrier,csirs,dmrs,H,nVar,cfg,state);
    a=run(measurement(interference,false,nVar));
    b=run(measurement(total,true,nVar));
    white=run(measurement([],false,nVar));
    assert(isequaln(a.PMISet,b.PMISet) && a.RI==b.RI && a.CQI==b.CQI && ...
        abs(a.WidebandSINR_dB-b.WidebandSINR_dB)<1e-12, ...
        'Noise must enter the receiver covariance exactly once.');
    assert(a.InterferenceCovarianceUsed && ~white.InterferenceCovarianceUsed && ...
        norm(a.DisturbanceCovarianceUsed-total,'fro')<1e-12);
    assert(a.WidebandSINR_dB<white.WidebandSINR_dB-5, ...
        'The high-port CSI engine ignored measured interference.');
    reference=nrCSIReportConfig('NSizeBWP',25,'PanelDimensions',[1 2 1], ...
        'CQIFormatIndicator','wideband','PMIFormatIndicator','wideband');
    if codebook=="typeII"
        reference.CodebookType='type2'; reference.NumberOfBeams=2;
        reference.PhaseAlphabetSize=4; reference.RIRestriction=[1 1];
    else
        reference.CodebookType='type1SinglePanel'; reference.CodebookMode=1;
        reference.RIRestriction=[1 1 0 0 0 0 0 0];
    end
    ri=nr5g.internal.nrRISelect(carrier,csirs,reference,H,total,'MaxSE');
    [cqi,pmi,~,pinfo]=nr5g.internal.nrCQIReport(carrier,csirs,reference,dmrs,ri,H,total);
    assert(a.RI==ri && a.CQI==cqi(1) && isequaln(a.PMISet,pmi));
    % Independently compute post-combiner desired/inter-layer/disturbance
    % powers. Do not call the simulator's SINR helper for the reference.
    W=pinfo.W(:,:,1);
    F=(eye(ri)+W'*(total\W))\(W'/total);
    effective=F*W;
    desired=abs(diag(effective)).^2;
    unwanted=sum(abs(effective-diag(diag(effective))).^2,2);
    expected=desired./(unwanted+real(diag(F*total*F')));
    expectedDB=10*log10(expm1(mean(log1p(expected))));
    assert(abs(a.WidebandSINR_dB-expectedDB)<1e-8, ...
        'CSI SINR disagrees with explicit complex-covariance receiver powers.');
    reject(@()run(measurement(interference,false,2*nVar)), ...
        'sixgr:mimo:MeasurementIdentityMismatch');
    reject(@()run(measurement(eye(3),false,nVar)), ...
        'sixgr:mimo:InvalidInterferenceCovariance');
    reject(@()run(measurement(diag([1 1 1 -1]),false,nVar)), ...
        'sixgr:mimo:InvalidInterferenceCovariance');
    fprintf('CSI_DISTURBANCE %s RI=%g CQI=%g SINR=%g whiteSINR=%g no_double_noise=1\n', ...
        codebook,a.RI,a.CQI,a.WidebandSINR_dB,white.WidebandSINR_dB);
end
% The lower-port codebook engine must honor the same noise-inclusion flag.
candidates=complex(zeros(2,1,2));
candidates(:,:,1)=[1;1]/sqrt(2); candidates(:,:,2)=[1;1i]/sqrt(2);
R=[.3 .1i;-.1i .4];
[w1,d1]=sixgr.phy.mimo.CodebookEngine.select(eye(2),candidates, ...
    NoiseVariance=nVar,InterferenceCovariance=R);
[w2,d2]=sixgr.phy.mimo.CodebookEngine.select(eye(2),candidates, ...
    NoiseVariance=nVar,InterferenceCovariance=R+nVar*eye(2), ...
    InterferenceCovarianceIncludesNoise=true);
assert(isequal(w1,w2) && isequaln(d1,d2));
fprintf('CSI_DISTURBANCE_AUTHORITY_PASS TypeI_TypeII=1 complex_covariance_math=1 lower_port_noise_once=1\n');
ok=true;
end

function state=measurement(R,includesNoise,nVar)
state=sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="covariance_unit_fixture",UEID="UE-1", ...
    ResourceType="NZP-CSI-RS",ResourceID="CSI-RS-0",ResourceOrdinal=0, ...
    Slot=0,MaxAgeSlots=4,ChannelEstimate=eye(4),NoiseVariance=nVar, ...
    InterferenceCovariance=R,InterferenceCovarianceIncludesNoise=includesNoise, ...
    Provenance="measured_contract_analytical_unit_fixture_not_phy_campaign");
end

function reject(action,id)
try, action(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:MissingRejection','Expected %s',id);
end
