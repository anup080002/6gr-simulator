function ok = testRARTimingTraceUnits()
% Actual MAC codec and analytic unit checks, not a shared-waveform test.
cfg = raStrictAnchorConfig();
ra = sixgr.mac.ra.RAConfig(cfg, 'RunId', 'rar_trace_units');
grant = sixgr.mac.ra.buildRARULGrant(ra);
packet = sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex, ...
    'TimingAdvanceCommand',3,'TemporaryCRNTI',ra.TempCRNTI,'ULGrant',grant);
rar = sixgr.mac.ra.decodeMACRAR(packet.Bytes,ra);
for scs = [15 30]
    for transmitRate = [7.68e6 15.36e6]
        timing = sixgr.phy.ra.resolveRARTimingAdvance(rar.TimingAdvanceCommand,scs,transmitRate);
        result = struct('TimingAdvanceCommand',rar.TimingAdvanceCommand, ...
            'TimingAdvanceNTA_Tc',timing.NTA_Tc,'TimingAdvanceSamples',timing.Samples, ...
            'TimingAdvanceSampleRate_Hz',transmitRate, ...
            'TimingAdvanceSource',"received_MAC_RAR_absolute_command_ts_38_213_4_2");
        for traceRate = [7.68e6 15.36e6]
            samples = sixgr.truth.receivedRARTimingOnTraceClock(result,traceRate);
            expected = 3*1024/(scs/15)/(480e3*4096)*traceRate;
            assert(abs(samples-expected)<1e-12 && samples~=3, ...
                'The RAR command index must never masquerade as trace-clock samples.');
        end
    end
end
assert(isnan(sixgr.truth.receivedRARTimingOnTraceClock(struct(),7.68e6)));
bad = result; bad.TimingAdvanceSamples = bad.TimingAdvanceSamples + 1;
localReject(@()sixgr.truth.receivedRARTimingOnTraceClock(bad,7.68e6), ...
    'sixgr:truth:RARTimingTraceUnitMismatch');
bad = result; bad.TimingAdvanceSource = "gnb_detector_estimate";
localReject(@()sixgr.truth.receivedRARTimingOnTraceClock(bad,7.68e6), ...
    'sixgr:truth:InvalidRARTimingTraceAuthority');
% Check the production adapter actually uses the validated conversion.
source = string(fileread(fullfile(pwd,'+sixgr','+truth','runWaveformLinkBundle.m')));
start = strfind(source,'function T = localBuildFourStepRACorrelationTraceTable');
stop = strfind(source,'function tables = localEmptyRAEvidenceTables');
adapter = extractBetween(source,start,stop-1);
assert(contains(adapter,'sixgr.truth.receivedRARTimingOnTraceClock(ra, sampleRateHz)'));
assert(~contains(adapter,'structGet(ra, "TimingAdvanceCommand"'));
ok = true;
disp('RAR_TIMING_TRACE_UNITS_PASS: decoded command, Tc, independent PRACH/PUSCH clocks; no shared timing claim.');
end

function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
