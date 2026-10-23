function [ok,folder]=testSameCaptureDMRSCSIRSComparison(varargin)
% Native pilot/OFDM/channel/receiver component, not a shared-control scenario.
% Optional {root,trial,snapshot,prepared,source,captures,owner,item} exercises
% an ALREADY published actual archive. New publication additionally requires
% ninth argument struct('Observation',originalDecoderInput,'GainCompensation',
% originalExecutedCompensation). Never reconstruct/execute that input here.
setup6GRSimToolkit('Verbose',false);
before=rng; cleanup=onCleanup(@()rng(before)); %#ok<NASGU>
folder=fullfile(pwd,'results','validation','same_capture_dmrs_csirs', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder)); mkdir(folder);
carrier=nrCarrierConfig('NSizeGrid',12,'SubcarrierSpacing',15);
pdsch=nrPDSCHConfig('PRBSet',0:11,'NumLayers',2);
pdsch.DMRS.DMRSPortSet=[0 1];
di=nrPDSCHDMRSIndices(carrier,pdsch); ds=nrPDSCHDMRS(carrier,pdsch);
signal=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',3, ...
    'Density','one','SymbolLocations',8,'SubcarrierLocations',0,'NumRB',12);
ci=nrCSIRSIndices(carrier,signal); cs=nrCSIRS(carrier,signal);
K=12*carrier.NSizeGrid; L=carrier.SymbolsPerSlot;
assert(isempty(intersect(mod(double(di)-1,K*L),mod(double(ci)-1,K*L))));
dg=nrResourceGrid(carrier,2); dg(di)=ds;
cg=nrResourceGrid(carrier,2); cg(ci)=cs;
dataMap=.7*[1 .2i;.1 .8]; csiMap=2.3*[.9 .3;.2i 1];
physicalGrid=reshape(reshape(dg,[],2)*dataMap.'+reshape(cg,[],2)*csiMap.',K,L,2);
[transmitted,~]=nrOFDMModulate(carrier,physicalGrid,'Windowing',0);
H=[.8+.1i .2-.1i;.3+.2i .6-.3i];
clean=transmitted*H.'; % This exact matrix was actually applied, once.
[received,noise]=sixgr.phy.waveform.addOccupiedREAWGN(clean,carrier,25, ...
    'Seed',74193,'SignalEnergyPerOccupiedRE',1);
[grid,ofdm]=sixgr.phy.waveform.ofdmDemodulate(carrier,received);
dh=nrChannelEstimate(carrier,grid,di,ds,'CDMLengths',[2 1]);
ch=nrChannelEstimate(carrier,grid,ci,cs,'CDMLengths',[2 1]);
op=struct('ReceiveCombiningMatrix',eye(2),'CaptureOriginCFOCorrection_Hz',0, ...
    'AlignedOriginCFOCorrection_Hz',0,'AppliedTimingCorrection_samples',0, ...
    'SampleRateHz',ofdm.SampleRate);
rx=struct('EffectiveLayerChannelEstimate',dh,'DMRSIndices',di,'DMRSSymbols',ds, ...
    'Carrier',carrier,'PDSCH',pdsch,'ReceiverChannelOperator',op,'OFDMInfo',ofdm, ...
    'RxGrid',grid,'CSIRSChannelEstimation',struct('Available',true), ...
    'CSIRSChannelEstimate',ch,'CSIRSIndices',ci,'CSIRSSymbols',cs, ...
    'CSIRSInfo',struct('ResourceID',7));
captured=sixgr.phy.dl.capturePDSCHCSIRSComparison(rx);
assert(numel(captured.Resources)==1 && captured.Resources.ResourceID==7 && ...
    captured.ReceivedGridSHA256==string(sixgr.phy.waveform.WaveformHash.runtimeArray(grid)) && ...
    ~captured.ReferenceUsedByReceiver && captured.AdditionalReceiverExecutions==0);
