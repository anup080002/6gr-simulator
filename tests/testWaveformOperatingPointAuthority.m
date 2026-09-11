function ok=testWaveformOperatingPointAuthority()
% Typed authority/state-machine fixtures; not exported radio measurements.
setup6GRSimToolkit('Verbose',false);
cfg=struct('channel',struct('snr_dB',12));
state=struct('CurrentSlot',10,'CurrentSNR_dB',35.78);
f=sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRowRuntime();
f.Valid=true; f.SINR_dB=45; f.SourceSlot=6; f.DeliveredSlot=7;
state.LatestDLFeedback=f; f.SINR_dB=-8; state.LatestULFeedback=f;
state.PendingCSITable=table(1,"DL",80,9,12, ...
    'VariableNames',{'UEIndex','Direction','SINR_dB','SourceSlot','DueSlot'});
state.LargeScaleState=struct('RxPower_dBm',-40);
assert(sixgr.truth.resolveWaveformOperatingPointMetadata(cfg)==12);
assert(sixgr.truth.resolveWaveformOperatingPointMetadata(cfg,17)==17);
assert(sixgr.truth.resolveDeliveredLinkQuality(state,1,'DL')==45);
assert(sixgr.truth.resolveDeliveredLinkQuality(state,1,'UL')==-8);
state.LatestDLFeedback.Valid=false;
assert(isnan(sixgr.truth.resolveDeliveredLinkQuality(state,1,'DL')), ...
    'Pending CSI or geometry cannot replace missing delivered feedback.');
state.LatestDLFeedback.Valid=true; state.LatestDLFeedback.DeliveredSlot=11;
assert(isnan(sixgr.truth.resolveDeliveredLinkQuality(state,1,'DL')));
state.LatestDLFeedback.DeliveredSlot=7; state.LatestDLFeedback.SourceSlot=8;
assert(isnan(sixgr.truth.resolveDeliveredLinkQuality(state,1,'DL')));
for invalid={NaN,Inf,[12 13],1i}
    rejected=false;
    try
        sixgr.truth.resolveWaveformOperatingPointMetadata(cfg,invalid{1});
    catch err
        if ~strcmp(err.identifier,'sixgr:truth:MissingConfiguredWaveformOperatingPoint'), rethrow(err); end
        rejected=true;
    end
    assert(rejected,'Invalid configured authority must not silently use a different source.');
end
% Integration wiring guard: all eight DL/UL control/reference call sites
% must use the configured authority; the retired mixed-domain resolver must
% not remain available for a legacy waveform path.
code=fileread(which('sixgr.truth.runWaveformLinkBundle'));
assert(~contains(code,'localResolveCoupledRuntimeLinkSNR') && ...
    ~contains(code,'localEstimateCoupledRuntimeLargeScaleSINR'));
assert(numel(strfind(code,'sixgr.truth.resolveWaveformOperatingPointMetadata('))==8);
assert(contains(code,'sixgr.truth.resolveDeliveredLinkQuality(tempState, ueIdx, direction)'));
% Physical noise variance remains independent of the nominal label in both
% duplex profiles. This invokes the actual power/noise ledger and resolver.
for mode=["TDD","FDD"]
    name='lls_causal_access_to_data_wiring_tdd.yaml';
    if mode=="FDD", name='lls_trs_shared_scoring_fdd_fixture.yaml'; end
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',name));
    c=sixgr.lls6g.buildInternalConfig(s,tempname);
    carrier=sixgr.phy.grid.makeCarrier(c); info=nrOFDMInfo(carrier);
    fs=info.SampleRate;
    for direction=["DL","UL"]
        c=sixgr.util.structSet(c,'lls6g.userContext.RuntimeCurrentDirection',direction);
        c.channel.snr_dB=12;
        [~,a]=sixgr.link.applyWaveformImpairments(complex(zeros(8,2)),c,fs,'ApplyRFChain',false);
        c.channel.snr_dB=35.78;
        [~,b]=sixgr.link.applyWaveformImpairments(complex(zeros(8,2)),c,fs,'ApplyRFChain',false);
        assert(a.ConfiguredSNR_dB==12 && b.ConfiguredSNR_dB==35.78);
        if logical(sixgr.util.structGet(c,'integration.configured_snr_is_link_authority',false))
            assert(string(a.NoiseOperatingMode)=="standalone_awgn_snr_argument" && ...
                a.AppliedAWGNSNR_dB==12 && b.AppliedAWGNSNR_dB==35.78 && ...
                isnan(a.AppliedPathloss_dB) && isnan(a.AppliedO2I_dB), ...
                ['A configured-Es/N0 LLS point must control AWGN and must ' ...
                 'not retain dormant geometry/pathloss as physical evidence.']);
        else
            assert(string(a.NoiseOperatingMode)=="receiver_noise_figure_thermal_noise");
            va=sixgr.link.resolveReceiverThermalNoiseVariance(a);
            vb=sixgr.link.resolveReceiverThermalNoiseVariance(b);
            assert(isfinite(va) && va>0 && va==vb, ...
                'Changing metadata must not change physical %s receiver variance in %s.',direction,mode);
        end
    end
end
fprintf('WAVEFORM_OPERATING_POINT_AUTHORITY_PASS: DL/UL, TDD/FDD, delivered feedback and thermal-noise separation.\n');
ok=true;
end
