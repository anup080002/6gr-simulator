function ok=testSRSPilotPhaseMeasurement()
% Actual SRS OFDM receiver, independent applied phase, no frequency oracle.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_four_port_shared_awgn_12db.yaml');
folder=fullfile(pwd,'results','lls','srs_pilot_phase',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); cfg=sixgr.lls6g.buildInternalConfig(source,folder);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
rows=struct([]);
for ports=[1 2 4]
    for numSymbols=[1 4]
        carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15);
        srs=strict.ToolboxSRS; srs.NumSRSPorts=ports; srs.SRSPeriod='on';
        srs.NumSRSSymbols=numSymbols; srs.SymbolStart=14-numSymbols;
        srs.CSRS=0; srs.BSRS=0; srs.BHop=0; srs.Repetition=1;
        % Equal-amplitude spatial phases cancel under the old complex mean.
        spatial=exp(2i*pi*(0:ports-1)'*(0:ports-1)/ports)/sqrt(ports);
        spatial=[spatial -spatial];
        for rate=[-75 0 75]
            history=struct();
            for occasion=0:1
                origin=.005*occasion; carrier.NSlot=5*occasion;
                indices=nrSRSIndices(carrier,srs); symbols=nrSRS(carrier,srs);
                grid=nrResourceGrid(carrier,ports); grid(indices)=symbols;
                [wave,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
                wave=(wave*spatial).*exp(2i*pi*rate*(origin+(0:size(wave,1)-1)'/ofdm.SampleRate));
                % Nonzero independently seeded noise satisfies the real
                % receiver contract, including the zero phase-rate case.
                noise=RandStream('mt19937ar','Seed',75413+ports*100+numSymbols*10+occasion);
                variance=1e-7/double(ofdm.Nfft);
                wave=wave+sqrt(variance/2)*(randn(noise,size(wave))+1i*randn(noise,size(wave)));
                [rx,info]=sixgr.phy.ul.SRS_Rx(wave,cfg,'Carrier',carrier,'SRS',srs);
                [phase,history]=sixgr.phy.rx.pilotChannelPhaseEvolution( ...
                    carrier,rx.Hest,rx.SRSIndices,rx.SRSSymbols,info.OFDMInfo, ...
                    'ObservationStartTime_s',origin,'ContextID','native_SRS_receiver', ...
                    'PreviousObservation',history);
                if occasion==0 && numSymbols==1
                    assert(isnan(phase.CommonPhaseRate_Hz) && phase.PairCount==0 && ...
                        phase.CurrentObservationTime_s==history.LastTime_s && ...
                        isnan(phase.PreviousObservationTime_s) && ...
                        isnan(phase.ObservationSeparation_s));
                else
                    assert(abs(phase.CommonPhaseRate_Hz-rate)<1, ...
                        'test:SRSPhaseAccuracy','Actual SRS rate differs by >=1 Hz (ports=%d symbols=%d).',ports,numSymbols);
                end
                row=struct('Ports',ports,'ReceiveBranches',2*ports,'SRSSymbols',numSymbols, ...
                    'Occasion',occasion,'AppliedCommonPhaseRate_Hz',rate, ...
                    'MeasuredCommonPhaseRate_Hz',phase.CommonPhaseRate_Hz, ...
                    'AliasHalfWidth_Hz',phase.UnaliasedHalfWidth_Hz, ...
                    'Pairs',phase.PairCount,'MatchedValues',phase.MatchedChannelValueCount, ...
                    'Scope',phase.ObservationScope,'ScenarioAccepted',false,'StatisticallyQualified',false);
                rows=[rows;row]; %#ok<AGROW>
            end
        end
    end
end
sixgr.util.csvWriteTable(fullfile(folder,'native_srs_phase.csv'),struct2table(rows),'PreserveSchema',true);
id=sixgr.truth.srsPilotPhaseContextID(cfg,'epoch1',1,1);
changed=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,10);
changed.channel.doppler_Hz=987; changed.channel.snr_dB=-999;
assert(sixgr.truth.srsPilotPhaseContextID(changed,'epoch1',1,1)==id, ...
    'Runtime clock, SNR and configured Doppler must not reset/drive measured history.');
assert(sixgr.truth.srsPilotPhaseContextID(cfg,'epoch2',1,1)~=id && ...
    sixgr.truth.srsPilotPhaseContextID(cfg,'epoch1',2,1)~=id && ...
    sixgr.truth.srsPilotPhaseContextID(cfg,'epoch1',1,2)~=id);
changed=cfg; changed.phy.srs.nPorts=2;
assert(sixgr.truth.srsPilotPhaseContextID(changed,'epoch1',1,1)~=id);
fprintf('SRS_PILOT_PHASE_MEASUREMENT_PASS cases=%d evidence=%s\n',numel(rows),folder);
ok=true;
end