r=captured.Resources; Q=size(r.Support,1);
physicalReference=repmat(H,1,1,Q); maps=repmat(dataMap,1,1,Q);
[score,rows,operands]=sixgr.report.scoreDMRSCSIRSCommonOperands( ...
    r.DMRSEstimate,r.CSIRSEstimate,physicalReference,csiMap,maps,r.Support);
assert(score.Available && score.Status=="paired_exact_common_operands" && ...
    score.ComparedValues==4*Q && height(rows)==4*Q && ...
    score.DMRSErrorEnergy>0 && score.CSIRSErrorEnergy>0 && score.DeltaNMSEdBAvailable);
% Independent arithmetic on the actually estimated matrices (no channel fit).
X=csiMap\dataMap; de=0; ce=0; energy=0;
for q=1:Q
    ref=H*dataMap;
    de=de+sum(abs(r.DMRSEstimate(:,:,q)-ref).^2,'all');
    ce=ce+sum(abs(r.CSIRSEstimate(:,:,q)*X-ref).^2,'all');
    energy=energy+sum(abs(ref).^2,'all');
end
assert(abs(de-score.DMRSErrorEnergy)<1e-11 && abs(ce-score.CSIRSErrorEnergy)<1e-11 && ...
    abs(energy-score.ReferenceEnergy)<1e-11 && ...
    abs(score.DeltaNMSELinear-(de-ce)/energy)<1e-11 && ...
    max(operands.SpanClosureResidual)<1e-12 && ~operands.GainOrPhaseFitted);
% Real nonunit physical amplitudes must not be silently normalized away.
assert(norm(csiMap,'fro')~=1 && norm(dataMap,'fro')~=1 && ...
    isequal(operands.CSIRSPortToPhysicalMatrix,csiMap) && isequal(operands.DMRSLayerToPhysicalMatrices,maps));
csv=fullfile(folder,'native_common_support_operands.csv');
sixgr.util.csvWriteTable(csv,rows,'PreserveSchema',true,'RoundTripNumericText',true);
assert(isequaln(sixgr.util.csvReadTable(csv,'TextType','string'),rows));
sixgr.util.matSave(fullfile(folder,'native_component_operands.mat'), ...
    struct('Scope',"native_no_control_two_pilot_component_not_shared_owner_proof", ...
    'Capture',captured,'Operands',operands,'Score',score,'NoiseExecution',noise, ...
    'SourceCSVSHA256',sixgr.phy.waveform.WaveformHash.file(csv), ...
    'TransmittedSHA256',sixgr.phy.waveform.WaveformHash.runtimeArray(transmitted), ...
    'ReceivedSHA256',sixgr.phy.waveform.WaveformHash.runtimeArray(received)), 'UseArtifactStore',false);

% Negative arithmetic boundaries, explicitly not additional PHY executions.
[bad,empty]=sixgr.report.scoreDMRSCSIRSCommonOperands(r.DMRSEstimate, ...
    r.CSIRSEstimate(:,1,:),physicalReference,csiMap(:,1),maps,r.Support);
assert(~bad.Available && isnan(bad.DeltaNMSELinear) && isempty(empty));
[bad,~]=sixgr.report.scoreDMRSCSIRSCommonOperands(r.DMRSEstimate,r.CSIRSEstimate, ...
    physicalReference,[csiMap(:,1) csiMap(:,1)],maps,r.Support);
assert(~bad.Available && isnan(bad.ReferenceEnergy));
[zero,zeroRows]=sixgr.report.scoreDMRSCSIRSCommonOperands(r.DMRSEstimate,r.CSIRSEstimate, ...
    zeros(size(physicalReference)),csiMap,maps,r.Support);
assert(~zero.Available && zero.Status=="unavailable_zero_reference_energy" && ...
    isnan(zero.DeltaNMSELinear) && height(zeroRows)==height(rows));
