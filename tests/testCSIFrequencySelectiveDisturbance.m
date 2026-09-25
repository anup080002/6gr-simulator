function ok=testCSIFrequencySelectiveDisturbance()
% Independent grid fixtures: distinguish native estimator leakage from
% actual disturbance measured on explicitly configured muted CSI-IM REs.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',100,'SubcarrierSpacing',30);
rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',3, ...
    'Density','one','SymbolLocations',4,'SubcarrierLocations',0,'NumRB',100);
ref=nrResourceGrid(carrier,2); ref(nrCSIRSIndices(carrier,rs))=nrCSIRS(carrier,rs);
cfg.phy.csiim=struct('enabled',true,'resource_id',0,'pattern',1,'subcarrier',4, ...
    'symbol',7,'starting_rb',0,'num_rbs',100,'period_slots',5,'offset_slots',0);
plan=sixgr.phy.refsig.csiIMResource(carrier,cfg);
variance=10^(-12/10); stream=RandStream('mt19937ar','Seed',924612);
rows=struct([]);
for cycles=[0 2 -2]
    clean=ref(:,:,1).*exp(-1j*2*pi*(0:1199)'*cycles/1200);
    assert(all(clean(plan.PhysicalIndices1Based)==0));
    [~,leakage]=nrChannelEstimate(carrier,clean,ref,'CDMLengths',[2 1]);
    for episode=1:64
        y=clean+sqrt(variance/2)*complex(randn(stream,size(clean)),randn(stream,size(clean)));
        residual=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,rs,y);
        muted=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,rs,y,cfg);
        actual=mean(abs(y(plan.PhysicalIndices1Based)).^2);
        assert(abs(muted.NoiseInterferencePowerPerReceiveAntenna-actual)<1e-14);
        assert(muted.DisturbanceSource=="configured_CSI_IM_received_RE_second_moment");
        assert(muted.ChannelEstimatorDisturbancePerReceiveAntenna== ...
            residual.ChannelEstimatorDisturbancePerReceiveAntenna);
        assert(muted.DesiredPowerPerReceiveAntenna==residual.DesiredPowerPerReceiveAntenna);
        row=struct('PhaseCyclesAcrossBand',cycles,'Episode',episode, ...
            'ValidationInjectedNoiseVariance',variance,'NoiselessNativeNoiseEstimate',leakage, ...
            'ReferenceResidualNoiseEstimate',residual.NoiseInterferencePowerPerReceiveAntenna, ...
            'MeasuredCSIIMNoise',actual,'ResidualSINR_dB',residual.CSI_SINR_dB, ...
            'CSIIMSINR_dB',muted.CSI_SINR_dB,'ValidationSINR_dB',12, ...
            'EvidenceScope',"received_grid_component_not_scenario_acceptance");
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    end
end
T=struct2table(rows);
folder=fullfile(pwd,'results','lls','csi_frequency_selective_disturbance', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); writetable(T,fullfile(folder,'measurements.csv'));
for cycles=[0 2 -2]
    group=T(T.PhaseCyclesAcrossBand==cycles,:);
    assert(abs(mean(group.CSIIMSINR_dB)-12)<1.5, ...
        'Independent CSI-IM did not meet the unchanged reference-SINR accuracy bound.');
    z=(mean(group.MeasuredCSIIMNoise)-variance)/(variance/sqrt(64*plan.NumRE));
    assert(abs(z)<6,'Muted-RE disturbance estimate disagrees with independent noise statistics.');
    fprintf('CSI_FREQUENCY_SELECTIVE cycles=%g residualSINR=%g CSIIMSINR=%g noiselessLeakage=%g noiseZ=%g\n', ...
        cycles,mean(group.ResidualSINR_dB),mean(group.CSIIMSINR_dB),group.NoiselessNativeNoiseEstimate(1),z);
end
fprintf('CSI_FREQUENCY_SELECTIVE_DISTURBANCE_PASS episodes=%d output=%s\n',height(T),folder);
ok=true;
end
