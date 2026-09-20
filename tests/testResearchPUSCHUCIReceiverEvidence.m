function ok=testResearchPUSCHUCIReceiverEvidence()
% Actual coding/decoding and reducer contract, not physical qualification.
setup6GRSimToolkit('Verbose',false);
for count=[0 1 2 7 12 20]
    bits=int8(mod((1:count)',2)); llr=[];
    if count>0
        coded=sixgr.phy.research.encodePUSCHUCI(bits,600,'1024QAM');
        coded(coded==-1)=1;
        repeated=find(coded==-2); coded(repeated)=coded(repeated-1);
        symbols=nrSymbolModulate(coded,'1024QAM');
        llr=nrSymbolDemodulate(symbols,'1024QAM',.001);
    end
    [decoded,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,count,'1024QAM');
    [usable,crc]=sixgr.truth.puschUCIFieldUsable(e,decoded,count);
    assert(isequal(decoded,bits) && usable && ~e.StandardNR);
    if count<12, assert(isnan(crc)); else, assert(crc==1); end
    bad=e; bad.Source="nrUCIDecode_received_LLR_and_code_block_error_flags";
    localReject(@()sixgr.truth.puschUCIFieldUsable(bad,decoded,count));
    bad=e; bad.StandardNR=true;
    localReject(@()sixgr.truth.puschUCIFieldUsable(bad,decoded,count));
    bad=rmfield(e,'ResearchClass');
    localReject(@()sixgr.truth.puschUCIFieldUsable(bad,decoded,count));
end
[bits,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(zeros(600,1),1,'1024QAM');
e.DecodeUsable=true;
assert(~sixgr.truth.puschUCIFieldUsable(e,bits,1), ...
    'An experimental source tag cannot override missing short-UCI confidence.');
ok=true;
fprintf('RESEARCH_PUSCH_UCI_RECEIVER_EVIDENCE_PASS counts=0,1,2,7,12,20 relabeling_rejected=1\n');
end

function localReject(fn)
try, fn(); catch ME, assert(strcmp(ME.identifier,'sixgr:truth:InvalidPUSCHUCIReceiverEvidence')); return; end
error('test:MissingRejection','Invalid experimental decoder authority must fail closed.');
end
