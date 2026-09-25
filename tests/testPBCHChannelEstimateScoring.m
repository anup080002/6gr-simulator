function ok=testPBCHChannelEstimateScoring(bandwidthMHz,ssbIndex)
% Actual SSB waveform/receiver and declared 4TX/2RX scoring reference.
% This component does not qualify the shared-stream capture/export wiring.
setup6GRSimToolkit('Verbose',false);
assert(exist('nrWaveformGenerator','file')==2);
if nargin==0
    for index=[0 1 2 3]
        assert(testPBCHChannelEstimateScoring(5,index));
    end
    for index=[0 3 4 7]
        assert(testPBCHChannelEstimateScoring(20,index));
    end
    ok=true;
    return;
end
if nargin<2, ssbIndex=0; end
cfg=sixgr.config.defaultConfig();
cfg.run.strictMode=true;
cfg.phy.carrier.NCellID=17;
switch bandwidthMHz
    case 5
        scs=15; nrb=25; frequency=2.35e9; pattern='Case A'; lmax=4;
    case 20
        scs=30; nrb=51; frequency=3.5e9; pattern='Case B'; lmax=8;
    otherwise
        error('test:UnsupportedPBCHFixture','Choose the explicit 5 or 20 MHz fixture.');
end
cfg.phy.carrier.centerFrequency_Hz=frequency;
cfg.phy.carrier.SubcarrierSpacing=scs;
cfg.phy.carrier.SubcarrierSpacing_kHz=scs;
cfg.phy.carrier.NSizeGrid=nrb;
cfg.phy.ssb.scs_kHz=scs; cfg.phy.ssb.blockPattern=pattern; cfg.phy.ssb.Lmax=lmax;
cfg.phy.channelBandwidth_MHz=bandwidthMHz;
cfg.frequency.bandwidth_hz=bandwidthMHz*1e6;
[carrier,~]=sixgr.phy.grid.makeCarrier(cfg);
[tx,~,txInfo]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',5,'SSBIndex',ssbIndex);
assert(size(tx,2)==1,'This fixture starts with one actual logical PBCH port.');
W=ones(4,1)/2;
H=[.8 0 .6 0;0 .6 0 .8];
physicalTX=tx*W.';
physicalRX=physicalTX*H.';
received=sixgr.phy.waveform.addOccupiedREAWGN(physicalRX,carrier,20, ...
    'Seed',9242301,'SignalEnergyPerOccupiedRE',1);
[grid,sync]=sixgr.phy.dl.SSB_Rx(received,cfg,'SampleRate_Hz',txInfo.SampleRate_Hz);
% Exercise the exact production demodulator call on the received samples.
% Only receiver-acquired timing determines the FFT origin. This fixture
% has no CFO or SSB placement translation; do not silently ignore either.
assert(sync.FreqOffset_Hz==0 && sync.SSBPlacementCorrectionAppliedHz==0);
ssbCarrier=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',sync.SCS_SSB_kHz, ...
    'NSlot',sync.DemodulationSlot);
phaseInfo=nrOFDMInfo(ssbCarrier,'Nfft',sync.Nfft,'SampleRate',sync.SampleRate_Hz, ...
    'CarrierFrequency',cfg.phy.carrier.centerFrequency_Hz);
columns=sync.SSBSymbolColumnsOneBased;
prefix=sum(sync.Nfft+sync.CyclicPrefixLengthsPerSlot(1:columns(1)-1));
first=1+sync.AppliedTimingCorrection_samples-prefix;
assert(first>=1 && first==fix(first));
candidateGrid=sixgr.phy.waveform.ofdmDemodulate(ssbCarrier,received(first:end,:), ...
    'Nfft',sync.Nfft,'SampleRate',sync.SampleRate_Hz, ...
    'CarrierFrequency',sync.SSBTiming.CarrierFrequencyHz);
candidateGrid=candidateGrid(:,columns,:);
assert(isequal(candidateGrid,grid) && ...
    sync.SymbolPhaseCompensationCarrierFrequencyHz==frequency, ...
    'The production receiver must use configured carrier-frequency phase compensation.');
% Negative control: reproduce the old receiver with phase reversal omitted.
legacyGrid=sixgr.phy.waveform.ofdmDemodulate(ssbCarrier,received(first:end,:), ...
    'Nfft',sync.Nfft,'SampleRate',sync.SampleRate_Hz,'CarrierFrequency',0);
