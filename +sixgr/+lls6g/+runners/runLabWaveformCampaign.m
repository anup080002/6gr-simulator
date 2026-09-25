function out=runLabWaveformCampaign(scfg,outputDir,runTag)
%RUNLABWAVEFORMCAMPAIGN Native continuous clean TX + independent DMRS receivers.
% All PHY samples are executed here; Python only measures/packages retained data.
s=scfg.toStruct(); profiles=sixgr.phy.research.validateLabWaveform(s);
p=s.lab_waveform; frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
if strlength(string(runTag))==0, runTag=string(datetime('now','Format','yyyyMMdd_HHmmss')); end
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9_-]+$','once')), ...
    'sixgr:lab:RunTag','Use a simple nonempty run tag.');
root=fullfile(outputDir,'vxg_vsa',p.output_group,char(runTag));
assert(~isfolder(root),'sixgr:lab:AlreadyExists','Refusing to overwrite %s.',root);
folders=["config","meta","validation","reports/csv","reports/image", ...
    "dl_tx","ul_tx","dl_rx_awgn","ul_rx_awgn","keysight","vsa","webgui"];
for f=folders, mkdir(fullfile(root,f)); end
sixgr.util.jsonWrite(fullfile(root,'config','resolved_config.json'),s);
sixgr.lls6g.config.writeYAML(fullfile(root,'config','resolved_config.yaml'),s);
inputRoot=fullfile(root,'config','inputs'); mkdir(inputRoot);
for k=1:numel(scfg.SourceFiles)
    [~,name,ext]=fileparts(scfg.SourceFiles(k));
    copyfile(scfg.SourceFiles(k),fullfile(inputRoot,sprintf('%03d_%s%s',k,name,ext)));
