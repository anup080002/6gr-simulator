function ok=testPUCCHPowerVectorEvidence()
setup6GRSimToolkit('Verbose',false);
repo=fileparts(fileparts(mfilename('fullpath')));
root=fullfile(repo,'tests','vectors','pucch');
profile=fullfile(repo,'simulator','configs','validation','pucch_power_waveform.yaml');
t=sixgr.phy.pucch.PUCCHPowerVectorEvidence.build(root,'focused_power_waveforms',profile);
assert(height(t)==48 && all(t.Status=="PASS"));
actual=str2double(t.MeasuredWaveformPowerdBm); expected=str2double(t.ExpectedTransmitPowerdBm);
assert(all(isfinite(actual))&&all(abs(actual-expected)<=str2double(t.Tolerance_dB)));
assert(all(t.MeasurementReferenceDomain=="specified_active_ofdm_symbols_excluding_cp"));
assert(all(t.MeasurementReferencePlane=="post_ifft_cp_pre_node_rf"));
assert(all(t.MeasurementSampleCount>0 & t.WaveformSampleCount>t.MeasurementSampleCount));
assert(all(strlength(t.WaveformSHA256)==64 & strlength(t.ProfileSHA256)==64));
assert(isequal(unique(t.Numerology).',[0 1 2 3]));
for k=1:height(t)
    p=jsondecode(t.PowerStateJSON(k)); r=jsondecode(t.ResourceJSON(k));
    a=jsondecode(t.AssignmentJSON(k));
    assert(p.Mu==t.Numerology(k)&&p.MRB==r.NumPRBs&&p.MRB==t.AllocatedPRBCount(k));
    assert(~a.ConnectedModeEvidenceEligible);
    assert(string(a.AssignmentSource)=="component_power_vector_fixture");
    assert(str2double(t.MeasuredSlotAveragePowerdBm(k))<actual(k)-3);
end
folder=tempname; mkdir(folder);
path=fullfile(folder,'pucch_power_control.csv');
sixgr.util.csvWriteTable(path,t,'PreserveSchema',true);
reopened=sixgr.util.csvReadTable(path,'TextType','string');
assert(height(reopened)==height(t));
assert(all(string(reopened.WaveformSHA256)==t.WaveformSHA256));
% TextType does not force numeric columns to text. string(double) formats
% for display and loses digits; compare the parsed doubles directly.
persisted=reopened.MeasuredWaveformPowerdBm;
if ~isnumeric(persisted), persisted=str2double(string(persisted)); end
assert(all(abs(double(persisted)-actual)<1e-12));
fprintf('PUCCH_POWER_VECTOR_WAVEFORMS_PASS rows=%d max_error_db=%.12g csv=%s\n', ...
    height(t),max(abs(actual-expected)),path);
ok=true;
end
