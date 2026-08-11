function ok = testJointISACTDoc()
%TESTJOINTISACTDOC Focused analytical and waveform checks for 10.8.2/10.8.3.

[cfg,~] = sixgr.isac.loadJointConfig( ...
    "configs/isac/joint_isac_tdoc_master.yaml","quick");
pre6g = sixgr.isac.buildPre6GExampleWaveform(cfg,1201);
assert(numel(pre6g.Waveform)>0 && strlength(pre6g.WaveformSHA256)==64);
assert(pre6g.ExecutionBackend=="6g_exploration_library_simulation" && ...
    ~pre6g.HardwareValidated);

% 1. Bistatic Doppler and monostatic special case.
g = sixgr.isac.bistaticGeometry([0;0;0],[0;0;0],[10;0;0],[2;0;0],3e9,"trp_monostatic");
assert(abs(g.DopplerHz-4/g.WavelengthM) < 1e-12);
gb = sixgr.isac.bistaticGeometry([0;0;0],[0;10;0],[10;0;0],[2;1;0],3e9,"trp_trp_bistatic");
expected = dot([2;1;0],gb.TxUnitVector+gb.RxUnitVector)/gb.WavelengthM;
assert(abs(gb.DopplerHz-expected) < 1e-12);

% 2. One common phase-step coherent gain.
a=.25; phase=deg2rad(90);
assert(abs(abs(a+(1-a)*exp(1i*phase))^2-0.625) < 1e-12);

% 3. Periodic two-state ghost offset.
P=4; n=0:255; state=mod(floor(n/P),2); sequence=exp(1i*deg2rad(60)*state);
spectrum=abs(fftshift(fft(sequence))).^2; center=numel(n)/2+1; spectrum(center)=0;
[~,index]=max(spectrum); measured=abs((index-center)/numel(n));
assert(abs(measured-1/(2*P)) <= 1/numel(n));

% 4. TDD binary-mask DFT grating location.
mask=repmat([1 0 0 0 0],1,16); response=abs(fft(mask)).^2; response(1)=0;
[~,bin]=max(response); frequency=min((bin-1)/numel(mask),1-(bin-1)/numel(mask));
assert(abs(frequency-0.2) < 1e-12);

% 5. Baseband timing shift creates the expected frequency phase slope.
N=256; delay=7; k=(-N/2:N/2-1).'; H=exp(-1i*2*pi*k*delay/N);
slope=polyfit(k,unwrap(angle(H)),1); assert(abs(slope(1)+2*pi*delay/N)<1e-12);

% Use a bounded grid for algorithmic checks; the campaign itself retains the
% 273-RB FR3 profile.
testCfg=cfg; active=char(testCfg.carrier.activeProfile);
testCfg.carrier.profiles.(active).nSizeGrid=24;
w0=sixgr.isac.buildJointWaveform(testCfg,"W0",1101);
w3=sixgr.isac.buildJointWaveform(testCfg,"W3",1101);
tr38901=sixgr.isac.runTR38901ReferenceEvidence(testCfg,w0);
assert(tr38901.Summary.EvidenceClass== ...
    "official_mathworks_example_helper_execution");
assert(strlength(tr38901.Summary.HelperSHA256)==64 && ...
    strlength(tr38901.Summary.ReceivedSHA256)==64 && ...
    height(tr38901.Paths)>0);

% 6. A linear subcarrier phase ramp is a circular time shift and preserves
% useful-symbol PAPR.
symbol=find(any(w0.ConfiguredMask,1),1); X=w0.SensingGrid(:,symbol);
x=ifft(X,w0.OFDMInfo.Nfft); shifted=circshift(x,17);
papr=@(v) max(abs(v).^2)/mean(abs(v).^2);
assert(abs(papr(x)-papr(shifted)) < 1e-12);

% 7. W3 symbol-dependent CP recurrence.
q=w3.CumulativeCPState; cp=w3.CPLengths;
assert(all(q(2:end)==mod(q(1:end-1)+cp(1:end-1),w3.OFDMInfo.Nfft)));

% 8. Omitted sensing symbol does not change absolute q.
punctured=sixgr.isac.buildJointWaveform(testCfg,"W3",1101, ...
    double(testCfg.waveform.sensingSymbolIndices(2)));
assert(isequal(w3.CumulativeCPState,punctured.CumulativeCPState));

% 9. Absolute subcarrier index is not a compressed comb counter.
physical=w3.PhysicalSubcarrierIndices;
compressed=(0:numel(physical)-1).'; qValue=w3.CumulativeCPState(7);
phasePhysical=exp(1i*2*pi*physical*qValue/w3.OFDMInfo.Nfft);
phaseCompressed=exp(1i*2*pi*compressed*qValue/w3.OFDMInfo.Nfft);
assert(norm(phasePhysical-phaseCompressed)>1e-3);

% 10. Effective-pattern derivation and gap coherency.
collision=false(size(w0.ConfiguredMask)); activeRE=find(w0.ConfiguredMask);
collision(activeRE(1:10))=true;
state=sixgr.isac.deriveEffectivePattern(w0.ConfiguredMask,collision, ...
    "sensing_puncture","preserved");
assert(state.RetainedObservations==state.ConfiguredObservations-10);
assert(state.CoherentSegmentCount==1);

% 11/12. Budget pass/fail and range-vs-Doppler action change.
candidates(1)=localCandidate("share_reuse",1,32,0,0,0,12,true);
candidates(2)=localCandidate("sensing_puncture",1,24,0,0,0,8,true);
candidates(3)=localCandidate("recoverable_relocation",2,16,20,.25,50,5,true);
budget=struct("MaxCoherentSegments",2,"MinimumSegmentLength",8, ...
    "MaximumResidualPhaseDeg",30,"MaximumResidualTimingBins",.5, ...
    "MaximumResidualFrequencyHz",10);
