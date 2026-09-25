function ok=testACLRArtifactSourceBinding()
% Verify the constructed RF measurement artifact has honest units/axes.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
root=fileparts(fileparts(mfilename('fullpath')));
rfRoot=fullfile(root,'tests','vectors','rf');
rf=sixgr.rf.runtime.RFPhaseEvidenceBuilder.build(rfRoot);
T=rf.rf_aclr_measurement;
assert(all(T.PowerUnit=="input_amplitude_squared_not_implicitly_watts"));
assert(~any(contains(string(T.Properties.VariableNames),"dBm")));
assert(all(abs(T.ACLRLower_dB-(T.AssignedPower_dB_re_InputPowerUnit- ...
    T.AdjacentLowerPower_dB_re_InputPowerUnit))<1e-9));
assert(all(abs(T.ACLRUpper_dB-(T.AssignedPower_dB_re_InputPowerUnit- ...
    T.AdjacentUpperPower_dB_re_InputPowerUnit))<1e-9));
out=fullfile(root,'results','lls','aclr_artifact_repair', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
vectorOut=fullfile(out,'contracts'); mkdir(vectorOut);
C=readtable(fullfile(rfRoot,'desired_rf_csv_contract.csv'),'TextType','string');
writetable(C(C.FileName=="rf_aclr_measurement.csv",:),fullfile(vectorOut,'desired_rf_csv_contract.csv'));
C=readtable(fullfile(rfRoot,'desired_rf_image_contract.csv'),'TextType','string');
writetable(C(C.ImageFile=="rf_aclr_spectrum.png",:),fullfile(vectorOut,'desired_rf_image_contract.csv'));
summary=sixgr.rf.runtime.RFArtifactExporter.exportBase(rf,vectorOut,out);
assert(summary.Passed && summary.ImageAudit.FinitePointCount==2*height(T));
assert(summary.ImageAudit.XLabel=="Case index" && summary.ImageAudit.YLabel=="ACLR (dB)");
assert(contains(summary.ImageAudit.Title,"not RF conformance"));
fprintf('ACLR_ARTIFACT_SOURCE_BINDING_PASS rows=%d output=%s\n',height(T),out);
ok=true;
end
