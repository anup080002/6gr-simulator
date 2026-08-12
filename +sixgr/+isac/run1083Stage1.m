function result = run1083Stage1(configPath,options)
%RUN1083STAGE1 Execute mandatory physical sanity gates for AI 10.8.3.
%
% This runner uses the production NR carrier, OFDM modulator/demodulator,
% W0-W3 builder, linear delay operator and sensing receiver. It does not
% create comparative/publication claims when a physical gate fails.

arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
[cfg,sourcePath]=sixgr.isac.loadJointConfig(configPath);
if strlength(options.RunId)==0
    runId="isac_10_8_3_validation_"+string(datetime("now", ...
        "Format","yyyyMMdd_HHmmss"));
else
    runId=options.RunId;
end
if strlength(options.OutputRoot)==0
    runFolder=fullfile(localRepoRoot(),"results",runId);
else
    runFolder=fullfile(options.OutputRoot,runId);
end
runFolder=string(runFolder); localLayout(runFolder);
diaryPath=fullfile(runFolder,"logs","stage1_console.log");
diary(char(diaryPath)); diaryCleanup=onCleanup(@() diary('off')); %#ok<NASGU>
fprintf("10.8.3 Stage-1 physical validation: %s\n",runFolder);

[carrier,~,ofdmInfo]=sixgr.isac.carrierConfig(cfg);
cpSafe=localCPSafe(cfg,carrier,ofdmInfo);
longDelay=localLongDelay(cfg,carrier,ofdmInfo);
offGrid=localOffGrid(cfg,ofdmInfo);
[punctureState,punctureReceiver]=localPuncture(cfg);
coherence=localCoherence(cfg);

gate=table(["CP_SAFE_INTEGER";"CP_SAFE_FRACTIONAL";"LINEAR_CP_TRANSITION"; ...
    "OFF_GRID_ESTIMATOR";"W3_ABSOLUTE_PUNCTURE_INVARIANCE"],false(5,1), ...
    strings(5,1),'VariableNames',{'Gate','Pass','Details'});
integerRows=cpSafe.IsIntegerDelay;
fractionRows=~integerRows;
integerTolerance=double(cfg.validation.stage1.cpSafe.integerEVMTolerance);
fractionTolerance=double(cfg.validation.stage1.cpSafe.fractionalEVMTolerance);
gate.Pass(1)=all(cpSafe.EVMRMS(integerRows)<integerTolerance);
gate.Details(1)=sprintf("max_evm=%.4g tolerance=%.4g", ...
    max(cpSafe.EVMRMS(integerRows)),integerTolerance);
gate.Pass(2)=all(cpSafe.EVMRMS(fractionRows)<fractionTolerance);
gate.Details(2)=sprintf("max_evm=%.4g tolerance=%.4g", ...
    max(cpSafe.EVMRMS(fractionRows)),fractionTolerance);
below=longDelay.DelayOverCP<1; above=longDelay.DelayOverCP>1;
gate.Pass(3)=max(longDelay.ResidualEVMRMS(below))<fractionTolerance && ...
    max(longDelay.PreviousSymbolISIPowerRatio(above))> ...
    max(longDelay.PreviousSymbolISIPowerRatio(below))+1e-8 && ...
    max(longDelay.OffDiagonalICIPowerRatio(above))> ...
    max(longDelay.OffDiagonalICIPowerRatio(below))+1e-8;
gate.Details(3)=sprintf("below_cp_evm=%.4g above_cp_isi=%.4g above_cp_ici=%.4g", ...
    max(longDelay.ResidualEVMRMS(below)), ...
    max(longDelay.PreviousSymbolISIPowerRatio(above)), ...
    max(longDelay.OffDiagonalICIPowerRatio(above)));
