function ok=testLinkEnergyRatioEvidence()
% Actual native coding/OFDM/energy/noise components plus declared negative
% fixtures. No shared receiver, scheduler, RF or conformance claim is made.
setup6GRSimToolkit('Verbose',false);
before=rng; cleanup=onCleanup(@()rng(before)); %#ok<NASGU>
rng(7374,'twister');
[qm,names]=sixgr.report.reportModulationOrder( ...
    ["BPSK","pi/2-BPSK","PI2-BPSK","QPSK","16QAM","64QAM","256QAM","1024QAM","4096QAM","unknown","QPSK|16QAM"]);
assert(isequaln(qm,[1 1 1 2 4 6 8 10 12 NaN NaN]) && all(names(1:3)=="BPSK"));
assert(isnan(sixgr.report.reportModulationOrder("8192QAM")), ...
    'Do not guess Qm for an uninstalled modulation or combined-codeword token.');

[tx,clean,noise,id]=nativeOperands();
originalTX=tx; originalNoise=noise; originalClean=clean;
oldState=rng;
[oldEnergy,oldReceipt]=sixgr.phy.waveform.measureReceivedOccupiedREEnergy(tx.Carrier,clean, ...
    tx.PDSCHIndices,'SignalFamily','PDSCH');
[newEnergy,compact]=sixgr.phy.waveform.measureReceivedOccupiedREEnergy(tx.Carrier,clean, ...
    tx.PDSCHIndices,'SignalFamily','PDSCH','RetainEnergyReceipt',true);
assert(isequal(oldEnergy,newEnergy) && isequal(oldState,rng) && ...
    ~isfield(oldReceipt,'EnergySumPerReceiveBranch') && numel(compact.EnergySumPerReceiveBranch)==size(clean,2));
for name=string(fieldnames(oldReceipt))'
    assert(isequaln(oldReceipt.(name),compact.(name)),'Optional receipt changed existing evidence.');
end
e=sixgr.link.captureLinkEnergyEvidence(tx,clean,noise,id,"normalized_complex_baseband",compact);
assert(e.Available && isequaln(tx,originalTX) && isequaln(noise,originalNoise) && isequaln(clean,originalClean));
assert(~isfield(e,'EnergyPerObservation') && ~isfield(e,'DataIndices') && ~isfield(e,'UniqueTimeFrequencyIndices'));
badMeasurement=compact; badMeasurement.ReferenceWaveformSHA256=repmat('0',1,64);
reject(@()sixgr.link.captureLinkEnergyEvidence(tx,clean,noise,id,"normalized_complex_baseband",badMeasurement), ...
    'sixgr:link:InvalidEnergyEvidence');
trial=ownerRow(tx,id);
bound=sixgr.link.bindLinkEnergyEvidence(trial,e);
assert(isequaln(bound,sixgr.link.bindLinkEnergyEvidence(bound,e)));
o=collect(bound); assert(o.RatioAvailable && ~o.CountsTowardCoverage);
energy=sum(e.EnergySumPerReceiveBranch)/size(clean,2);
assert(near(o.MeanRxBranchEcN0_dB,10*log10(energy/(tx.G*noise.GridNoiseVariance))) && ...
    near(o.MeanRxBranchEbN0_dB,10*log10(energy/(numel(tx.TransportBlock)*noise.GridNoiseVariance))));
assert(all(isnan([o.EsN0_dB,o.EcNo_dB,o.EbNo_dB])), ...
    'Branch-mean received support energy is not generic modulation Es/NR EcNo.');
% Rank/rate/SINR/effective-impairment metadata are NOT arithmetic operands.
changed=bound; changed.Layers=8; changed.TargetCodeRate=.99;
changed.PostEqSINR_dB=-80; changed.ReplayGridNoiseVariance=1e8;
c=collect(changed);
assert(isequaln(c.MeanRxBranchEcN0_dB,o.MeanRxBranchEcN0_dB) && ...
    isequaln(c.MeanRxBranchEbN0_dB,o.MeanRxBranchEbN0_dB));
