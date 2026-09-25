function ok=testCSIReferenceSINRPublication(retainedCSV)
% Publication contract only; this test does not qualify the estimator.
observation=struct('Observed',true,'ReferenceMeasuredSINR_dB',-4.75, ...
    'ReferenceMeasuredSINRStatus',"available", ...
    'ReferenceMeasuredSINRSource',"received_reference_RE_power", ...
    'SINRMeasurementDomain',"csi_rs_port3000_reference_re_received_plane", ...
    'SINR_dB',17,'CQIEffectiveSINR_dB',28);
fields=sixgr.link.csiReferenceSINRPublication(observation,-10);
assert(fields.ConfiguredSNR_dB==-10 && fields.MeasuredSINR_dB==-4.75 && ...
    fields.MeasuredTrialSINR_dB==-4.75 && ...
    fields.MeasuredSINRDomain==observation.SINRMeasurementDomain && ...
    fields.MeasuredTrialSINRMeasurementDomain==observation.SINRMeasurementDomain);
assert(~isfield(fields,'SINR_dB') && ~isfield(fields,'CQIEffectiveSINR_dB') && ...
    ~isfield(fields,'SINRMeasurementDomain'));
poison=observation; poison.SINR_dB=999; poison.CQIEffectiveSINR_dB=-999;
assert(isequaln(fields,sixgr.link.csiReferenceSINRPublication(poison,-10)));
absent=observation; absent.ReferenceMeasuredSINR_dB=NaN;
missing=sixgr.link.csiReferenceSINRPublication(absent,-10);
assert(isnan(missing.MeasuredSINR_dB) && missing.MeasuredTrialSINRValueStatus=="unavailable");
absent=observation; absent.ReferenceMeasuredSINRStatus="not_attempted";
missing=sixgr.link.csiReferenceSINRPublication(absent,-10);
assert(isnan(missing.MeasuredSINR_dB));
for invalid=["fallback_estimate","configured_SNR","proxy_value",""]
    bad=observation; bad.ReferenceMeasuredSINRSource=invalid;
    reject(@()sixgr.link.csiReferenceSINRPublication(bad,-10));
end
bad=observation; bad.Observed=false;
reject(@()sixgr.link.csiReferenceSINRPublication(bad,-10));
% Canonical readers use <metric>MeasurementDomain, not <metric>Domain.
% Preserve a different objective plane through CSV serialization as well.
published=fields;
published.SINR_dB=observation.SINR_dB;
published.SINRMeasurementDomain="selected_PMI_receiver_objective";
published.CQIEffectiveSINR_dB=observation.CQIEffectiveSINR_dB;
csv=[tempname '.csv']; cleanup=onCleanup(@()delete(csv));
writetable(struct2table(published),csv);
roundtrip=readtable(csv,'TextType','string','VariableNamingRule','preserve', ...
    'Delimiter',',','ReadVariableNames',true,'NumHeaderLines',0);
assert(roundtrip.MeasuredTrialSINRMeasurementDomain==observation.SINRMeasurementDomain && ...
    roundtrip.SINRMeasurementDomain=="selected_PMI_receiver_objective" && ...
    roundtrip.MeasuredTrialSINR_dB==-4.75 && roundtrip.SINR_dB==17 && ...
    roundtrip.CQIEffectiveSINR_dB==28);
if nargin>0
    % Read-only replay of retained receiver evidence, no old CSV rewriting.
    T=readtable(retainedCSV,'TextType','string','VariableNamingRule','preserve', ...
        'Delimiter',',','ReadVariableNames',true,'NumHeaderLines',0);
    observedCount=0;
    for k=1:height(T)
        if ~isfinite(T.ReferenceMeasuredSINR_dB(k)), continue; end
        row=table2struct(T(k,:));
        row.SINRMeasurementDomain=row.ReferenceMeasuredSINRDomain;
        result=sixgr.link.csiReferenceSINRPublication(row,row.SNR_dB);
        assert(result.MeasuredSINR_dB==row.ReferenceMeasuredSINR_dB);
        evidence=jsondecode(row.ReferenceSINRMeasurementJSON);
        assert(abs(result.MeasuredSINR_dB-evidence.CSI_SINR_dB)<1e-12);
        observedCount=observedCount+1;
    end
    assert(observedCount>0,'Retained fixture needs an actual measured CSI reference row.');
    fprintf('CSI_REFERENCE_PUBLICATION_RETAINED_ROWS=%d\n',observedCount);
end
fprintf('CSI_REFERENCE_PUBLICATION_PASS reference_plane_preserved=1 CQI_not_substituted=1 no_missing_fallback=1\n');
ok=true;
end

function reject(f)
try, f(); catch e
    assert(strcmp(e.identifier,'sixgr:link:CSIReferenceSINRPublicationAuthority')); return;
end
error('test:ExpectedPublicationRejection','Invalid measurement authority must be rejected.');
end
