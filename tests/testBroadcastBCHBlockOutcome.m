function ok=testBroadcastBCHBlockOutcome(originalResult)
% Declared operand integrity fixture; optional original receiver result is
% checked separately without rerunning PHY or altering historical evidence.
setup6GRSimToolkit('Verbose',false);
bits=uint8(mod((0:23)',3)==1);
r=struct('DecodeAttempted',true,'BCHCRCValid',true,'BCHTransportBlockNumBits',24, ...
    'BCHTransportBlockHex',sixgr.rrc.asn1.bitsToHex(bits), ...
    'BCHTransportBlockHash',sixgr.rrc.asn1.asn1SHA256Hex(bits), ...
    'StrictOk',false,'Crash',true,'CandidateIdentityConsistent',false, ...
    'DCICrcPass',false,'DLSCHCrcPass',false,'SIB1ASN1DecodeOk',false);
original=r;
pass=sixgr.link.broadcastBCHBlockOutcome(r);
assert(pass.Eligible && pass.BlockError==0 && ...
    pass.Source=="original_completed_BCH_decode_raw_CRC");
r.BCHCRCValid=false; fail=sixgr.link.broadcastBCHBlockOutcome(r);
assert(fail.Eligible && fail.BlockError==1);
% Later SI success/failure, candidate identity, or exceptions cannot change
% an already returned BCH CRC. This is not accepted-MIB qualification.
r=original; r.StrictOk=true; r.Crash=false; r.CandidateIdentityConsistent=true;
assert(isequaln(sixgr.link.broadcastBCHBlockOutcome(r),pass));
for mutation=["missing_attempt","not_attempted","numeric_attempt","vector_attempt", ...
        "missing_crc","nan_crc","numeric_crc","vector_crc","missing_bits", ...
        "wrong_count","text_count","complex_count","missing_hex","short_hex", ...
        "numeric_hex","bad_hex","wrong_hash","missing_hash","numeric_hash","vector_hash"]
    bad=original;
    switch mutation
        case "missing_attempt", bad=rmfield(bad,'DecodeAttempted');
        case "not_attempted", bad.DecodeAttempted=false; bad.BCHTransportBlockNumBits=NaN;
        case "numeric_attempt", bad.DecodeAttempted=1;
        case "vector_attempt", bad.DecodeAttempted=[true true];
        case "missing_crc", bad=rmfield(bad,'BCHCRCValid');
        case "nan_crc", bad.BCHCRCValid=NaN;
        case "numeric_crc", bad.BCHCRCValid=0;
        case "vector_crc", bad.BCHCRCValid=[true false];
        case "missing_bits", bad=rmfield(bad,'BCHTransportBlockNumBits');
        case "wrong_count", bad.BCHTransportBlockNumBits=23;
        case "text_count", bad.BCHTransportBlockNumBits='24';
        case "complex_count", bad.BCHTransportBlockNumBits=24+1i;
        case "missing_hex", bad=rmfield(bad,'BCHTransportBlockHex');
        case "short_hex", bad.BCHTransportBlockHex="12345";
        case "numeric_hex", bad.BCHTransportBlockHex=123456;
        case "bad_hex", bad.BCHTransportBlockHex="ZZZZZZ";
        case "wrong_hash", bad.BCHTransportBlockHash=string(repmat('0',1,64));
        case "missing_hash", bad=rmfield(bad,'BCHTransportBlockHash');
        case "numeric_hash", bad.BCHTransportBlockHash=ones(1,64);
        case "vector_hash", bad.BCHTransportBlockHash=[original.BCHTransportBlockHash;original.BCHTransportBlockHash];
    end
    if startsWith(mutation,"missing_") || any(mutation==["not_attempted","nan_crc"])
        v=sixgr.link.broadcastBCHBlockOutcome(bad);
        assert(~v.Eligible && isnan(v.BlockError) && v.Source=="unavailable",mutation);
    else
        localReject(bad);
    end
end
v=sixgr.link.broadcastBCHBlockOutcome(struct()); assert(~v.Eligible&&isnan(v.BlockError));
localReject([]);
bad=original; bad.DecodeAttempted=false; localReject(bad);
bad=original; bad.BCHTransportBlockHex="";
v=sixgr.link.broadcastBCHBlockOutcome(bad); assert(~v.Eligible&&isnan(v.BlockError));
if nargin>0
    saved=originalResult;
    v=sixgr.link.broadcastBCHBlockOutcome(originalResult);
    assert(v.Eligible && v.BlockError==double(~originalResult.BCHCRCValid));
    assert(isequaln(saved,originalResult));
    fprintf('BCH_BLOCK_OUTCOME_RETAINED_ORIGINAL_PASS no_new_PHY\n');
end
fprintf('BCH_BLOCK_OUTCOME_PASS declared_raw_operands_20_negatives no_PHY_or_statistics\n');
ok=true;
end

function localReject(r)
try, sixgr.link.broadcastBCHBlockOutcome(r); catch ex
    assert(strcmp(ex.identifier,'sixgr:link:InvalidBCHBlockEvidence'), ...
        'Unexpected rejection %s: %s',ex.identifier,ex.message);
    return;
end
error('test:ExpectedBCHEvidenceRejection','Malformed or contradictory evidence was accepted.');
end
