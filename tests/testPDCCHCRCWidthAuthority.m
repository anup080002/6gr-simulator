function ok=testPDCCHCRCWidthAuthority()
% NR DCI CRC24C is distinct from its 16-bit RNTI mask (38.212 7.3.2).
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
s=source.toStruct();
bad=s; bad.pdcch.crc_length=16;
rejected=false;
try
    sixgr.lls6g.buildInternalConfig(bad,tempname);
catch ex
    rejected=strcmp(ex.identifier,'sixgr:phy:pdcch:InvalidNRCRCDeclaration');
end
assert(rejected,'test:PDCCHCRCDeclarationIgnored', ...
    'An explicit 16-bit NR DCI CRC declaration must be rejected, not silently ignored.');
assert(s.pdcch.crc_length==24,'The resolved H4 YAML must declare the executed NR CRC width.');
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
assert(cfg.phy.pdcch.crcLength==24 && cfg.phy.pdcch.rntiMaskLength==16 && ...
    string(cfg.phy.pdcch.crcPolynomial)=="CRC24C");
% H4 is a runtime scenario, not a standalone statistical detector campaign.
% Exercise that separate builder with its explicitly authored mini-campaign.
campaign=sixgr.lls6g.config.loadScenarioConfig('configs/lls/lls_pdcch_strict_mini_anchor.yaml');
campaignCfg=sixgr.lls6g.buildInternalConfig(campaign,tempname);
strict=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(campaignCfg);
assert(strict.CRCLength==24 && strict.RNTIMaskLength==16 && ...
    strict.CRCPolynomial=="CRC24C");
for invalid={16,NaN,[],[24 24],"24",24.5}
    broken=campaignCfg; broken.phy.pdcch.crcLength=invalid{1};
    rejected=false;
    try
        sixgr.phy.pdcch.buildPDCCHConfigFromScenario(broken);
    catch ex
        rejected=strcmp(ex.identifier,'sixgr:phy:pdcch:InvalidNRCRCDeclaration');
    end
    assert(rejected,'Runtime NR PDCCH must not accept malformed or mismatching CRC declarations.');
    for side=["TX","RX"]
        rejected=false;
        try
            if side=="TX"
                sixgr.phy.dl.PDCCH_Tx(broken);
            else
                sixgr.phy.dl.PDCCH_Rx(zeros(1,1),broken);
            end
        catch ex
            rejected=strcmp(ex.identifier,'sixgr:phy:pdcch:InvalidNRCRCDeclaration');
        end
        assert(rejected,'Direct core TX/RX calls must preserve the same CRC-width guard.');
    end
end
profile=sixgr.phy.pdcch.PDCCHSpecificationProfile.describe();
assert(profile.CRCLength==24 && profile.RNTIMaskLength==16);
bits=int8(mod((0:63).',3)==0); rnti=4660;
for al=[1 2 4 8 16]
    [cw,maskedCRC]=nrDCIEncode(bits,rnti,108*al);
    % MATLAB returns the 24 CRC bits as one MSB-first decimal integer.
    [~,unmaskedCRC]=nrDCIEncode(bits,0,108*al);
    crcBits=nrCRCEncode([ones(24,1,'int8');bits],'24C',rnti);
    expectedCRC=sum(double(crcBits(end-23:end)).*2.^(23:-1:0).');
    assert(maskedCRC==expectedCRC && maskedCRC<2^24 && numel(cw)==108*al && ...
        bitxor(uint32(maskedCRC),uint32(unmaskedCRC))==uint32(rnti));
    [decoded,crc]=nrDCIDecode(20*(1-2*double(cw)),numel(bits),8,rnti);
    assert(crc==0 && isequal(int8(decoded),bits));
end
ok=true;
end