end
[~,sha]=system('git rev-parse HEAD'); [~,dirty]=system('git status --porcelain');
meta=struct('Status',"running",'ScenarioID',scfg.ScenarioID,'Description',s.meta.description, ...
    'RunTag',string(runTag),'GitCommit',strtrim(string(sha)), ...
    'GitDirty',strlength(strtrim(string(dirty)))>0,'ConfigHash',scfg.ConfigHash, ...
    'StartedUTC',string(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX')), ...
    'MATLAB',version,'Toolboxes',ver,'Seed',s.simulation.random_seed, ...
    'ResearchClass',s.meta.research_class,'StandardNR',false, ...
    'DLTableAuthority',"nrPDSCHMCSTables.QAM1024Table / TS38.214 table5.1.3.1-4", ...
    'ULStandardsStatus',p.ul_standards_status,'RFUse',"center_frequency_metadata_only", ...
    'TimingSource',"preconfigured_lab_slot_boundary_not_acquired", ...
    'NoiseReference',s.research_link.noise_reference,'PowerUnits',"normalized_baseband_not_dBm", ...
    'PayloadAcceptance',"all_executed_TBs_CRC_and_bit_exact; no BLER qualification claim", ...
    'InstrumentCapability',"UNKNOWN",'InstrumentImportVerified',false, ...
    'BinaryFormat',"little_endian_interleaved_float64_IQ_per_port_or_layer", ...
    'NoiseSeedRule',"base_seed+100000*direction_index+1000*SNR_index; reset for each MCS", ...
    'TXSeedRule',"base_seed+100000*direction_index+absolute_slot", ...
    'Profiles',profiles,'SampleRateHz',frame.SampleRate_Hz,'FFTSize',frame.FFTSize, ...
    'ActiveSubcarriers',frame.NRB*12,'ActiveSpanHz',frame.NRB*12*frame.SCSkHz*1e3, ...
    'SNRdB',p.rx_snr_db,'WaveformExportReady',false,'WebDemoReady',false);
sourceNames=[string(mfilename('fullpath'))+".m", ...
    string(which('sixgr.phy.research.SharedChannelLink')), ...
    string(which('sixgr.phy.research.validateLabWaveform')), ...
    string(which('sixgr.phy.waveform.CanonicalOFDMModulator'))];
sourceRoot=fullfile(root,'meta','executed_sources'); mkdir(sourceRoot);
for k=1:numel(sourceNames)
    [~,name,ext]=fileparts(sourceNames(k)); copyfile(sourceNames(k),fullfile(sourceRoot,name+ext));
    meta.ExecutedSources(k)=struct('Path',sourceNames(k),'SHA256',sixgr.util.sha256File(sourceNames(k)));
end
sixgr.util.jsonWrite(fullfile(root,'meta','manifest.json'),meta);
sixgr.util.jsonWrite(fullfile(root,'validation','schema.json'),struct('Passed',true));
fprintf('LAB_RUN_FOLDER=%s\n',root);
trials=struct([]); timeline=struct([]); layerRows=struct([]); bins=struct([]);
try
for ip=1:numel(profiles)
    cfg=s; cfg.research_dl.target_code_rate=profiles(ip).TargetCodeRate;
    profile=sprintf('mcs%d',profiles(ip).MCS);
    sixgr.util.jsonWrite(fullfile(root,'config',profile+"_runtime.json"),cfg);
    noiseStreams=cell(2,numel(p.rx_snr_db));
    for di=1:2
        for si=1:numel(p.rx_snr_db)
            noiseStreams{di,si}=RandStream('mt19937ar','Seed', ...
                s.simulation.random_seed+100000*di+1000*si);
        end
    end
    cursor=0; symbolCursor=[0 0]; first=[true true];
    for slot=0:s.simulation.n_slots-1
        carrier=nrCarrierConfig('NSizeGrid',frame.NRB,'SubcarrierSpacing',frame.SCSkHz, ...
            'CyclicPrefix',char(frame.CyclicPrefix),'NSlot',mod(slot,frame.SlotsPerFrame), ...
            'NFrame',mod(floor(slot/frame.SlotsPerFrame),1024));
        [silent,ofdm]=sixgr.phy.waveform.ofdmModulate(carrier,nrResourceGrid(carrier,s.mimo.n_tx_ant), ...
            'Nfft',frame.FFTSize,'SampleRate',frame.SampleRate_Hz,'Windowing',s.waveform.windowing_samples);
        count=size(silent,1); active=[frame.IsDLAllocation(slot,s.research_dl.symbol_allocation), ...
            frame.IsULAllocation(slot,s.research_ul.symbol_allocation)];
        assert(~all(active),'sixgr:lab:TDDOverlap','DL/UL full-slot allocations overlap.');
        tick=struct('Profile',string(profile),'AbsoluteSlot',slot,'StartSample',cursor, ...
            'StopSampleExclusive',cursor+count,'DLActive',active(1),'ULActive',active(2));
        if isempty(timeline), timeline=tick; else, timeline(end+1)=tick; end %#ok<AGROW>
        for di=1:2
            dirs=["DL","UL"]; direction=dirs(di); lowerDir=lower(direction);
            ch=cfg.("research_"+lowerDir); clean=silent;
            folder=fullfile(root,lowerDir+"_tx",profile); if ~isfolder(folder), mkdir(folder); end
            if active(di)
                a=sixgr.phy.research.SharedChannelLink.allocation(cfg,slot,direction);
                ts=RandStream('mt19937ar','Seed',s.simulation.random_seed+100000*di+slot);
                tb=int8(randi(ts,[0 1],a.TransportBlockSize,1));
                tx=sixgr.phy.research.SharedChannelLink.transmit(cfg,slot,tb,direction);
                clean=tx.Waveform;
                assert(size(clean,1)==count && size(clean,2)==ch.num_layers && ...
                    tx.OFDM.SampleRate==frame.SampleRate_Hz && tx.OFDM.Nfft==frame.FFTSize, ...
                    'sixgr:lab:NativeClock','Generated waveform differs from the configured native clock.');
                for layer=1:a.NumLayers
                    localAppendIQ(fullfile(folder,sprintf('reference_layer%d.symbols64',layer)),tx.LayerSymbols(:,layer));
                end
                if first(di)
                    localGridCSV(fullfile(folder,'resource_grid.csv'),a,tx.Grid,slot);
                    sixgr.util.matSave(fullfile(folder,'first_slot_grid.mat'), ...
                        struct('Grid',tx.Grid,'DataIndices',a.DataIndices,'DMRSIndices',a.DMRSIndices, ...
                        'DMRSSymbols',a.DMRSSymbols,'Precoder',a.Precoder,'AbsoluteSlot',slot),UseArtifactStore=false);
                    first(di)=false;
                end
            end
            for port=1:size(clean,2)
                localAppendIQ(fullfile(folder,sprintf('port%d.iq64',port)),clean(:,port));
            end
            for si=1:numel(p.rx_snr_db)
                snr=p.rx_snr_db(si); nvGrid=(1/ch.num_layers)/10^(snr/10);
                nvSample=nvGrid/ofdm.SampleToGridNoiseVarianceGain;
                ns=noiseStreams{di,si}; noise=sqrt(nvSample/2)*(randn(ns,size(clean))+1j*randn(ns,size(clean)));
                noisy=clean+noise;
                rxFolder=fullfile(root,lowerDir+"_rx_awgn",profile,sprintf('snr%g',snr));
                if ~isfolder(rxFolder), mkdir(rxFolder); end
                for port=1:size(noisy,2)
                    localAppendIQ(fullfile(rxFolder,sprintf('port%d.iq64',port)),noisy(:,port));
                end
                if ~active(di), continue; end
                rx=sixgr.phy.research.SharedChannelLink.receive(cfg,slot,noisy,direction);
                errors=rx.EqualizedSymbols-tx.LayerSymbols;
                refEnergy=sum(abs(tx.LayerSymbols).^2,'all'); errEnergy=sum(abs(errors).^2,'all');
                noiseGrid=rx.Grid-tx.Grid;
                physicalSNR=10*log10(sum(abs(tx.Grid(a.DataIndices)).^2,'all')/sum(abs(noiseGrid(a.DataIndices)).^2,'all'));
                bitErrors=nnz(rx.TransportBlock~=tb);
                dmrsRE=numel(unique(mod(double(a.DMRSIndices(:))-1,frame.NRB*12*frame.SymbolsPerSlot)));
                row=struct('Profile',string(profile),'Direction',direction,'SNRdB',snr, ...
                    'AbsoluteSlot',slot,'StartSample',cursor,'SampleCount',count, ...
                    'TBID',profile+"_"+direction+"_"+slot,'DLMCS',profiles(ip).MCS, ...
                    'ULMCSApplicable',false,'Layers',a.NumLayers,'Qm',a.Qm, ...
                    'TargetCodeRate',a.TargetCodeRate,'TBSBits',a.TransportBlockSize,'CodedBits',a.G, ...
                    'EffectiveInformationCodeRate',a.TransportBlockSize/a.G, ...
                    'LayerDataRE',a.LayerDataRE,'UniqueDMRSRE',dmrsRE,'NREPerPRB',a.NREPerPRB, ...
                    'SymbolStart',symbolCursor(di),'CRCPass',logical(rx.CRCPass),'TBExact',bitErrors==0, ...
                    'BitErrors',bitErrors,'BER',bitErrors/a.TransportBlockSize, ...
                    'EVMRMSPercent',100*sqrt(errEnergy/refEnergy), ...
                    'EVMPeakPercent',100*sqrt(max(abs(errors).^2,[],'all')/mean(abs(tx.LayerSymbols).^2,'all')), ...
                    'ErrorEnergy',errEnergy,'ReferenceEnergy',refEnergy, ...
                    'ReferenceErrorSINRdB',10*log10(refEnergy/errEnergy), ...
                    'MeasuredDataREChannelSNRdB',physicalSNR, ...
                    'GridNoiseVariance',nvGrid,'SampleNoiseVariance',nvSample, ...
                    'DMRSNoiseVariance',rx.NoiseVariance,'LDPCBaseGraph',double(a.CodingLayout.BaseGraph), ...
                    'DecoderMaxIterationsUsed',max(rx.Iterations(:)), ...
                    'ChannelEstimateSource',rx.ChannelEstimateSource,'Source',"actual_coded_waveform");
                if isempty(trials), trials=row; else, trials(end+1)=row; end %#ok<AGROW>
                for layer=1:a.NumLayers
                    localAppendIQ(fullfile(rxFolder,sprintf('equalized_layer%d.symbols64',layer)),rx.EqualizedSymbols(:,layer));
                    localAppendIQ(fullfile(rxFolder,sprintf('error_layer%d.symbols64',layer)),errors(:,layer));
                    lr=row; lr.Layer=layer;
                    lr.ErrorEnergy=sum(abs(errors(:,layer)).^2); lr.ReferenceEnergy=sum(abs(tx.LayerSymbols(:,layer)).^2);
                    lr.EVMRMSPercent=100*sqrt(lr.ErrorEnergy/lr.ReferenceEnergy);
                    if isempty(layerRows), layerRows=lr; else, layerRows(end+1)=lr; end %#ok<AGROW>
                    linear=double(a.DataIndices(:,layer))-1;
                    sc=mod(linear,frame.NRB*12); symbol=mod(floor(linear/(frame.NRB*12)),frame.SymbolsPerSlot);
                    prb=floor(sc/12);
                    for kind=["symbol","prb"]
                        if kind=="symbol", groups=symbol; else, groups=prb; end
                        for group=unique(groups)'
                            mask=groups==group;
                            b=struct('Profile',string(profile),'Direction',direction,'SNRdB',snr, ...
                                'AbsoluteSlot',slot,'Layer',layer,'Kind',kind,'Index',group, ...
                                'Count',nnz(mask),'ErrorEnergy',sum(abs(errors(mask,layer)).^2), ...
                                'ReferenceEnergy',sum(abs(tx.LayerSymbols(mask,layer)).^2));
                            if isempty(bins), bins=b; else, bins(end+1)=b; end %#ok<AGROW>
                        end
                    end
                end
                fprintf('LAB profile=%s slot=%d %s SNR=%g CRC=%d exact=%d EVM=%.4f%%\n', ...
                    profile,slot,direction,snr,rx.CRCPass,bitErrors==0,row.EVMRMSPercent);
                clear rx
            end
            if active(di), symbolCursor(di)=symbolCursor(di)+a.LayerDataRE; clear tx; end
        end
        cursor=cursor+count;
        sixgr.util.csvWriteTable(fullfile(root,'reports','csv','trials.csv'),struct2table(trials),'PreserveSchema',true,'RoundTripNumericText',true);
        sixgr.util.csvWriteTable(fullfile(root,'reports','csv','timeline.csv'),struct2table(timeline),'PreserveSchema',true);
    end
    assert(cursor==round(frame.SampleRate_Hz*p.expected_duration_s) && ...
        cursor>=p.min_playback_samples && mod(cursor,p.playback_sample_multiple)==0, ...
        'sixgr:lab:FrameLength','Actual native frame length failed duration/playback constraints.');
    meta.SamplesPerPort=cursor;
    sixgr.util.csvWriteTable(fullfile(root,'reports','csv','layer_measurements.csv'),struct2table(layerRows),'PreserveSchema',true,'RoundTripNumericText',true);
    sixgr.util.csvWriteTable(fullfile(root,'reports','csv','evm_bins.csv'),struct2table(bins),'PreserveSchema',true,'RoundTripNumericText',true);
end
meta.Status="phy_completed"; meta.PayloadPass=all([trials.CRCPass] & [trials.TBExact]);
meta.CompletedUTC=string(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
sixgr.util.jsonWrite(fullfile(root,'meta','manifest.json'),meta);
out=struct('Ok',false,'PHYCompleted',true,'PayloadPass',meta.PayloadPass, ...
    'RunFolder',string(root),'PackagingRequired',true);
fprintf('LAB_PHY_COMPLETED payload_pass=%d; packaging and export validation still required.\n',meta.PayloadPass);
catch exception
    meta.Status="failed"; meta.ErrorIdentifier=string(exception.identifier); meta.Error=string(exception.message);
    sixgr.util.jsonWrite(fullfile(root,'meta','manifest.json'),meta);
    rethrow(exception);
end
end

function localAppendIQ(path,x)
assert(all(isfinite(x(:))),'sixgr:lab:NonfiniteIQ','Cannot export nonfinite samples.');
fid=fopen(path,'a','ieee-le'); assert(fid>=0,'sixgr:lab:OpenFailed','Cannot open %s.',path);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
assert(fwrite(fid,[real(x(:))';imag(x(:))'],'double')==2*numel(x), ...
    'sixgr:lab:ShortWrite','Incomplete IQ write.');
end

function localGridCSV(path,a,grid,slot)
shape=size(grid); kind=zeros(shape,'uint8'); kind(a.DataIndices)=1; kind(a.DMRSIndices)=2;
[sc,symbol,port]=ind2sub(shape,(1:numel(grid))');
t=table(repmat(slot,numel(grid),1),sc-1,symbol-1,port,kind(:), ...
    real(grid(:)),imag(grid(:)),'VariableNames', ...
    {'AbsoluteSlot','Subcarrier','Symbol','Port','Kind','I','Q'});
sixgr.util.csvWriteTable(path,t);
end