gate.Pass(4)=all(isfinite(offGrid.RangeErrorBins)) && ...
    all(isfinite(offGrid.DopplerErrorHz)) && ...
    all(abs(offGrid.RangeErrorBins)<=double(cfg.validation.stage1.offGrid.maximumRangeErrorBins)) && ...
    all(abs(offGrid.DopplerErrorHz)<=double(cfg.validation.stage1.offGrid.maximumDopplerErrorHz)) && ...
    all(abs(offGrid.SubBinPeakOffset)>1e-6);
gate.Details(4)=sprintf("rows=%d max_range_error_bins=%.4g max_doppler_error_hz=%.4g", ...
    height(offGrid),max(abs(offGrid.RangeErrorBins)),max(abs(offGrid.DopplerErrorHz)));
post=punctureState.AfterFirstPuncture;
gate.Pass(5)=all(punctureState.DeltaQ(~post)==0) && any(punctureState.DeltaQ(post)~=0) && ...
    punctureReceiver.ReferenceCoherentGain(1)>punctureReceiver.ReferenceCoherentGain(2);
gate.Details(5)=sprintf("max_delta_q=%g correct_gain=%.4g wrong_gain=%.4g", ...
    max(abs(punctureState.DeltaQ)),punctureReceiver.ReferenceCoherentGain(1), ...
    punctureReceiver.ReferenceCoherentGain(2));
gate.ResultClass=repmat("PASS — physical/unit sanity",height(gate),1);
gate.ResultClass(~gate.Pass)="FAIL — implementation issue";

localSaveTable(runFolder,"cp_safe_w0_validation",cpSafe);
localSaveTable(runFolder,"linear_convolution_validation",longDelay);
localSaveTable(runFolder,"off_grid_estimator_validation",offGrid);
localSaveTable(runFolder,"w3_absolute_counter_validation",punctureState);
localSaveTable(runFolder,"w3_puncture_receiver_effect",punctureReceiver);
localSaveTable(runFolder,"cross_symbol_coherence",coherence);
localSaveTable(runFolder,"stage1_gate_summary",gate);
localFigure17(runFolder,cfg,longDelay);
localFigure18(runFolder,cfg,punctureState,punctureReceiver);
localFigure19(runFolder,cfg,coherence);

copyfile(sourcePath,fullfile(runFolder,"config_source.yaml"));
save(fullfile(runFolder,"config_snapshot.mat"),"cfg");
localWriteText(fullfile(runFolder,"config_snapshot.json"),jsonencode(cfg,"PrettyPrint",true));
copyfile(fullfile(localRepoRoot(),"docs","10_8_3_simulation_audit.md"), ...
    fullfile(runFolder,"audit","10_8_3_simulation_audit.md"));