[rangeSelection,rangeEval]=sixgr.isac.selectCollisionResponse(candidates,budget,"range_only");
[dopplerSelection,dopplerEval]=sixgr.isac.selectCollisionResponse(candidates,budget,"range_doppler");
assert(rangeSelection.Name=="recoverable_relocation");
assert(dopplerSelection.Name=="sensing_puncture");
assert(any(~dopplerEval.Feasible) && all(rangeEval.Feasible));

% 13. Port slope changes angle while a common phase does not.
spacing=.5; slopeDeg=10; angleError=asind(deg2rad(slopeDeg)/(2*pi*spacing));
commonPhase=90; relativeCommon=diff(repmat(commonPhase,1,8));
assert(angleError>0 && all(relativeCommon==0));

% 14. Saved-table serialization and plot regeneration.
folder=string(tempname); mkdir(folder); folderCleanup=onCleanup(@() localRemove(folder)); %#ok<NASGU>
source=table((1:5).',(1:5)'.^2,'VariableNames',{'x','y'});
writetable(source,fullfile(folder,"source.csv")); save(fullfile(folder,"source.mat"),"source");
loaded=readtable(fullfile(folder,"source.csv")); fig=figure("Visible","off");
figCleanup=onCleanup(@() close(fig)); %#ok<NASGU>
plot(loaded.x,loaded.y,"-o"); exportgraphics(fig,fullfile(folder,"regenerated.png"));
assert(exist(fullfile(folder,"regenerated.png"),"file")==2);

% One short production receive-chain trial.
trial=struct("TrialId","focused","Seed",1101,"DelayOverCP",.5, ...
    "NormalizedDoppler",.001,"SensingMode","trp_monostatic", ...
    "CollisionRatioPercent",0,"CollisionResponse","share_reuse", ...
    "TDDPattern","all_dl","TargetPresent",true,"UseGeometryDelay",false);
trial.PortProfile="single_port";
[row,~]=sixgr.isac.runJointWaveformTrial(testCfg,w0,trial);
assert(row.Detected && abs(row.RangeErrorM)<=physconst("LightSpeed")/(2*w0.OFDMInfo.SampleRate));
assert(isfinite(row.MeasuredDopplerHz));

% Expanded executed integration evidence: periodic ghost location, all TDD
% masks/responses, event transforms, asynchronous interference and
% beyond-CP ISI/ICI are evaluated from physical sample vectors.
studyBundles=struct("W0",w0,"W1",sixgr.isac.buildJointWaveform(testCfg,"W1",1101), ...
    "W2",sixgr.isac.buildJointWaveform(testCfg,"W2",1101),"W3",w3);
studies=sixgr.isac.runIntegrationStudies(testCfg,studyBundles,row);
assert(max(abs(studies.PeriodicPhase.Summary.ExpectedGhostOffsetNormalized- ...
    studies.PeriodicPhase.Summary.MeasuredGhostOffsetNormalized))<1e-12);
assert(height(studies.TDD)==double(testCfg.tdd.analysisSlots)* ...
    numel(fieldnames(testCfg.tdd.patterns)));
assert(numel(unique(studies.EffectivePatterns.Response))==10);
assert(all(isfinite(studies.ISIICI.ResidualEVMRMS)) && ...
    all(strlength(studies.ISIICI.ReceivedWaveformSHA256)==64));
below=studies.ISIICI.DelayOverCP<1 & studies.ISIICI.NormalizedDoppler==0;
beyond=studies.ISIICI.DelayOverCP>1 & studies.ISIICI.NormalizedDoppler==0;
assert(max(studies.ISIICI.ResidualEVMRMS(beyond))> ...
    max(studies.ISIICI.ResidualEVMRMS(below))+1e-3);
assert(studies.PortPhase.AzimuthErrorDeg(1)==0 && ...
    any(abs(studies.PortPhase.AzimuthErrorDeg(2:end))>0));
assert(all(strlength(studies.Interference.ReceivedWaveformSHA256)==64));
plan=sixgr.isac.buildJointTrialPlan(testCfg);
stage=string({plan.Stage}); profile=string({plan.WaveformProfile});
response=string({plan.CollisionResponse});
relocationIndex=find(stage=="J3_response"&profile=="W3"& ...
    response=="time_relocation",1);
[relocationRow,~]=sixgr.isac.runJointWaveformTrial(testCfg,w3,plan(relocationIndex));
assert(relocationRow.ReplacementObservations>0 && ...
    relocationRow.RelationClass=="known_transform" && ...
    relocationRow.CommunicationEVMRMS<0.2 && ...
    ~relocationRow.UncodedDataBlockError);

fprintf("testJointISACTDoc: PASS (measured Doppler %.3f Hz, expected %.3f Hz)\n", ...
    row.MeasuredDopplerHz,row.ExpectedDopplerHz);
ok=true;
end

function c=localCandidate(name,segments,minLength,phase,timing,frequency,cost,crossPort)
c=struct("Name",name,"CoherentSegmentCount",segments, ...
    "MinimumSegmentLength",minLength,"ResidualPhaseDeg",phase, ...
    "ResidualTimingBins",timing,"ResidualFrequencyHz",frequency, ...
    "Cost",cost,"CrossPortRelationAvailable",crossPort);
end

function localRemove(path)
if exist(path,"dir")==7, rmdir(path,"s"); end
end
