function ok=testCSIRSFlatMeasurement()
% Actual CSI-RS OFDM + AWGN. Execution metadata below is a declared model
% contract fixture, not evidence of a complete shared-runtime execution.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15,'NCellID',17);
rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',4, ...
    'Density','one','SymbolLocations',6,'SubcarrierLocations',0,'NumRB',25);
indices=nrCSIRSIndices(carrier,rs); symbols=nrCSIRS(carrier,rs);
tx=nrResourceGrid(carrier,4); tx(indices)=symbols;
H=[.8 0 .6 0;0 .6 0 .8]; waveform=nrOFDMModulate(carrier,tx)*H.';
rf=struct('RFConfiguredStageCount',0,'RFAppliedStageCount',0);
link=struct('TX',"gnb",'RX',"ue",'Replay',struct( ...
    'RuntimeChannelTimingTruthSource',"executed_fixed_matrix_operator_zero_delay",'ChannelFadingApplied',false));
execution=struct('NoiseOperatingMode',"standalone_awgn_snr_argument",'ReceiverID',"ue",'TransmitterID',"gnb", ...
    'ReceiveStreamExecutionSegments',{{struct('Execution',struct('Links',link, ...
    'TX',struct('ID',"gnb",'Replay',rf),'RX',struct('ID',"ue",'Replay',rf)))}});
cfg=struct('phy',struct('csirs',struct('runtimeChannelEstimator',"flat_static_awgn_ls")));
K=300; L=14; physical=unique(mod(double(indices(:))-1,K*L)+1);
X=reshape(tx,K*L,4); X=X(physical,:); C=(X'*X)\eye(4);
c=real(C(1,1)); d=size(X,1)-4; episodes=256; rows=struct([]);
for imEnabled=[false true]
    cfg.phy.csiim=struct('enabled',imEnabled,'resource_id',0,'pattern',1,'subcarrier',0, ...
        'symbol',7,'starting_rb',0,'num_rbs',24,'period_slots',5,'offset_slots',0);
    plan=sixgr.phy.refsig.csiIMResource(carrier,cfg);
    for point=[NaN -30 -20 -10 0 10 20 30 40]
        noiseOnly=isnan(point); snr=point; signal=waveform; expected=abs(H(:,1).').^2;
        if noiseOnly, snr=0; signal(:)=0; expected(:)=0; end
        variance=10^(-snr/10); power=zeros(episodes,2); ratio=power;
        for k=1:episodes
            capture=sixgr.phy.waveform.addOccupiedREAWGN(signal,carrier,snr, ...
                'Seed',9244100+k,'SignalEnergyPerOccupiedRE',1);
            grid=nrOFDMDemodulate(carrier,capture);
            measured=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,rs,grid,cfg,execution);
            evidence=measured.SignalPowerEstimation;
            power(k,:)=evidence.SignedPort3000PowerPerBranch;
            ratio(k,:)=evidence.SignedPort3000SNRLinearPerBranch;
            assert(~evidence.ClippedToNonnegative);
            if k==1
                poison=execution; poison.InjectedNoiseVariance=1e30; poison.AppliedAWGNSNR_dB=Inf;
                same=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,rs,grid,cfg,poison);
                assert(isequaln(measured,same),'Scoring truth must not enter measurement.');
                scaled=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,rs,grid*1e-8,cfg,execution);
                assert(max(abs(scaled.SignalPowerEstimation.SignedPort3000SNRLinearPerBranch-ratio(k,:))) ...
                    <1e-9*max(1,max(abs(ratio(k,:)))));
            end
        end
        rho=expected/variance;
        powerVariance=2*c*variance*expected+(c*variance)^2*(1+1/d);
        if imEnabled
            m=plan.NumRE;
            ratioVariance=(m-1)/(m-2)*powerVariance/variance^2+rho.^2/(m-2);
        else
            ratioVariance=c^2*((d-1)*(1+2*rho/c)+(1+rho/c).^2)/(d-2);
        end
        for branch=1:2
            pz=(mean(power(:,branch))-expected(branch))/sqrt(powerVariance(branch)/episodes);
            rz=(mean(ratio(:,branch))-rho(branch))/sqrt(ratioVariance(branch)/episodes);
            assert(abs(pz)<6 && abs(rz)<6,'Port-3000 ensemble bias exceeds frozen six-SE bound.');
            if expected(branch)==0
                assert(any(power(:,branch)<0) && any(ratio(:,branch)<0));
            end
            row=struct('CSIIMEnabled',imEnabled,'NoiseOnly',noiseOnly,'ReferenceSNR_dB',point, ...
                'ReceiveBranch',branch,'Episodes',episodes,'SignedPowerMean',mean(power(:,branch)), ...
                'ValidationPower',expected(branch),'PowerZScore',pz,'SignedSNRMean',mean(ratio(:,branch)), ...
                'ValidationSNR',rho(branch),'SNRZScore',rz,'Pass',true);
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
        fprintf('CSI_FLAT_GROUP im=%d snr=%g noiseOnly=%d PASS\n',imEnabled,point,noiseOnly);
    end
end
bad=execution; bad.ReceiveStreamExecutionSegments{1}.Execution.Links.Replay.ChannelFadingApplied=true;
rejected=false;
try
    sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,rs,grid,cfg,bad);
catch e
    rejected=strcmp(e.identifier,'sixgr:phy:rx:FlatAWGNObservationRequired');
end
assert(rejected,'A fading operator cannot use flat CSI estimation.');
folder=fullfile(pwd,'results','lls','csirs_flat_measurement',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); writetable(struct2table(rows),fullfile(folder,'port3000_statistics.csv'));
fprintf('CSI_FLAT_MEASUREMENT_PASS cases=%d episodes=%d output=%s\n',numel(rows),18*episodes,folder);
ok=true;
end
