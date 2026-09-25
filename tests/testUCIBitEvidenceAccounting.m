function ok=testUCIBitEvidenceAccounting()
% Bit substitutions require paired bit positions, never padded erasures.
ref=int8([0;1;0;1]);
e=sixgr.link.compareUCIBitEvidence(ref,int8([0;0;0;1]));
assert(e.BitsCompared==4 && e.BitErrors==1 && e.ContentMismatch && e.UCIBitErrorVector=="0100");
e=sixgr.link.compareUCIBitEvidence(ref,ref);
assert(e.BitsCompared==4 && e.BitErrors==0 && ~e.ContentMismatch);
for decoded={int8([]),ref(1:3),[ref;int8(0)]}
    e=sixgr.link.compareUCIBitEvidence(ref,decoded{1});
    assert(e.BitsCompared==0 && isnan(e.BitErrors) && e.ContentMismatch && strlength(e.UCIBitErrorVector)==0);
end
for decoded={int8([]),ref}
    e=sixgr.link.compareUCIBitEvidence(int8([]),decoded{1});
    assert(e.BitsCompared==0 && isnan(e.BitErrors) && e.BitComparisonStatus=="unavailable_no_transmitted_bits");
end
fprintf('UCI_BIT_EVIDENCE_ACCOUNTING_PASS no_erasure_as_bit_error no_blind_prefix\n');
ok=true;
end
