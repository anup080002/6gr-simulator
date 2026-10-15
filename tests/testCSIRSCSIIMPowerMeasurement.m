function ok=testCSIRSCSIIMPowerMeasurement()
% Independent received-grid populations. NOT RF/statistical UCI qualification.
% Check the analytically derived CDM noise bias, not a fitted correction.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','diagnostics','csirs_csiim_power', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
c=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
cfg.phy.csiim=struct('enabled',true,'resource_id',0,'pattern',1, ...
    'subcarrier',4,'symbol',13,'starting_rb',0,'num_rbs',24, ...
    'period_slots',5,'offset_slots',0);
plan=sixgr.phy.refsig.csiIMResource(c,cfg);
episodes=256; rows=table();
for row=[2 3 8 18]
    offsets=0;
    if row==8, offsets=[0 2]; elseif row==18, offsets=[0 2 4 6]; end
    rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',row, ...
        'Density','one','SymbolLocations',2,'SubcarrierLocations',offsets,'NumRB',24);
    X=nrResourceGrid(c,rs.NumCSIRSPorts); X(nrCSIRSIndices(c,rs))=nrCSIRS(c,rs);
    cdm=sixgr.phy.refsig.csirsCDMLengths(rs.CDMType);
    tileSize=prod(cdm); a=1/tileSize; N=24; M=plan.NumRE;
    for referenceSNR=[NaN -20 0 20]
        expected=0; clean=complex(zeros(288,14));
        if isfinite(referenceSNR)
            expected=10^(referenceSNR/10);
            % Independent phase per RB: no wideband coherent average.
            phase=repelem(exp(2i*pi*(0:23)'/24),12);
            clean=sqrt(expected)*X(:,:,1).*phase;
            % Other ports deliberately stronger. Their CDM coefficients
            % must not be mistaken for antenna-port-3000 reference power.
            for port=2:rs.NumCSIRSPorts
                clean=clean+(2+1i*port/rs.NumCSIRSPorts)*X(:,:,port).*phase;
            end
        end
        powers=zeros(episodes,1);
        for episode=1:episodes
            stream=RandStream('mt19937ar','Seed',814026+episode);
            grid=clean+complex(randn(stream,288,14),randn(stream,288,14))/sqrt(2);
            im=sixgr.phy.refsig.measureCSIIM(c,cfg,grid);
            measured=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,X,grid,cdm,im.PowerPerReceiveAntenna);
            powers(episode)=measured.SignedPort3000PowerPerBranch;
            assert(measured.CDMGroupCount==N && ~measured.ClippedToNonnegative && ...
                abs(measured.UnitDisturbancePowerBias-a)<1e-12);
            if episode==1
                main=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,grid,cfg);
                assert(isequaln(main.DesiredPowerPerReceiveAntenna,powers(episode)) && ...
                    main.DisturbanceSource==im.Source && ...
                    main.Source==measured.Source);
                poison=cfg; poison.channel.snr_dB=300;
                again=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,grid,poison, ...
                    struct('InjectedNoiseVariance',1e99,'AppliedAWGNSNR_dB',300));
                assert(isequaln(main,again),'Configured or injected noise cannot repair a received measurement.');
                scaled=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,grid*1e-5,cfg);
                assert(abs(scaled.DesiredPowerPerReceiveAntenna/1e-10-powers(episode))<1e-9);
            end
        end
        % Complex independent Gaussian pilot and CSI-IM samples have known
        % variance; use a predeclared six-standard-error ensemble bound.
        variance=(a*a+2*a*expected)/N+a*a/M;
        z=(mean(powers)-expected)/sqrt(variance/episodes);
        assert(abs(z)<6,'test:CSICDMPowerBias','CDM power mean exceeds its six-SE bound.');
        if ~isfinite(referenceSNR)
            assert(any(powers<0) && any(powers>0),'Never clip a noise-only linear population.');
        end
        entry=table(row,tileSize,referenceSNR,episodes,expected,mean(powers),z, ...
            'VariableNames',{'CSIRSRow','CDMTileSize','ReferenceSNR_dB','Episodes', ...
            'ExpectedPowerAuditOnly','MeanMeasuredSignedPower','PowerZScore'});
        rows=[rows;entry]; %#ok<AGROW>
        writetable(rows,fullfile(folder,'power_statistics.csv'));
    end
end
% Exact H4 receiver path, including relative-power and per-branch export.
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
h4=sixgr.lls6g.buildInternalConfig(source,tempname);
h4=sixgr.phy.grid.applyRuntimeCarrierTimeline(h4,6);
% The following is declared measurement-plane input for this grid fixture,
% not an assertion that a physical transmitter/front end was executed.
h4.lls6g.runtimePowerContext=struct('WaveformAmplitudeUnit',"normalized_complex_baseband", ...
    'FixedSNRNormalizedReference',true,'PhysicalDevicePowerClaim',false, ...
    'ScaleApplied',false,'AmplitudeScale',1);
carrier=sixgr.phy.grid.makeCarrier(h4); [~,~,info]=sixgr.phy.refsig.csirs(carrier,h4);
grid=complex(zeros(3276,14,4));
% This is a deliberately constructed received-grid boundary fixture, not
% a transmitted waveform: muted REs contain known samples, not a supplied
% noise-variance oracle. With no CSI signal all signed estimates are negative.
imPlan=sixgr.phy.refsig.csiIMResource(carrier,h4);
flat=reshape(grid,[],4); flat(imPlan.PhysicalIndices1Based,:)=1;
grid=reshape(flat,size(grid));
received=struct('OFDMGrid',grid,'OFDMInfo',nrOFDMInfo(carrier));
options=struct('PhysicalMeasurementGrid',grid,'PhysicalMeasurementOFDMInfo',nrOFDMInfo(carrier), ...
    'PhysicalMeasurementGridStatus',"available_exact_pre_front_end_grid", ...
    'PhysicalMeasurementReferencePlane',"normalized_received_grid_fixture", ...
    'PhysicalMeasurementSource',"independent_CSI_IM_grid_fixture");
rx=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,h4,received,options);
evidence=jsondecode(rx.CSIRSObservation.ReferenceSINRMeasurementJSON);
assert(~evidence.Available && all(evidence.DesiredPowerPerReceiveAntenna<0) && ...
    isnan(rx.CSIRSObservation.ReferenceMeasuredSINR_dB), ...
    'Nonpositive observed powers must survive receiver publication as signed evidence.');
% One strong branch must remain reportable without manufacturing positive
% RSRP on the other three branches. Keep their NaNs and signed measurements.
for resource=reshape(info.Resources,1,[])
    X=nrResourceGrid(carrier,resource.NumPorts); X(resource.Indices)=resource.Symbols;
    grid(:,:,1)=grid(:,:,1)+X(:,:,1);
end
received.OFDMGrid=grid; options.PhysicalMeasurementGrid=grid;
rx=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,h4,received,options);
assert(isfinite(rx.CSIRSObservation.MeasurementRSRP_dB_re_UnitOccupiedRE_Es) && ...
    rx.CSIRSObservation.MeasurementReceiveAntennaIndex1Based==1);
scope=struct('Scope',"independent_CDM_CSI_IM_grid_statistics_and_H4_receiver_publication", ...
    'ScenarioAccepted',false,'RFQualified',false,'GenericNoCSIIMEstimatorQualified',false);
save(fullfile(folder,'evidence.mat'),'rows','scope','rx');
fprintf('CSI_IM_CDM_POWER_PASS populations=%d episodes=%d folder=%s\n',height(rows),height(rows)*episodes,folder);
ok=true;
end
