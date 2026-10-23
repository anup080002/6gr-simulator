function ok=testConnectedCORESETRateMatching()
% Exact RE exclusion, shared TX/RX construction, and pilot-collision guards.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',15,'NSlot',1);
p=nrPDSCHConfig('PRBSet',0:23,'SymbolAllocation',[0 14],'NumLayers',1);
p.DMRS.DMRSTypeAPosition=2;
cfg.phy.pdsch.rateMatchingPattern="connected_coreset";
cfg.phy.pdcch.coreset=struct('frequencyResources',[1 0 1], ...
    'rbStart',0,'duration',2);
cfg.phy.pdcch.operatorControl.connected_monitoring=struct( ...
    'cce_reg_mapping','noninterleaved','reg_bundle_size',6,'interleaver_size',2, ...
    'shift_index',0,'precoder_granularity','sameAsREG-bundle','start_symbol',0, ...
    'period_slots',2,'offset_slots',1,'duration_slots',1,'dmrs_scrambling_id',1);
baseline=double(nrPDSCHIndices(carrier,p,'IndexBase','0based'));
[tx,e]=sixgr.phy.grid.reserveConnectedCORESETPDSCHResources(carrier,p,cfg);
[rx,er]=sixgr.phy.grid.reserveConnectedCORESETPDSCHResources(carrier,p,cfg);
data=double(nrPDSCHIndices(carrier,tx,'IndexBase','0based'));
assert(isequal(data,double(nrPDSCHIndices(carrier,rx,'IndexBase','0based'))) && isequal(e,er));
prbs=[0:5 12:17]; [k,l]=ndgrid(reshape(12*prbs+(0:11).',[],1),0:1);
excluded=double(k(:)+12*carrier.NSizeGrid*l(:));
assert(isempty(intersect(data,excluded)) && ...
    isequal(sort(data(:)),setdiff(baseline(:),excluded)), ...
    'Only the configured PRB/symbol pattern may be removed.');
assert(numel(baseline)-numel(data)==12*12*2 && ...
    isequal(nrPDSCHDMRSIndices(carrier,p),nrPDSCHDMRSIndices(carrier,tx)));
off=carrier; off.NSlot=0;
[offP,offE]=sixgr.phy.grid.reserveConnectedCORESETPDSCHResources(off,p,cfg);
assert(~offE.Enabled && isequal(nrPDSCHIndices(off,offP),nrPDSCHIndices(off,p)));
bad=cfg; bad.phy.pdcch.coreset.duration=3;
caught=false;
try
    sixgr.phy.grid.reserveConnectedCORESETPDSCHResources(carrier,p,bad);
catch err
    caught=strcmp(err.identifier,'sixgr:pdsch:CORESETPilotCollision');
end
assert(caught,'A control pattern colliding with DM-RS must fail before coding.');
withPTRS=p; withPTRS.EnablePTRS=true;
withPTRS.PTRS.TimeDensity=1; withPTRS.PTRS.FrequencyDensity=2;
[mapped,~]=sixgr.phy.grid.reserveConnectedCORESETPDSCHResources(carrier,withPTRS,cfg);
active=double(nrPDSCHPTRSIndices(carrier,mapped,'IndexBase','0based'));
assert(~isempty(active) && isempty(intersect(active,excluded)), ...
    'PT-RS must remain enabled outside the installed unavailable-resource pattern.');
ok=true;
disp('CONNECTED_CORESET_RATE_MATCH_PASS: exact 288 RE exclusion, outside-pattern data retained');
end