exactD=repmat(H*dataMap,1,1,Q); exactC=repmat(H*csiMap,1,1,Q);
[exact,~]=sixgr.report.scoreDMRSCSIRSCommonOperands(exactD,exactC,physicalReference,csiMap,maps,r.Support);
assert(exact.Available && exact.DMRSErrorEnergy==0 && exact.DMRSNMSE_dB==-Inf && ...
    ~exact.DeltaNMSEdBAvailable && isnan(exact.DeltaNMSE_dB));
badD=r.DMRSEstimate; badD(1)=NaN;
mustFail(@()sixgr.report.scoreDMRSCSIRSCommonOperands(badD,r.CSIRSEstimate, ...
    physicalReference,csiMap,maps,r.Support),'sixgr:report:PairedChannelNonfiniteOperand');
badSupport=r.Support; badSupport(2,:)=badSupport(1,:);
mustFail(@()sixgr.report.scoreDMRSCSIRSCommonOperands(r.DMRSEstimate,r.CSIRSEstimate, ...
    physicalReference,csiMap,maps,badSupport),'sixgr:report:PairedChannelOperandShape');
missing=rx; missing.CSIRSChannelEstimation.Available=false;
uncaptured=sixgr.phy.dl.capturePDSCHCSIRSComparison(missing);
assert(isempty(uncaptured.Resources));
nanNative=rx; nanNative.CSIRSChannelEstimate(:)=NaN;
uncaptured=sixgr.phy.dl.capturePDSCHCSIRSComparison(nanNative);
assert(uncaptured.Resources.Status=="unavailable_nonfinite_native_estimate_on_common_support" && ...
    numel(uncaptured.Resources.CSIRSEstimate)==numel(r.CSIRSEstimate));
assert(isempty(sixgr.report.collectSharedDMRSCSIRSPairs(folder,table())));
unowned=struct('PairedCSIRSEstimates',captured);
mustFail(@()sixgr.truth.scoreSharedPDSCHCSIRSComparison(unowned,struct(),struct(),{},struct(),struct()), ...
    'sixgr:truth:PairedChannelOwner');
sharedCount=0;
if ~isempty(varargin)
    assert(any(numel(varargin)==[8 9]),'Supply only original caller-owned completed shared inputs.');
    actual=varargin{2};
    if ~ismember('DMRSCSIRSComparisonAvailable',actual.Properties.VariableNames) || ...
            ~actual.DMRSCSIRSComparisonAvailable
        assert(numel(varargin)==9,'sixgr:truth:PairedReceiverInputRequired', ...
            'New publication requires the original consumed decoder input and executed compensation receipt.');
        actual=sixgr.truth.exportSharedPDSCHCSIRSComparison(varargin{:});
    end
    assert(actual.DMRSCSIRSComparisonAvailable,'The supplied actual episode did not exercise a compatible pair.');
    pairs=sixgr.report.collectSharedDMRSCSIRSPairs(varargin{1},actual);
    assert(~isempty(pairs) && all(pairs.PairingStatus=="paired_exact_common_operands"));
    sharedCount=height(pairs);
    altered=actual; altered.ReceiverObservationSHA256=string(repmat('0',1,64));
    mustFail(@()sixgr.report.collectSharedDMRSCSIRSPairs(varargin{1},altered), ...
        'sixgr:report:PairedChannelSourceIdentity');
    altered=actual; altered.DMRSCSIRSComparisonCSVSHA256=string(repmat('0',1,64));
    mustFail(@()sixgr.report.collectSharedDMRSCSIRSPairs(varargin{1},altered), ...
        'sixgr:report:PairedChannelArchiveChecksum');
end
fprintf('SAME_CAPTURE_DMRS_CSIRS_PASS native_compared_values=%d shared_owner_pairs=%d scope=native_component_not_statistical folder=%s\n', ...
    score.ComparedValues,sharedCount,folder);
ok=true;
end

function mustFail(action,id)
caught=false;
try, action(); catch ex
    assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); caught=true;
end
assert(caught,'Expected %s.',id);
end
