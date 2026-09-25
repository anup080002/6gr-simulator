function ok=testPUCCHFormat0ExportEvidence()
% Metadata regression for actual Format-0 receiver execution, not RF qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
T=table([35;36;37], ["harq_ack";"harq_ack";"standalone_sr"], ...
    ["0";"1";"1"], ["0";"1";"1"], ...
    'VariableNames',{'Slot','UCIType','UCIExpectedBitVector','UCIDecodedBitVector'});
T.Status=repmat("PASS",3,1);
T.PUCCHFormat=zeros(3,1); T.PUCCHDMRSRECount=zeros(3,1);
T.NoncoherentSequenceDetection=true(3,1);
T.DecodeNoiseVarianceDomain=repmat("not_consumed_noncoherent_sequence_detection",3,1);
T.NoiseVariance=nan(3,1); T.NoiseVarStatus=repmat("unavailable",3,1);
T.NoiseVarStrictFailure=false(3,1);
T.DetectionMetric=[0.42485;0.7;0.8]; T.DetectionMetricValid=true(3,1);
T.DetectionUsable=true(3,1); T.ReceiverUsable=true(3,1);
T.PUCCHDecodeOk=true(3,1); T.UCIContentMatch=true(3,1);
T.ReceiverTimingOracleUsed=false(3,1); T.ReceiverZeroPaddingUsed=false(3,1);
T.ResourceExtractionAvailable=true(3,1); T.ControlResourceValidity=true(3,1);
T.ChannelEstimateAvailable=false(3,1); T.EqualizationAvailable=false(3,1);
T.CRCApplicable=false(3,1); T.CRCPass=nan(3,1); T.DTXFlag=false(3,1);
T.ReceiverOnlyAssignment=false(3,1); T.PUCCHTransmissionPrepared=true(3,1);
T.EvidenceClass=repmat("metadata_fixture_no_physical_qualification",3,1);
out=publish(T);
assert(all(out.StrictReceiverEvidenceOk & out.StrictOk) && all(out.Status=="PASS"), ...
    'test:Format0HARQEvidenceRejected', ...
    'Valid noncoherent Format-0 ACK, NACK and SR need no fabricated noise variance.');
assert(all(isnan(out.NoiseVariance)) && all(~out.CRCApplicable) && ...
    isequal(out.UCIDecodedBitVector,T.UCIDecodedBitVector));
assert(all(out.ReceiverUsable) && all(out.PUCCHDecodeOk));
assert(isequaln(publish(out),out),'Repeated evidence publication must be idempotent.');
% Each missing/contradictory proof remains a failure. The exception is only
% for the explicitly executed noncoherent, DMRS-free Format-0 algorithm.
bad=T(1,:); bad.PUCCHFormat=2; checkRejected(bad);
bad=T(1,:); bad.PUCCHDMRSRECount=8; checkRejected(bad);
bad=T(1,:); bad.PUCCHDMRSRECount=NaN; checkRejected(bad);
bad=T(1,:); bad.NoncoherentSequenceDetection=false; checkRejected(bad);
bad=T(1,:); bad.DetectionMetricValid=false; checkRejected(bad);
bad=T(1,:); bad.DetectionMetric=NaN; checkRejected(bad);
bad=T(1,:); bad.ReceiverTimingOracleUsed=true; checkRejected(bad);
bad=T(1,:); bad.ReceiverZeroPaddingUsed=true; checkRejected(bad);
bad=T(1,:); bad.NoiseVarStrictFailure=true; checkRejected(bad);
bad=T(1,:); bad.DecodeNoiseVarianceDomain="equalized_symbol"; checkRejected(bad);
bad=T(1,:); bad.ResourceExtractionAvailable=false; checkRejected(bad);
bad=T(1,:); bad.ControlResourceValidity=false; checkRejected(bad);
bad=T(1,:); bad.UCIContentMatch=false; bad.UCIDecodedBitVector="1";
bad.Status="FAIL"; checkRejected(bad);
fprintf('PUCCH_FORMAT0_EXPORT_EVIDENCE_PASS ACK_NACK_SR=3 negative_guards=13 RF_executions=0\n');
ok=true;
end

function out=publish(T)
out=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable("PUCCH",T);
end

function checkRejected(T)
out=publish(T);
assert(~out.StrictReceiverEvidenceOk && ~out.StrictOk && out.Status=="FAIL", ...
    'Incomplete or failed physical evidence must not be promoted to strict acceptance.');
assert(isequal(out.PUCCHDecodeOk,T.PUCCHDecodeOk), ...
    'Export failure must not rewrite the actual receiver result.');
end
