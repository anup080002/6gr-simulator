function ok = testMsg2RARWaveformDecode()
res = raStrictAnchorSuccessResult();
assert(logical(res.Msg2RARNTIDetected), "UE must decode RA-RNTI PDCCH for MSG2.");
assert(logical(res.Msg2PDSCHCrcPass), "UE must decode RAR PDSCH/DL-SCH.");
assert(logical(res.RAPIDMatches), "Decoded RAPID must match MSG1 preamble.");
assert(logical(res.RARULGrantValid), "Decoded RAR UL grant must validate.");
assert(strlength(string(res.RARBytesHex)) > 0, "RAR bytes must be exported as hex.");
ok = true;
end
