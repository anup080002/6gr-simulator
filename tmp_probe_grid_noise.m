setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg = sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml');
cfg = sixgr.lls6g.buildInternalConfig(scfg,pwd);
cfg = sixgr.config.normalizeConfig(cfg);
snr = 20;
[tx,txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg);
fs = txInfo.OFDM.SampleRate;
ch = sixgr.channel.ChannelFactory.create(cfg,'Model',cfg.channel.model,'SampleRate',fs,'NumTxAnt',size(tx.Waveform,2),'NumRxAnt',double(sixgr.util.structGet(cfg,'phy.nRxAnt',size(tx.Waveform,2))),'Seed',sixgr.util.structGet(cfg,'run.seed',1));
if isfield(ch,'Object') && ~isempty(ch.Object)
  try, reset(ch.Object); catch, end
  xIn = tx.Waveform;
  try
    infoCh = info(ch.Object);
    fd = double(sixgr.util.structGet(infoCh,'ChannelFilterDelay',0));
    pd = sixgr.util.structGet(infoCh,'PathDelays',[]);
    md = 0;
    if ~isempty(pd), md = ceil(max(double(pd))*fs); end
    pad = max(fd,md);
  catch
    pad = 0;
  end
  if pad > 0, xIn = [xIn; zeros(pad,size(xIn,2),'like',xIn)]; end
  try
    yRaw = ch.Object(xIn);
  catch
    [yRaw,~] = ch.Object(xIn);
  end
  if size(yRaw,1) > size(tx.Waveform,1)
    y = yRaw(1:size(tx.Waveform,1),:);
  else
    y = yRaw;
  end
else
  y = tx.Waveform;
end
[yNoisy,nVarInjected] = sixgr.util.addAwgnComplex(y,snr);
[gridClean,~] = sixgr.phy.waveform.ofdmDemodulate(tx.Carrier,y);
[gridNoisy,~] = sixgr.phy.waveform.ofdmDemodulate(tx.Carrier,yNoisy);
gridNoise = gridNoisy - gridClean;
noiseVarGrid = mean(abs(gridNoise(:)).^2);
sigPowGrid = mean(abs(gridClean(:)).^2);
snrGrid = 10*log10(sigPowGrid/max(noiseVarGrid,eps));
disp(struct('snrTimeInput',snr,'nVarInjectedTime',nVarInjected,'signalPowTime',mean(abs(y(:)).^2),'signalPowGrid',sigPowGrid,'noiseVarGrid',noiseVarGrid,'snrGrid',snrGrid));
