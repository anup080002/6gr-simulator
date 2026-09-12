function ok=testTwoPortULYAMLAndSRS()
% YAML resolution plus an independent 12 dB pilot-waveform receiver fixture.
% This is not a replacement for the shared-CDL full-scenario validation.
setup6GRSimToolkit('Verbose',false); rng(90021,'twister');
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.pusch.NumAntennaPorts==2 && cfg.phy.pusch.numAntennaPorts==2 && ...
    cfg.phy.srs.nPorts==2 && cfg.phy.pusch.numLayers==1);
data=struct('ULPrecoding',cfg.phy.pdcch.operatorControl.ul_precoding, ...
    'TransformPrecodingEnabled',cfg.phy.pusch.transformPrecoding);
field=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
assert(field.Width==3 && data.ULPrecoding.max_rank==1);
grant=struct('SymbolAllocation',cfg.phy.pusch.symbolAllocation,'RNTI',1, ...
    'NumLayers',1,'TPMI',3);
context=sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,grant,'0_1');
assert(sixgr.phy.pdcch.ULPrecodingField.encode(context.Data,1,3)==3);
wrong=cfg; wrong.phy.pusch.NumAntennaPorts=1;
rejected=false;
try, sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(wrong,grant,'0_1');
catch ME, rejected=string(ME.identifier)=="sixgr:phy:pdcch:ULPrecodingContextMismatch"; end
assert(rejected,'DCI context must reject sounding/data port disagreement.');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5);
[tx,~]=sixgr.phy.ul.SRS_Tx(cfg);
assert(tx.SRS.NumSRSPorts==2 && size(tx.Waveform,2)==2 && ~isempty(tx.SRSIndices));
assert(numel(unique(floor((double(tx.SRSIndices(:))-1)/(size(tx.Grid,1)*size(tx.Grid,2)))))==2);
% Both ports are actually transmitted through one non-symmetric channel.
H=[1 -.8; .3 -.5];
ofdm=nrOFDMInfo(tx.Carrier);
noise=10^(-12/10)/double(ofdm.Nfft);
wave=tx.Waveform*H.'+sqrt(noise/2)*complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)));
[rx,~]=sixgr.phy.ul.SRS_Rx(wave,cfg,'Carrier',tx.Carrier,'SRS',tx.SRS);
assert(size(rx.Hest,3)==2 && size(rx.Hest,4)==2 && rx.NoiseVar>0);
measured=sixgr.phy.ul.estimateSRSRITPMI(rx.Hest,rx.NoiseVar,cfg);
assert(measured.Valid && measured.RI==1 && measured.TPMI==3, ...
    'The received two-port SRS must select the independently optimal opposing-phase TPMI, not configured bootstrap zero.');
W=nrPUSCHCodebook(1,2,measured.TPMI).';
assert(abs(sum(abs(W).^2,'all')-1)<1e-12);
assert(sum(abs(H*W).^2)>sum(abs(H*nrPUSCHCodebook(1,2,0).').^2));
ok=true;
end
