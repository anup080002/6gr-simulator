function ok=testPDCCHTransmitDiversityPower()
% Actual production mapper: total RE power, bundle identity and repetitions.
setup6GRSimToolkit('Verbose',false);
cfg=struct('EnableTransmitDiversity',true,'NTx',4, ...
    'DiversityMode','transparent','PrecoderGranularity','reg_bundle', ...
    'CORESET',struct('REGBundleSize',2));
% Non-contiguous REGs exercise real bundle IDs, not candidate-local order.
regs=[1;2;5;6;9;10]; sc=[0;3;6;9;12;15]; sy=[0;0;1;1;2;2];
T=table(repmat(regs,2,1),repmat(sc,2,1),repmat(sy,2,1), ...
    [ones(6,1);2*ones(6,1)], ...
    'VariableNames',{'REGIndex','Subcarrier','Symbol','SlotIndex'});
g=complex(zeros(24,14,1,2));
indices=sub2ind(size(g),T.Subcarrier+1,T.Symbol+1,ones(height(T),1),T.SlotIndex);
g(indices)=exp(1j*(1:height(T)).');
initialRNG=rng;
for nTx=[2 4 8]
    cfg.NTx=nTx;
    y=sixgr.ctrl.applyPDCCHStudyTransmitDiversity(g,cfg,817,T);
    assert(isequal(rng,initialRNG),'Precoder generation must not mutate the campaign RNG.');
    p=sum(abs(y).^2,3);
    assert(max(abs(p(:)-abs(g(:)).^2))<1e-12, ...
        'Diversity must preserve total power on each RE, not only aggregate energy.');
    assert(isequal(y,sixgr.ctrl.applyPDCCHStudyTransmitDiversity(g,cfg,817,T)));
    stream=RandStream('mt19937ar','Seed',817);
    phase=exp(1j*pi/2*randi(stream,[0 3],5,nTx))/sqrt(nTx);
    for k=1:height(T)
        actual=reshape(y(T.Subcarrier(k)+1,T.Symbol(k)+1,:,T.SlotIndex(k)),1,[])/g(indices(k));
        expected=phase(ceil(T.REGIndex(k)/2),:);
        assert(max(abs(actual-expected))<1e-12, ...
            'DMRS/data and repeated slots must use their actual shared REG-bundle weights.');
    end
    cfg.PrecoderGranularity='none';
    flat=sixgr.ctrl.applyPDCCHStudyTransmitDiversity(g,cfg,817,T);
    p=sum(abs(flat).^2,3);
    assert(max(abs(p(:)-abs(g(:)).^2))<1e-12);
    cfg.PrecoderGranularity='reg_bundle';
end
localReject(@()sixgr.ctrl.applyPDCCHStudyTransmitDiversity(g,cfg,817,T(2:end,:)), ...
    'sixgr:ctrl:TransmitDiversityBundleMap');
bad=cat(3,g,g);
localReject(@()sixgr.ctrl.applyPDCCHStudyTransmitDiversity(bad,cfg,817,T), ...
    'sixgr:ctrl:TransmitDiversityLogicalPort');
localReceivedBundleEstimation();
localRunnerPower();
fprintf('PDCCH_DIVERSITY_POWER_PASS: 2/4/8 TX, per-RE power, real REG bundles, repeated slots and invalid mappings.\n');
ok=true;
end

function localReceivedBundleEstimation()
% Independent received responses: no TX phase weights reach the receiver.
[sc,sy]=ndgrid((0:47)',0:1);
loc=table(sc(:),sy(:),ones(numel(sc),1),ones(numel(sc),1), ...
    floor(sc(:)/12)+1+4*sy(:), ...
    'VariableNames',{'Subcarrier','Symbol','SlotIndex','CopyIndex','REGIndex'});
pilot=ismember(mod(loc.Subcarrier,12),[0 4 8]);
dmrs=struct('Locations',loc(pilot,:),'Symbols',ones(sum(pilot),1));
payload=loc(~pilot,:);
h=[1+1i 2-1i; -2+1i 1-2i; .5-2i -1+.5i; 2+2i -.5-1i];
rx=complex(zeros(48,14,2));
for k=1:height(loc)
    rx(loc.Subcarrier(k)+1,loc.Symbol(k)+1,:)=h(ceil(loc.REGIndex(k)/2),:);
end
cfg=struct('ChannelModel','AWGN','EnableTransmitDiversity',true, ...
    'NTx',4,'PrecoderGranularity','reg_bundle','CORESET',struct('REGBundleSize',2));
est=sixgr.ctrl.PDCCHChannelEstimator(rx,dmrs,cfg,1,[],payload);
assert(max(abs(est.HData-h(ceil(payload.REGIndex/2),:)),[],'all')<1e-12 && ...
    max(abs(est.Residual),[],'all')<1e-12 && ...
    est.ChannelEstimateSource=="received_dmrs_per_reg_bundle_awgn", ...
    'A changing precoder must not be averaged into a burst-wide AWGN scalar or counted as noise.');
end

function localRunnerPower()
root=fullfile(pwd,'results','lls','pdcch_diversity_power', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
input=struct('phy',struct('carrier',struct('NSizeGrid',24),'numerology',struct('mu',1)), ...
    'ctrl6gr',struct('BlindDetectionEnabled',true,'NRx',2,'Seed',817, ...
    'EnableTransmitDiversity',true,'DiversityMode','transparent', ...
    'PrecoderGranularity','reg_bundle','WaveformMode','grid_mode'));
point=struct('ScenarioID','power','AggregationLevel',4,'CORESETDuration',2, ...
    'MappingType','noninterleaved','FrequencyAllocationMode','contiguous', ...
    'RepetitionMode','none','SNRdB',40,'ChannelModel','AWGN', ...
    'SearchSpaceType','USS','DMRSVariant','single_port_density_3_per_rb', ...
    'REGBundleSize',2,'NumREGPerCCE',6,'MRSSMode','exclusive_6gr','NumTrials',1);
energy=zeros(3,1); trials=table();
ports=[1 2 4];
for k=1:numel(ports)
    input.ctrl6gr.NTx=ports(k);
    out=sixgr.ctrl.runPDCCHStudyLLS(input,'ScenarioMatrix',point, ...
        'WriteOutputs',false,'OutputDir',fullfile(root,sprintf('tx%d',ports(k))));
    energy(k)=out.PDCCHTrials.TXGridEnergy;
    T=out.PDCCHTrials; T.ConfiguredTxPorts=repmat(ports(k),height(T),1);
    trials=[trials;T]; %#ok<AGROW>
end
assert(all(abs(energy-energy(1))<1e-10) && all(energy>0), ...
    'The coded production runner must preserve the same total transmitted energy across TX dimensions.');
assert(all(logical(trials.CRCPass)) && all(logical(trials.PDCCHPayloadMatch)), ...
    'The deterministic high-SNR power comparison must also recover the coded payloads.');
writetable(trials,fullfile(root,'power_trials.csv'));
save(fullfile(root,'power_comparison.mat'),'input','point','ports','energy');
fprintf('PDCCH_DIVERSITY_RUNNER_EVIDENCE=%s\n',root);
end
function localReject(action,id)
threw=false;
try, action(); catch ME, threw=strcmp(ME.identifier,id); end
assert(threw,'Malformed transmitter mapping must not be silently repaired.');
end