legacyGrid=legacyGrid(:,columns,:);
[legacyPBCH,~]=sixgr.phy.dl.PBCH_Recovery(legacyGrid,sync,cfg);
phaseCorrectedGrid=legacyGrid.*reshape(exp(-1i*phaseInfo.SymbolPhases(columns)),1,4,1);
% GHz carrier phase arguments have larger absolute rounding error than
% unit-scale grid values; bound it from the argument, not a fitted phase.
phaseArgument=2*pi*frequency*(sync.DemodulationSlot+1)*1e-3/(scs/15);
phaseTolerance=32*eps(phaseArgument)*max(1,max(abs(legacyGrid),[],'all'));
assert(max(abs(candidateGrid-phaseCorrectedGrid),[],'all')<=phaseTolerance);
[pbch,~]=sixgr.phy.dl.PBCH_Recovery(grid,sync,cfg);
assert(pbch.Ok && size(pbch.ChannelEstimateGrid,3)==2);
% Exact declared transmitter amplitude and applied matrix, not a fit to RX.
power=txInfo.SSBBurstPlan.PerSSBPowerDB(pbch.SSBIndex+1);
gain=(H*W)*10^(power/20);
reference=repmat(reshape(gain,1,1,2),240,4,1);
score=sixgr.phy.dl.scorePBCHChannelEstimate(pbch,reference);
legacyScore=sixgr.phy.dl.scorePBCHChannelEstimate(legacyPBCH,reference);
folder=fullfile(pwd,'results','lls','pbch_channel_estimate_scoring', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
save(fullfile(folder,'received_channel.mat'),'pbch','sync','reference','score', ...
    'txInfo','H','W','legacyScore','phaseInfo','grid');
fprintf('PBCH_SYMBOL_PHASE_COMPARISON original_nmse_db=%g candidate_nmse_db=%g configured_carrier_hz=%g\n', ...
    legacyScore.NMSE_dB,score.NMSE_dB,cfg.phy.carrier.centerFrequency_Hz);
assert(score.NMSE_dB < -10 && score.ChannelNMSEComparedComplexValues==288 && ...
    score.ChannelNMSENumReceiveBranches==2 && score.ChannelNMSENumLogicalPorts==1, ...
    'test:PBCHChannelScoringMismatch','NMSE=%g values=%d RX=%d ports=%d evidence=%s', ...
    score.NMSE_dB,score.ChannelNMSEComparedComplexValues, ...
    score.ChannelNMSENumReceiveBranches,score.ChannelNMSENumLogicalPorts,folder);
% Independent direct NMSE on the same 144 PBCH DM-RS REs per RX branch.
indices=double(nrPBCHDMRSIndices(pbch.NCellID));
E=reshape(pbch.ChannelEstimateGrid,960,2); R=reshape(reference,960,2);
ratio=sum(abs(E(indices,:)-R(indices,:)).^2,'all')/sum(abs(R(indices,:)).^2,'all');
assert(abs(score.NMSELinear-ratio)<1e-12);
before=pbch;
poisoned=sixgr.phy.dl.scorePBCHChannelEstimate(pbch,100i*reference);
assert(isequaln(before,pbch) && abs(poisoned.NMSE_dB-score.NMSE_dB)>5 && ...
    ~score.ChannelNMSEGainOrPhaseFitted && ~score.ChannelNMSEReferenceUsedByReceiver);
bad=reference; bad(indices(1))=NaN;
rejected=false;
try
    sixgr.phy.dl.scorePBCHChannelEstimate(pbch,bad);
catch ex
    rejected=strcmp(ex.identifier,'sixgr:srs:IncompletePilotChannelReference');
end
assert(rejected,'Do not drop unscored RX resources or replace missing reference values.');
fprintf('PBCH_CHANNEL_ESTIMATE_SCORING_PASS bandwidth_mhz=%g ssb_index=%d demod_slot=%d nmse_db=%.9g values=%d physical_tx=4 physical_rx=2 shared_export_verified=0\n', ...
    bandwidthMHz,ssbIndex,sync.DemodulationSlot,score.NMSE_dB,score.ChannelNMSEComparedComplexValues);
ok=true;
end