% Repeated source records remain distinct; no pooling across point/seed.
id2=id; id2.SweepPointIndex=2; id2.Seed=9002;
e2=sixgr.link.captureLinkEnergyEvidence(tx,clean,noise,id2,"normalized_complex_baseband");
bound2=sixgr.link.bindLinkEnergyEvidence(ownerRow(tx,id2),e2);
rows=collect([bound;bound2;bound]);
assert(height(rows)==3 && all(rows.RatioAvailable) && numel(unique(rows.EvidenceID))==3 && ...
    contains(rows.InputIdentityJSON(2),'"SweepPointIndex":2'));
% Finite configured reference/SINR/rate and old energy aliases cannot rescue
% a missing receipt. High-order Qm is still reported accurately, separately.
legacy=trial; legacy.Modulation="4096QAM"; legacy.ModulationOrderQm=12;
legacy.SignalEnergyPerOccupiedRE=1; legacy.EsN0_dB=30;
legacy.EcNo_dB=20; legacy.EbNo_dB=21;
missing=collect(legacy);
assert(~missing.RatioAvailable && missing.ModulationOrderQm==12 && ...
    all(isnan([missing.EsN0_dB,missing.EcNo_dB,missing.EbNo_dB,missing.MeanRxBranchEcN0_dB])));
empty=collect(bound([],:));
assert(isempty(empty) && isstring(empty.Status) && islogical(empty.RatioAvailable));
% Original unavailable numeric identity is not an empty array or a made-up
% UE. The sealed typed value disambiguates scalar NaN from JSON null/[]/Inf.
missingID=id; missingID.UEIndex=NaN;
missingEvidence=sixgr.link.captureLinkEnergyEvidence(tx,clean,noise,missingID, ...
    "normalized_complex_baseband",compact);
missingOwner=ownerRow(tx,missingID);
missingBound=sixgr.link.bindLinkEnergyEvidence(missingOwner,missingEvidence);
missingObserved=collect(missingBound);
decodedMissing=jsondecode(missingBound.LinkEnergyEvidenceJSON);
assert(missingObserved.RatioAvailable && isnan(missingBound.UEIndex) && ...
    isnan(missingID.UEIndex) && ...
    string(decodedMissing.Identity.UEIndex.OriginalClass)=="double" && ...
    isequal(decodedMissing.Identity.UEIndex.OriginalSize(:),[1;1]) && ...
    string(decodedMissing.Identity.UEIndex.ValueState)=="original_numeric_scalar_NaN" && ...
    string(decodedMissing.IdentityMissingNumericFields)=="UEIndex" && ...
    near(missingObserved.MeanRxBranchEcN0_dB,o.MeanRxBranchEcN0_dB));
for invalid={[],Inf,-Inf,[NaN NaN]}
    badID=missingID; badID.UEIndex=invalid{1};
    reject(@()sixgr.link.captureLinkEnergyEvidence(tx,clean,noise,badID, ...
        "normalized_complex_baseband",compact),'sixgr:link:InvalidEnergyEvidence');
end
for replacement={0,1,Inf,-Inf,[]}
    bad=missingBound; bad.UEIndex={replacement{1}}; reject(@()collect(bad));
end
bad=missingBound; bad.UEIndex=[]; reject(@()collect(bad));
bad=rmfield(missingEvidence,{'IdentityValueContract','IdentityMissingNumericFields'});
bad.Identity.UEIndex=NaN;
reject(@()collect(reseal(missingOwner,bad))); % Unmarked null is never accepted.
for replacement={[],NaN,Inf,-Inf,1,[NaN NaN]}
    bad=missingEvidence; bad.Identity.UEIndex=replacement{1};
    reject(@()collect(reseal(missingOwner,bad)));