[~,commit]=system("git rev-parse HEAD"); [~,status]=system("git status --porcelain");
localWriteText(fullfile(runFolder,"git_commit.txt"),strtrim(commit));
manifest=struct("SchemaVersion","sixgr.isac.10_8_3.stage1.v1", ...
    "RunFolder",char(runFolder),"ConfigSource",char(sourcePath), ...
    "ConfigSHA256",cfg.provenance.SourceSHA256,"GitCommit",strtrim(commit), ...
    "GitWorktreeDirty",strlength(strtrim(string(status)))>0, ...
    "MATLABRelease",version("-release"),"ActiveRunMode",char(cfg.run.activeMode), ...
    "AllStage1GatesPassed",all(gate.Pass), ...
    "GeneratedUTC",char(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss'Z'")));
localWriteText(fullfile(runFolder,"run_manifest.json"),jsonencode(manifest,"PrettyPrint",true));
localStage1Report(runFolder,cfg,gate,cpSafe,longDelay,offGrid,punctureReceiver);
result=struct("RunFolder",runFolder,"GateTable",gate,"Passed",all(gate.Pass), ...
    "CPSafe",cpSafe,"LinearConvolution",longDelay,"OffGrid",offGrid, ...
    "PunctureState",punctureState,"PunctureReceiver",punctureReceiver, ...
    "Coherence",coherence);
if ~result.Passed
    failed=join(gate.Gate(~gate.Pass),", ");
    error("sixgr:isac:Stage1PhysicalGateFailed", ...
        "10.8.3 Stage-1 stopped on failed physical gate(s): %s. Evidence: %s", ...
        failed,runFolder);
end
fprintf("10.8.3 Stage-1 PASS: %d/%d gates, evidence %s\n", ...
    nnz(gate.Pass),height(gate),runFolder);
end

function out=localCPSafe(cfg,carrier,ofdmInfo)
nSC=carrier.NSizeGrid*12; nSymbols=carrier.SymbolsPerSlot;
rng(double(cfg.validation.stage1.seed),"twister");
bits=randi([0 1],2*nSC*nSymbols,1);
grid=reshape(nrSymbolModulate(bits,"QPSK"),nSC,nSymbols);
waveform=nrOFDMModulate(carrier,grid,"Windowing",0);
cp=double(ofdmInfo.CyclicPrefixLengths(1:nSymbols)); cp=cp(:); cpReference=min(cp);
ratios=double(cfg.validation.stage1.cpSafe.delayOverCP(:));
k=(-floor(nSC/2):ceil(nSC/2)-1).'+12*double(carrier.NStartGrid);
parts=cell(numel(ratios),1);
for i=1:numel(ratios)
    delay=ratios(i)*cpReference;
    received=sixgr.isac.applyLinearDelay(waveform,delay);
    rxGrid=nrOFDMDemodulate(carrier,received,"CyclicPrefixFraction", ...
        double(cfg.receiver.ofdmCyclicPrefixFraction));
    H=exp(-1i*2*pi*k*delay/double(ofdmInfo.Nfft));
    validSymbols=find(cp>=ceil(delay)); validSymbols(validSymbols==1)=[];
    equalized=rxGrid(:,validSymbols)./H;
    evm=sqrt(sum(abs(equalized-grid(:,validSymbols)).^2,"all")/ ...
        sum(abs(grid(:,validSymbols)).^2,"all"));
    isInteger=abs(delay-round(delay))<1e-12;
    tolerance=double(cfg.validation.stage1.cpSafe.fractionalEVMTolerance);
    if isInteger, tolerance=double(cfg.validation.stage1.cpSafe.integerEVMTolerance); end
    parts{i}=table(ratios(i),delay,isInteger,numel(validSymbols),evm,tolerance,evm<tolerance, ...
        "production_nr_ofdm_linear_delay_perfect_diagonal_equalization", ...
        'VariableNames',{'DelayOverCP','DelaySamples','IsIntegerDelay','EvaluatedSymbols', ...
        'EVMRMS','Tolerance','Pass','EvidenceClass'});
end
out=vertcat(parts{:});
end

function out=localLongDelay(cfg,carrier,ofdmInfo)
nSC=carrier.NSizeGrid*12; nSymbols=carrier.SymbolsPerSlot; currentSymbol=4; previousSymbol=3;
rng(double(cfg.validation.stage1.seed)+1,"twister");
previous=nrSymbolModulate(randi([0 1],2*nSC,1),"QPSK");
current=nrSymbolModulate(randi([0 1],2*nSC,1),"QPSK");
gridPrevious=complex(zeros(nSC,nSymbols)); gridPrevious(:,previousSymbol)=previous;
gridCurrent=complex(zeros(nSC,nSymbols)); gridCurrent(:,currentSymbol)=current;
wavePrevious=nrOFDMModulate(carrier,gridPrevious,"Windowing",0);
waveCurrent=nrOFDMModulate(carrier,gridCurrent,"Windowing",0);
cp=double(ofdmInfo.CyclicPrefixLengths(currentSymbol));
k=(-floor(nSC/2):ceil(nSC/2)-1).'+12*double(carrier.NStartGrid);
ratios=double(cfg.validation.stage1.linearConvolution.delayOverCP(:));
parts=cell(numel(ratios),1);
for i=1:numel(ratios)
    delay=ratios(i)*cp;
    rxPrevious=nrOFDMDemodulate(carrier,sixgr.isac.applyLinearDelay(wavePrevious,delay), ...
        "CyclicPrefixFraction",double(cfg.receiver.ofdmCyclicPrefixFraction));
    rxCurrent=nrOFDMDemodulate(carrier,sixgr.isac.applyLinearDelay(waveCurrent,delay), ...
        "CyclicPrefixFraction",double(cfg.receiver.ofdmCyclicPrefixFraction));
    rxTotal=rxPrevious+rxCurrent;
    H=exp(-1i*2*pi*k*delay/double(ofdmInfo.Nfft)); expected=current.*H;
    normalization=sum(abs(current).^2);
    isi=sum(abs(rxPrevious(:,currentSymbol)).^2)/normalization;
    ici=sum(abs(rxCurrent(:,currentSymbol)-expected).^2)/normalization;
    equalized=rxTotal(:,currentSymbol)./H;
    evm=sqrt(sum(abs(equalized-current).^2)/normalization);
    parts{i}=table(ratios(i),delay,isi,ici,evm, ...
        string(sixgr.util.sha256Hex(typecast([real(rxTotal(:));imag(rxTotal(:))],"uint8"))), ...
        "true_time_domain_linear_convolution_two_distinct_symbols", ...
        'VariableNames',{'DelayOverCP','DelaySamples','PreviousSymbolISIPowerRatio', ...
        'OffDiagonalICIPowerRatio','ResidualEVMRMS','ReceivedGridSHA256','EvidenceClass'});
end
out=vertcat(parts{:});
end

function out=localOffGrid(cfg,ofdmInfo)
fractionsDelay=double(cfg.validation.stage1.offGrid.delayFractions(:));
fractionsDoppler=double(cfg.validation.stage1.offGrid.dopplerFractions(:));
profiles=["W0";"W0";"W2";"W3"];
receivers=["B0";"B1";"B2";"C0"];
cp=min(double(ofdmInfo.CyclicPrefixLengths)); parts=cell(0,1); index=0;
for p=1:numel(profiles)
    bundle=sixgr.isac.buildJointWaveform(cfg,profiles(p), ...
        double(cfg.validation.stage1.seed)+20,zeros(0,1),14, ...
        localVariant(profiles(p)));
    symbolStarts=[0;cumsum(double(bundle.CPLengths(:))+double(bundle.OFDMInfo.Nfft))];
    times=(symbolStarts(1:end-1)+double(bundle.CPLengths(:)))/double(bundle.OFDMInfo.SampleRate);
    dopplerBin=1/(times(end)-times(1));
    for f=1:numel(fractionsDelay)
        index=index+1; trial=localTrial("offgrid_"+profiles(p)+"_"+f, ...
            double(cfg.validation.stage1.seed)+100+p*10+f,receivers(p));
        trial.ExactDelaySamples=double(cfg.validation.stage1.offGrid.baseDelayBins)+fractionsDelay(f);
        trial.DelayOverCP=trial.ExactDelaySamples/cp;
        trial.ExactDopplerHz=(double(cfg.validation.stage1.offGrid.baseDopplerBins)+ ...
            fractionsDoppler(f))*dopplerBin;
        trial.NormalizedDoppler=trial.ExactDopplerHz/(bundle.Carrier.SubcarrierSpacing*1e3);
        [row,~]=sixgr.isac.runJointWaveformTrial(cfg,bundle,trial);
        parts{index}=table(profiles(p),receivers(p),fractionsDelay(f),fractionsDoppler(f), ...
            trial.ExactDelaySamples,row.MeasuredRangeM/(physconst("LightSpeed")/ ...
            (2*bundle.OFDMInfo.SampleRate)), ...
            row.MeasuredRangeM/(physconst("LightSpeed")/(2*bundle.OFDMInfo.SampleRate))- ...
            trial.ExactDelaySamples,trial.ExactDopplerHz,row.MeasuredDopplerHz, ...
            row.DopplerErrorHz,row.Detected,row.WrongPeak,row.SubBinPeakOffset, ...
            "same_runtime_receiver_without_target_oracle", ...
            'VariableNames',{'WaveformProfile','ReceiverProfile','DelayFractionBin', ...
            'DopplerFractionBin','ExpectedDelaySamples','EstimatedDelaySamples', ...
            'RangeErrorBins','ExpectedDopplerHz','EstimatedDopplerHz','DopplerErrorHz', ...
            'Detected','WrongPeak','SubBinPeakOffset','EvidenceClass'});
    end
end
out=vertcat(parts{:});
end

function [stateTable,receiverTable]=localPuncture(cfg)
bundle=sixgr.isac.buildJointWaveform(cfg,"W3",double(cfg.validation.stage1.seed)+30, ...
    zeros(0,1),14,"default");
trial=localTrial("w3_puncture_correct",double(cfg.validation.stage1.seed)+31,"C0");
trial.CollisionRatioPercent=double(cfg.validation.stage1.puncture.ratioPercent);
trial.CollisionResponse="sensing_puncture"; trial.CollisionMaskProfile="contiguous_time";
trial.DelayOverCP=.5; trial.NormalizedDoppler=.01;
trial.ReceiverW3StateRule="absolute_physical_symbol";
[correct,raw]=sixgr.isac.runJointWaveformTrial(cfg,bundle,trial);
trial.TrialId="w3_puncture_wrong"; trial.ReceiverW3StateRule="transmitted_sensing_counter";
[wrong,~]=sixgr.isac.runJointWaveformTrial(cfg,bundle,trial);
mask=raw.PatternState.EffectiveMask; cp=double(bundle.CPLengths(:)); nFFT=double(bundle.OFDMInfo.Nfft);
qAbs=bundle.CumulativeCPState(:); qWrong=zeros(size(qAbs)); accumulator=0;
for symbol=1:numel(qWrong)
    if any(mask(:,symbol)), accumulator=mod(accumulator+cp(symbol),nFFT); end
    qWrong(symbol)=accumulator;
end
active=any(mask,1).'; firstMissing=find(~active,1); after=false(size(qAbs));
    if ~isempty(firstMissing), after(firstMissing:end)=true; end
delta=qWrong-qAbs; representativeK=max(abs(bundle.PhysicalSubcarrierIndices));
phase=angle(exp(1i*2*pi*representativeK*delta/nFFT));
stateTable=table((0:numel(qAbs)-1).',cp,active,qAbs,qWrong,delta,phase,after, ...
    'VariableNames',{'AbsoluteSymbolIndex','CPLengthSamples','SensingOccasionTransmitted', ...
    'QAbsolute','QTransmittedCounter','DeltaQ','ResidualPhaseRadAtEdgeSubcarrier', ...
    'AfterFirstPuncture'});
receiverTable=[correct;wrong];
end

function out=localCoherence(cfg)
profiles=["W1-A";"W1-B";"W2";"W3"]; waveform=["W1";"W1";"W2";"W3"];
variant=["per_occasion";"reset_aligned_interval";"default";"default"];
parts=cell(0,1); index=0;
for p=1:numel(profiles)
    bundle=sixgr.isac.buildJointWaveform(cfg,waveform(p), ...
        double(cfg.validation.stage1.seed)+40,zeros(0,1),14,variant(p));
    symbols=find(any(bundle.ConfiguredMask,1));
    for s=2:numel(symbols)
        previous=symbols(s-1); current=symbols(s);
        a=bundle.SensingGrid(bundle.ConfiguredMask(:,previous),previous);
        b=bundle.SensingGrid(bundle.ConfiguredMask(:,current),current);
        rawRho=abs(a'*b)/(norm(a)*norm(b));
        % Exact sequence and W3-state removal is equally available to all
        % declared receivers; the residual channel observations are z_l.
        zA=a.*conj(a)./max(abs(a).^2,realmin);
        zB=b.*conj(b)./max(abs(b).^2,realmin);
        residualRho=abs(zA'*zB)/(norm(zA)*norm(zB));
        residualPhase=angle(zA'*zB);
        boundary="inside_continuity_interval";
        if profiles(p)=="W1-A"
            boundary="reset_boundary";
        elseif profiles(p)=="W1-B" && mod(s-1,double(cfg.waveform.w1ResetAlignedIntervalOccasions))==0
            boundary="reset_boundary";
        end
        index=index+1;
        parts{index}=table(profiles(p),previous-1,current-1,boundary,rawRho, ...
            residualRho,residualPhase, ...
            "known_rs_and_w3_relation_removed_before_channel_coherence", ...
            'VariableNames',{'Profile','PreviousAbsoluteSymbol','CurrentAbsoluteSymbol', ...
            'BoundaryClass','RawRSCoherence','ResidualCoherenceMagnitude', ...
            'ResidualCommonPhaseRad','EvidenceClass'});
    end
end
out=vertcat(parts{:});
end

function trial=localTrial(id,seed,receiver)
trial=struct("TrialId",char(id),"Seed",double(seed),"WaveformSeed",double(seed), ...
    "DelayOverCP",.5,"NormalizedDoppler",0,"SensingMode","trp_monostatic", ...
    "CollisionRatioPercent",0,"CollisionResponse","share_reuse", ...
    "TDDPattern","all_dl","TargetPresent",true,"UseGeometryDelay",false, ...
    "PortProfile","single_port","ReceiverProfile",char(receiver), ...
    "CoherentSymbols",14,"CollisionMaskProfile","random_isolated", ...
    "SequenceVariant","default");
end

function value=localVariant(profile)
if profile=="W1", value="per_occasion"; else, value="default"; end
end

function localFigure17(runFolder,cfg,t)
fig=localNewFigure(cfg); c=onCleanup(@() close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
nexttile(layout); semilogy(t.DelayOverCP,max(t.PreviousSymbolISIPowerRatio,realmin),"-o");
xline(1,"--","CP boundary"); xlabel("Delay / CP"); ylabel("Previous-symbol ISI power ratio"); grid on;
nexttile(layout); semilogy(t.DelayOverCP,max(t.OffDiagonalICIPowerRatio,realmin),"-o");
xline(1,"--"); xlabel("Delay / CP"); ylabel("Off-diagonal ICI power ratio"); grid on;
nexttile(layout); semilogy(t.DelayOverCP,max(t.ResidualEVMRMS,realmin),"-o");
xline(1,"--"); xlabel("Delay / CP"); ylabel("Residual EVM RMS"); grid on;
title(layout,"True linear-convolution CP-boundary validation");
localExport(runFolder,cfg,fig,"WFig17_linear_convolution_validation",t);
end

function localFigure18(runFolder,cfg,t,r)
fig=localNewFigure(cfg); c=onCleanup(@() close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2,2,"TileSpacing","compact","Padding","compact");
nexttile(layout); plot(t.AbsoluteSymbolIndex,t.QAbsolute,"-o",t.AbsoluteSymbolIndex, ...
    t.QTransmittedCounter,"--s","LineWidth",1.4); xlabel("Absolute OFDM symbol"); ylabel("q(l) samples");
legend("q_{abs}","q_{txCount}","Location","best"); grid on;
nexttile(layout); stem(t.AbsoluteSymbolIndex,t.DeltaQ,"filled"); xlabel("Absolute OFDM symbol"); ylabel("Delta q"); grid on;
nexttile(layout); plot(t.AbsoluteSymbolIndex,rad2deg(t.ResidualPhaseRadAtEdgeSubcarrier),"-o");
xlabel("Absolute OFDM symbol"); ylabel("Residual phase (deg)"); grid on;
nexttile(layout); labels=categorical(r.ReceiverW3StateRule); yyaxis left;
bar(labels,r.ReferenceCoherentGain); ylabel("Coherent gain"); yyaxis right;
plot(labels,abs(r.DopplerErrorHz),"ko","LineWidth",1.5); ylabel("|Doppler error| (Hz)"); grid on;
title(layout,"W3 absolute-state puncture invariance and wrong-counter consequence");
localExport(runFolder,cfg,fig,"WFig18_absolute_vs_transmitted_counter",struct("State",t,"Receiver",r));
end

function localFigure19(runFolder,cfg,t)
fig=localNewFigure(cfg); c=onCleanup(@() close(fig)); %#ok<NASGU>
profiles=unique(t.Profile,"stable"); layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
nexttile(layout); hold on; nexttile(layout); hold on; nexttile(layout); hold on;
for i=1:numel(profiles)
    rows=t.Profile==profiles(i);
    nexttile(layout,1); plot(find(rows),t.RawRSCoherence(rows),"-o","DisplayName",profiles(i));
    nexttile(layout,2); plot(find(rows),t.ResidualCoherenceMagnitude(rows),"-o","DisplayName",profiles(i));
    nexttile(layout,3); plot(find(rows),rad2deg(t.ResidualCommonPhaseRad(rows)),"-o","DisplayName",profiles(i));
end
nexttile(layout,1); ylabel("Raw RS |rho|"); xlabel("Adjacent pair"); legend; grid on;
nexttile(layout,2); ylabel("Residual |rho|"); xlabel("Adjacent pair"); ylim([0 1.05]); grid on;
nexttile(layout,3); ylabel("Residual phase (deg)"); xlabel("Adjacent pair"); grid on;
title(layout,"Cross-symbol coherence after declared receiver knowledge removal");
localExport(runFolder,cfg,fig,"WFig19_cross_symbol_coherence",t);
end

function fig=localNewFigure(cfg)
pixels=double(cfg.output.imageSizePixels(:).'); dpi=double(cfg.output.imageResolutionDPI);
fig=figure("Visible","off","Color","white","Units","inches", ...
    "Position",[1 1 pixels(1)/dpi pixels(2)/dpi]);
end

function localExport(runFolder,cfg,fig,stem,data)
folder=fullfile(runFolder,"figures");
localPublicationStyle(fig);
save(fullfile(folder,stem+".mat"),"data");
if istable(data)
    writetable(data,fullfile(folder,stem+".csv"));
elseif isstruct(data)
    names=string(fieldnames(data)); paths=strings(numel(names),1); hashes=strings(numel(names),1);
    for i=1:numel(names)
        component=data.(names(i)); componentPath=fullfile(folder,stem+"_"+names(i)+".csv");
        if ~istable(component)
            error("sixgr:isac:InvalidFigureSourceComponent", ...
                "Composite figure component %s must be a table.",names(i));
        end
        writetable(component,componentPath); paths(i)=string(componentPath);
        hashes(i)=localFileHash(componentPath);
    end
    sourceManifest=table(names,paths,hashes,'VariableNames',{'Dataset','CSVPath','SHA256'});
    writetable(sourceManifest,fullfile(folder,stem+".csv"));
else
    error("sixgr:isac:InvalidFigureSource","Figure source must be a table or struct of tables.");
end
savefig(fig,fullfile(folder,stem+".fig"));
exportgraphics(fig,fullfile(folder,stem+".png"), ...
    "Resolution",double(cfg.output.imageResolutionDPI));
exportgraphics(fig,fullfile(folder,stem+".pdf"),"ContentType","vector");
end

function localPublicationStyle(fig)
axesHandles=findall(fig,"Type","axes");
for ax=reshape(axesHandles,1,[])
    set(ax,"Color","white","XColor",[.12 .12 .12],"YColor",[.12 .12 .12], ...
        "GridColor",[.68 .68 .68],"MinorGridColor",[.82 .82 .82], ...
        "GridAlpha",.35,"FontName","Arial","FontSize",9);
end
textHandles=findall(fig,"Type","text");
for h=reshape(textHandles,1,[]), set(h,"Color",[.08 .08 .08]); end
layoutHandles=findall(fig,"Type","tiledlayout");
for h=reshape(layoutHandles,1,[])
    h.Title.Color=[.08 .08 .08]; h.Title.FontWeight="bold";
end
legendHandles=findall(fig,"Type","legend");
for h=reshape(legendHandles,1,[])
    set(h,"Color","white","TextColor",[.08 .08 .08],"EdgeColor",[.55 .55 .55]);
end
end

function digest=localFileHash(path)
fid=fopen(path,"rb"); if fid<0, error("sixgr:isac:FileHashReadFailed","Cannot read %s.",path); end
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
digest=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function localSaveTable(runFolder,stem,t)
writetable(t,fullfile(runFolder,"tables",stem+".csv"));
save(fullfile(runFolder,"tables",stem+".mat"),"t");
end

function localLayout(runFolder)
for folder=["audit","logs","raw","aggregate","tables","figures","report"]
    path=fullfile(runFolder,folder); if exist(path,"dir")~=7, mkdir(path); end
end
end

function localStage1Report(runFolder,cfg,gate,cpSafe,longDelay,offGrid,puncture)
lines=["# 10.8.3 validation report — Stage 1";""; ...
    "This report contains mandatory physical sanity evidence only. Stages 2–5 are not claimed here.";""; ...
    "## Simulation configuration";""; ...
    "- Carrier: `"+string(cfg.carrier.activeProfile)+"`"; ...
    "- MATLAB: `"+string(version)+"`"; ...
    "- Paired deterministic seed: "+string(cfg.validation.stage1.seed);""; ...
    "## Gate summary";""];
for i=1:height(gate)
    lines(end+1)="- "+gate.Gate(i)+": **"+gate.ResultClass(i)+"** — "+gate.Details(i); %#ok<AGROW>
end
lines=[lines;"";"## CP-safe W0 validation";""; ...
    "Integer-delay EVM maximum: "+string(max(cpSafe.EVMRMS(cpSafe.IsIntegerDelay))); ...
    "Fractional-delay EVM maximum: "+string(max(cpSafe.EVMRMS(~cpSafe.IsIntegerDelay)));""; ...
    "## Linear-convolution long-delay validation";""; ...
    "The channel is a zero-extended time-domain delay. Previous-symbol ISI and off-diagonal error rise beyond CP; no per-symbol phase-only delay model is used.";""; ...
    "Rows: "+string(height(longDelay));"";"## Off-grid estimator";""; ...
    "All B0/B1/B2/C0 rows use the same parabolic sub-bin peak estimator and the same continuous slow-time phase fit. Configured target values are evaluation labels, not estimator inputs."; ...
    "Rows: "+string(height(offGrid));"";"## W3 puncture invariance";""; ...
    "Correct receiver coherent gain: "+string(puncture.ReferenceCoherentGain(1)); ...
    "Wrong transmitted-counter gain: "+string(puncture.ReferenceCoherentGain(2));""; ...
    "## Open issues";"";"Stages 2–5 must only run after every Stage-1 gate passes."];
localWriteText(fullfile(runFolder,"report","10_8_3_validation_report.md"),join(lines,newline));
end

function localWriteText(path,value)
fid=fopen(path,"w"); if fid<0, error("sixgr:isac:WriteFailed","Cannot write %s.",path); end
c=onCleanup(@() fclose(fid)); %#ok<NASGU> fprintf(fid,"%s",value);
end

function root=localRepoRoot()
here=fileparts(mfilename("fullpath")); root=fileparts(fileparts(here));
end
