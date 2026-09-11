function ok=testReceivedTrackingFrequencyAuthority()
% Receiver selection unit contract; values are deliberate fixtures, not PHY results.
common=struct('FrequencyEstimateDomain',"received_TRS_common_phase_frequency", ...
    'EstimatedCommonFrequency_Hz',251,'EstimatedCFO_Hz',251, ...
    'EstimatedOscillatorCFO_Hz',NaN,'InjectedCFO_Hz',0);
for runtime=[false true]
    for legacyPolicy=[false true]
        [value,domain]=sixgr.phy.rx.resolveTrackingFrequencyEstimate(common,runtime,legacyPolicy);
        assert(value==251 && domain==common.FrequencyEstimateDomain);
        modified=common; modified.InjectedCFO_Hz=-500;
        assert(sixgr.phy.rx.resolveTrackingFrequencyEstimate(modified,runtime,legacyPolicy)==value);
    end
end
bad=common; bad.EstimatedOscillatorCFO_Hz=251;
localReject(@()sixgr.phy.rx.resolveTrackingFrequencyEstimate(bad,true,false), ...
    'sixgr:phy:rx:UnseparatedOscillatorClaim');
bad=common; bad.EstimatedCFO_Hz=250;
localReject(@()sixgr.phy.rx.resolveTrackingFrequencyEstimate(bad,true,false), ...
    'sixgr:phy:rx:FrequencyEstimateDomainConflict');
for name=["sixgr.phy.dl.PDSCH_Rx","sixgr.phy.ul.PUSCH_Rx"]
    source=fileread(which(name));
    assert(~contains(source,'hasInjectedOscillatorCFO') && ...
        contains(source,'sixgr.phy.rx.resolveTrackingFrequencyEstimate'));
end
ok=true;
end

function localReject(f,id)
try, f(); catch ME, assert(string(ME.identifier)==id); return; end
error('TEST:MissingError','Expected %s.',id);
end