end
bad=missingEvidence; bad.Identity.UEIndex.OriginalSize=[0 0];
reject(@()collect(reseal(missingOwner,bad)));
bad=missingEvidence; bad.Identity.UEIndex.OriginalClass="uint32";
reject(@()collect(reseal(missingOwner,bad)));
bad=missingEvidence; bad.IdentityMissingNumericFields=["UEIndex";"UEIndex"];
reject(@()collect(reseal(missingOwner,bad)));
bad=missingEvidence; bad.IdentityMissingNumericFields="MissingOriginalField";
reject(@()collect(reseal(missingOwner,bad)));
bad=missingEvidence; bad.IdentityMissingNumericFields="Seed";
reject(@()collect(reseal(missingOwner,bad)));
bad=rmfield(missingEvidence,'IdentityValueContract');
reject(@()collect(reseal(missingOwner,bad)));
badOwner=missingOwner; badOwner.UEIndex={[]};
bad=rmfield(missingEvidence,{'IdentityValueContract','IdentityMissingNumericFields'});
bad.Identity.UEIndex=[]; reject(@()collect(reseal(badOwner,bad)));
finiteID=id; finiteID.UEIndex=7;
finiteEvidence=sixgr.link.captureLinkEnergyEvidence(tx,clean,noise,finiteID, ...
    "normalized_complex_baseband",compact);
finiteBound=sixgr.link.bindLinkEnergyEvidence(ownerRow(tx,finiteID),finiteEvidence);
finiteObserved=collect(finiteBound);
assert(finiteObserved.RatioAvailable && finiteEvidence.Identity.UEIndex==7 && finiteBound.UEIndex==7);
bad=finiteBound; bad.UEIndex=8; reject(@()collect(bad));
% Previously captured finite-only records are still exact-value contracts.
oldFinite=rmfield(e,{'IdentityValueContract','IdentityMissingNumericFields'});
oldObserved=collect(reseal(trial,oldFinite)); assert(oldObserved.RatioAvailable);

bad=bound; bad.LinkEnergyEvidenceSHA256=repmat("0",1,1)+extractAfter(bad.LinkEnergyEvidenceSHA256,1);
if bad.LinkEnergyEvidenceSHA256==bound.LinkEnergyEvidenceSHA256
    bad.LinkEnergyEvidenceSHA256="1"+extractAfter(bound.LinkEnergyEvidenceSHA256,1);
end
reject(@()collect(bad));
bad=bound; bad.Seed=bad.Seed+1; reject(@()collect(bad));
bad=bound; bad.RateMatchedBits=bad.RateMatchedBits+2; reject(@()collect(bad));
bad=bound; bad.TBSize_bits=bad.TBSize_bits+1; reject(@()collect(bad));
bad=e; bad.NoiseReceipt.Source="effective_noise_plus_interference"; reject(@()collect(reseal(trial,bad)));
bad=e; bad.NoiseReceipt.GridNoiseVariance=2*bad.NoiseReceipt.GridNoiseVariance;
reject(@()collect(reseal(trial,bad)));
bad=e; bad.NoiseReceipt.ConfiguredCyclicPrefix="extended"; reject(@()collect(reseal(trial,bad)));
bad=e; bad.MeasurementReceipt.MeasurementPlane="post_equalizer"; reject(@()collect(reseal(trial,bad)));
bad=e; bad.UniqueTimeFrequencyRECount=bad.UniqueTimeFrequencyRECount+1;
reject(@()collect(reseal(trial,bad)));
bad=e; bad.EnergySumPerReceiveBranch(1)=NaN; reject(@()collect(reseal(trial,bad)));
bad=e; bad.CodedBitCount=bad.CodedBitCount+2; reject(@()collect(reseal(trial,bad)));
bad=e; bad.ModulationOrderQm=8; reject(@()collect(reseal(trial,bad)));
bad=e; bad.MeasurementReceipt.ReceiveBranchCount=1; reject(@()collect(reseal(trial,bad)));
bad=e; bad.EnergySumPerReceiveBranch(:)=0; bad.MeasurementReceipt.EnergySumPerReceiveBranch(:)=0;
bad.MeasurementReceipt.SignalEnergyPerOccupiedRE=0;
zero=collect(reseal(trial,bad));
assert(~zero.RatioAvailable && zero.Status=="not_available_zero_reference_energy" && isnan(zero.MeanRxBranchEcN0_dB));
conflict=e; conflict.Identity.Seed=9999;
reject(@()sixgr.link.bindLinkEnergyEvidence(bound,conflict),'sixgr:link:EnergyEvidenceConflict');
badTX=tx; badTX.DMRSIndices=badTX.PDSCHIndices(1);
reject(@()sixgr.link.captureLinkEnergyEvidence(badTX,clean,noise,id,"normalized_complex_baseband"), ...
    'sixgr:link:InvalidEnergyEvidence');
