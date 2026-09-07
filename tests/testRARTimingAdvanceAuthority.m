function ok = testRARTimingAdvanceAuthority()
% Analytic timing/actual MAC codec checks, not received channel measurements.
setup6GRSimToolkit('Verbose',false);
for scs = [15 30 60 120 240 480 960]
    for fs = [7.68e6 15.36e6 30.72e6 61.44e6]
        stepSeconds = (16*64)/(480e3*4096)/(scs/15);
        stepSamples = fs*stepSeconds;
        det = struct('TimingOffsetSamples',17.25*stepSamples, ...
            'PropagationTimingOffsetSamples',17.25*stepSamples);
        ta = sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det,fs,scs);
        assert(ta.Valid && ta.TimingAdvanceCommand==17 && ...
            abs(ta.TimingAdvanceSamples-17*stepSamples)<1e-12 && ...
            abs(ta.QuantizationResidualSamples-0.25*stepSamples)<1e-12);
        decoded = sixgr.phy.ra.resolveRARTimingAdvance(17,scs,2*fs);
        assert(abs(decoded.Samples-2*ta.TimingAdvanceSamples)<1e-12 && ...
            decoded.NTA_Tc==ta.NTA_Tc, ...
            'The same RAR must preserve absolute time across PRACH/PUSCH sample rates.');
    end
end
% Reproduces the historical hardcoded divisor defect: at 7.68 MHz/15 kHz,
% a 17-sample observation commands 4 (16 samples), not 1 or raw 17 samples.
det = struct('TimingOffsetSamples',17,'PropagationTimingOffsetSamples',17);
ta = sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det,7.68e6,15);
assert(ta.TimingAdvanceCommand==4 && ta.TimingAdvanceSamples==16);

cfg = raStrictAnchorConfig();
ra = sixgr.mac.ra.RAConfig(cfg,'RunId','rar_ta_codec');
grant = sixgr.mac.ra.buildRARULGrant(ra);
packet = sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex, ...
    'TimingAdvanceCommand',3,'TemporaryCRNTI',ra.TempCRNTI,'ULGrant',grant);
rar = sixgr.mac.ra.decodeMACRAR(packet.Bytes,ra);
waveform = complex((1:64)',(64:-1:1)');
applied = sixgr.phy.ra.applyDecodedRARTimingAdvance(waveform,rar,15,7.68e6);
assert(applied.RARTiming.Command==3 && applied.TimingAdvanceSamples==12 && ...
    applied.RARTiming.NTA_Tc==3072);
assert(isequal(applied.Waveform(1:end-12,:),waveform(13:end,:)));
assert(applied.RARTiming.Command~=ta.TimingAdvanceCommand, ...
    'Only the decoded command may control UE transmit timing, not an earlier gNB estimate.');
invalid = det; invalid.PropagationTimingOffsetSamples=NaN;
missing = sixgr.phy.ra.estimateTimingAdvanceFromPRACH(invalid,7.68e6,15);
assert(~missing.Valid && isnan(missing.TimingAdvanceCommand));
localReject(@()sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det), ...
    'sixgr:phy:ra:MissingRARTimingClock');
for command=[-1 3847 1.5 NaN]
    localReject(@()sixgr.phy.ra.resolveRARTimingAdvance(command,15,7.68e6), ...
        'sixgr:phy:ra:InvalidRARTimingCommand');
end
far = det; far.PropagationTimingOffsetSamples=4*3847;
localReject(@()sixgr.phy.ra.estimateTimingAdvanceFromPRACH(far,7.68e6,15), ...
    'sixgr:phy:ra:PRACHTimingOutsideRARRange');
localReject(@()sixgr.phy.ra.applyDecodedRARTimingAdvance(waveform,struct(),15,7.68e6), ...
    'sixgr:phy:ra:MissingDecodedRARTimingCommand');
fractional = rar; fractional.TimingAdvanceCommand=1;
localReject(@()sixgr.phy.ra.applyDecodedRARTimingAdvance(waveform,fractional,120,7.68e6), ...
    'sixgr:phy:ra:RARTimeNotOnSampleClock');
ok = true;
disp('PASS testRARTimingAdvanceAuthority: Tc/SCS/sample-clock conversion and decoded RAR authority.');
end

function localReject(fn,id)
try, fn(); catch ex
    assert(string(ex.identifier)==id,'Expected %s; got %s: %s',id,ex.identifier,ex.message);
    return;
end
error('testRARTimingAdvanceAuthority:MissingRejection','Expected %s.',id);
end
