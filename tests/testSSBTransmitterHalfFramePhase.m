function ok=testSSBTransmitterHalfFramePhase()
% Native standalone SS/PBCH phase/CRC test, not coupled access qualification.
% TS 38.213 V18.8.0 4.1: candidate symbols are half-frame relative.
% Native nrWavegenSSBurstConfig.Period supplies the actual half-frame offset
% and encoded PBCH half-frame bit, rather than shifting a phase-zero buffer.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
for scs=[15 30]
    cfg=localConfig(scs);
    for half=[0 1]
        fprintf('SSB_PHASE_CASE scs=%g half=%g\n',scs,half);
        cfg.phy.ssb.halfFrameIndex=half;
        original=cfg;
        [~,~,timingOnly]=sixgr.phy.dl.SSB_Tx(cfg,'TimingOnly',true);
        [wave,info,tx]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',10);
        canonical=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
        assert(isequaln(cfg,original) && ...
            isequaln(tx.SSBTiming,timingOnly.SSBTiming) && ...
            isequal(tx.SSBTiming.CandidateStartSymbols,canonical.CandidateStartSymbols));
        assert(tx.SSBBurstPlan.HalfFrameIndex==half);
        grid=info.ResourceGridSSBurst.ResourceGrid;
        active=find(any(abs(grid)>0,[1 3]))-1;
        expected=canonical.CandidateStartSymbols(1)+(0:3);
        assert(isequal(active(:).',expected(:).'), ...
            'sixgr:test:SSBPhaseNativeGrid','Actual native occupied symbols must match the configured phase.');
        carrier=sixgr.phy.grid.makeCarrier(cfg);
        for slot=0:carrier.SlotsPerFrame-1
            c=carrier;c.NSlot=slot;
            reservation=sixgr.phy.frame.ssbPRBSymbolReservation(cfg,c,slot);
            expectedActive=any(floor(active/carrier.SymbolsPerSlot)==slot);
            assert(~isempty(reservation.ReservedCarrierRE0)==expectedActive);
        end
        [rx,sync]=sixgr.phy.dl.SSB_Rx(wave,cfg,'SampleRate_Hz',tx.SampleRate_Hz);
        assert(sync.SelectedCandidateStartSymbol==canonical.CandidateStartSymbolsWithinHalfFrame(1) && ...
            sync.SelectedCandidateAbsoluteStartSymbol==canonical.CandidateStartSymbols(1) && ...
            sync.DemodulationSlot==floor(canonical.CandidateStartSymbols(1)/14));
        [pbch,~]=sixgr.phy.dl.PBCH_Recovery(rx,sync,cfg);
        assert(pbch.Ok && pbch.SSBIndex==0 && pbch.HalfFrame==half, ...
            'sixgr:test:SSBPhasePBCH','The actual PBCH CRC and decoded half-frame bit must agree with the native emission.');
    end
end
bad=cfg;bad.phy.ssb.periodicity_ms=5;
localReject(@()sixgr.phy.dl.SSB_Tx(bad,'TimingOnly',true), ...
    'sixgr:phy:ssb:InvalidPeriodPhase');
% Empty owner is deliberate: this negative must reject before link lookup,
% sample enqueue, component publication or any receiver outcome exists.
owner=sixgr.truth.CoupledWaveformStream();before=owner.Pending;random=rng;
localReject(@()owner.queueDownlink("PBCH",1,struct(),struct('Config',cfg)), ...
    'sixgr:truth:UnsupportedSharedSSBPhaseOrigin');
assert(isequaln(owner.Pending,before) && isequal(rng,random));
fprintf('SSB_TRANSMITTER_HALF_FRAME_PHASE_PASS native_15_30kHz_phase0_1_CRC shared_phase_fail_closed\n');
ok=true;
end

function cfg=localConfig(scs)
cfg=struct();cfg.frequency.range_name='FR1';cfg.phy.frequencyRange='FR1';
cfg.phy.duplex=struct('mode','FDD');
cfg.phy.frame=struct('slotFormat','fdd_separate_carriers');
if scs==15,fc=2.35e9;bw=5;nrb=25;pattern='Case A';lmax=4;
else,fc=4e9;bw=20;nrb=51;pattern='Case B';lmax=8;end
cfg.channel.fc_Hz=fc;cfg.frequency.center_frequency_hz=fc;
cfg.frequency.bandwidth_hz=bw*1e6;cfg.phy.channelBandwidth_MHz=bw;
cfg.phy.carrier=struct('NCellID',17,'SubcarrierSpacing_kHz',scs, ...
    'SubcarrierSpacing',scs,'CyclicPrefix','normal','NStartGrid',0,'NSizeGrid',nrb);
cfg.phy.ssb=struct('enable',true,'blockPattern',pattern,'scs_kHz',scs, ...
    'Lmax',lmax,'periodicity_ms',20);
cfg.phy.pbch=struct('enable',true);
cfg.phy.mib=struct('pdcchConfigSIB1',0,'dmrsTypeAPosition',2, ...
    'cellBarred',false,'intraFreqReselection',false);
cfg.phy.sib1=struct('coreset0Index',0,'searchSpaceZero',0);
cfg.phy.synchronization=struct('ssbDetectorTargetFalseAlarmProbability',1e-3, ...
    'pssDetectionThreshold',0,'sssHypothesisTestThreshold',0);
end

function localReject(f,id)
try,f();catch cause,assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);return;end
error('sixgr:test:ExpectedSSBPhaseError','Expected %s.',id);
end