badTX=tx; badTX.CodingLayouts={tx.CodingLayouts{1},tx.CodingLayouts{1}};
unavailable=sixgr.link.captureLinkEnergyEvidence(badTX,clean,noise,id,"normalized_complex_baseband");
assert(~unavailable.Available && contains(unavailable.Status,"multi_codeword"));
ulTX=tx; ulTX.PUSCH=tx.PDSCH; ulTX.PUSCHIndices=tx.PDSCHIndices;
ulTX.UCIOnPUSCHApplied=true; ulID=id; ulID.Direction="UL";
unavailable=sixgr.link.captureLinkEnergyEvidence(ulTX,clean,noise,ulID,"normalized_complex_baseband");
assert(~unavailable.Available && contains(unavailable.Status,"UCI"));

folder=fullfile(pwd,'results','validation','link_energy_ratio_evidence', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder)); mkdir(folder);
missingPath=fullfile(folder,'original_unavailable_numeric_identity.csv');
sixgr.util.csvWriteTable(missingPath,missingBound,'PreserveSchema',true,'RoundTripNumericText',true);
missingReadback=sixgr.util.csvReadTable(missingPath,'TextType','string');
missingReadbackObserved=sixgr.report.collectLinkEnergyRatioEvidence(missingReadback,"DL", ...
    string(missingPath),string(sixgr.util.sha256File(missingPath)));
assert(isnan(missingReadback.UEIndex) && missingReadbackObserved.RatioAvailable && ...
    missingReadback.LinkEnergyEvidenceJSON==missingBound.LinkEnergyEvidenceJSON && ...
    missingReadback.LinkEnergyEvidenceSHA256==missingBound.LinkEnergyEvidenceSHA256);
path=fullfile(folder,'original_component_trials.csv');
originalRows=[bound;bound2];
sixgr.util.csvWriteTable(path,originalRows,'PreserveSchema',true,'RoundTripNumericText',true);
readback=sixgr.util.csvReadTable(path,'TextType','string');
assert(isequal(readback.LinkEnergyEvidenceJSON,originalRows.LinkEnergyEvidenceJSON));
persisted=sixgr.report.collectLinkEnergyRatioEvidence(readback,"DL",string(path),string(sixgr.util.sha256File(path)));
assert(all(persisted.RatioAvailable) && height(persisted)==2 && ...
    near(persisted.MeanRxBranchEcN0_dB(1),o.MeanRxBranchEcN0_dB));
sixgr.util.csvWriteTable(fullfile(folder,'component_energy_observations.csv'),persisted, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
% Exercise the actual report owner with diagnostics separate from primary
% metrics. This fixture is NOT labeled an executed waveform scenario.
layout=sixgr.report.resultLayout(fullfile(folder,'report_fixture'));
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'dl_pdsch_trials.csv'),readback, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
scfg=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scfg,layout.Root);
data=scfg.toStruct(); data.output.artifact_contract_engine.enabled=true;
scfg=sixgr.lls6g.config.ScenarioConfig(data);
manifest=struct('CodeVersion',"test",'CodeDetail',"native_energy_components_not_shared_runtime", ...
    'RandomSeed',7374,'GeneratedUTC',"test",'RunnerProfile',"test",'RunCompletion',"completed",'DeterministicMode',"test");
sixgr.truth.exportLLSReportingBundle(layout.Root,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
saved=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'link_energy_ratio_observations.csv'),'TextType','string');
assert(height(saved)==2 && all(saved.RatioAvailable) && ~any(saved.CountsTowardCoverage) && ...
    all(isnan(saved.EsN0_dB)) && all(isnan(saved.EcNo_dB)) && all(isnan(saved.EbNo_dB)));
fprintf('LINK_ENERGY_RATIO_EVIDENCE_PASS native_coding_OFDM_noise_components=1 generic_Es_alias=0 shared_runtime=0 evidence=%s\n',folder);
ok=true;
end

function [tx,clean,noise,id]=nativeOperands()
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',15);
pdsch=nrPDSCHConfig('PRBSet',0:5,'NumLayers',2,'Modulation','QPSK','RNTI',7);
pdsch.DMRS.DMRSPortSet=[0 1];
[indices,info]=nrPDSCHIndices(carrier,pdsch); G=double(info.G);
A=384; R=.3; tb=int8(randi([0 1],A,1)); sch=nrDLSCHInfo(A,R);
coded=nrCRCEncode(tb,sch.CRC); blocks=sixgr.phy.tb.segmentLDPC(coded,sch.BGN);
encoded=nrLDPCEncode(blocks,sch.BGN);
[bits,rm]=sixgr.phy.phycode.rateMatchLDPC(encoded,G,0,'QPSK',2,[]);
layout=sixgr.phy.phycode.resolveCodingLayout('TransportBlockSize',A,'TargetCodeRate',R, ...
    'RateMatchedBitCount',G,'RV',0,'NumLayers',2);
assert(isequal(layout.RateMatchAccounting,rm.Accounting));
symbols=nrPDSCH(carrier,pdsch,{int8(bits)});
grid=nrResourceGrid(carrier,2); grid(indices)=symbols;
di=nrPDSCHDMRSIndices(carrier,pdsch); grid(di)=nrPDSCHDMRS(carrier,pdsch);
[wave,~]=nrOFDMModulate(carrier,grid,'Windowing',0);
clean=wave*[.7 .2i;.1 .9].'; % Actual deterministic component channel, applied once.
[~,noise]=sixgr.phy.waveform.addOccupiedREAWGN(clean,carrier,17,'Seed',7375, ...
    'SignalEnergyPerOccupiedRE',3); % Configured anchor deliberately differs from measured energy.
tx=struct('Carrier',carrier,'PDSCH',pdsch,'PDSCHIndices',indices,'Waveform',wave, ...
    'PDSCHLayerSymbolsForEvidence',symbols,'DMRSIndices',di,'PTRSIndices',zeros(0,1), ...
    'CodingLayouts',{{layout}},'TransportBlock',tb,'G',G);
id=struct('Direction',"DL",'Frame',1,'Slot',1,'Seed',7374,'SweepPointIndex',1, ...
    'ExecutionBackend',"native_coding_OFDM_noise_component_not_receiver_or_shared_runtime");
end
function row=ownerRow(tx,id)
row=struct2table(id,'AsArray',true); row.Modulation="QPSK"; row.ModulationOrderQm=2;
row.RateMatchedBits=double(tx.G); row.TBSize_bits=double(numel(tx.TransportBlock));
row.Layers=2; row.TargetCodeRate=.3; row.PostEqSINR_dB=80; row.ReplayGridNoiseVariance=1;
end
function result=collect(rows)
result=sixgr.report.collectLinkEnergyRatioEvidence(rows,"DL","declared_native_component.csv");
end
function row=reseal(row,e)
row.LinkEnergyEvidenceJSON=string(jsonencode(e));
row.LinkEnergyEvidenceSHA256=string(sixgr.util.sha256Hex(char(row.LinkEnergyEvidenceJSON)));
end
function reject(action,identifier)
if nargin<2, identifier='sixgr:report:InvalidEnergyEvidence'; end
didFail=false;
try, action(); catch cause, assert(strcmp(cause.identifier,identifier),'Unexpected rejection: %s',cause.identifier); didFail=true; end
assert(didFail,'Expected exact evidence rejection.');
end
function tf=near(a,b)
tf=abs(a-b)<1e-11;
end
