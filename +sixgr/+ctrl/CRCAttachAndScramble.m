function out = CRCAttachAndScramble(infoBits, ctrlCfg)
%CRCAttachAndScramble Attach control CRC and optionally scramble it by RNTI.

mask = [];
if ctrlCfg.CRCScramblingEnabled
    mask = double(ctrlCfg.RNTI);
end

blkcrc = sixgr.phy.tb.attachCRC(infoBits(:), ctrlCfg.CRCPolynomial, mask);
out = struct();
out.InputBits = int8(infoBits(:));
out.BitsWithCRC = int8(blkcrc(:));
out.CRCScramblingEnabled = logical(ctrlCfg.CRCScramblingEnabled);
out.CRCMask = double(ctrlCfg.RNTI) * double(ctrlCfg.CRCScramblingEnabled);
out.CRCPolynomial = ctrlCfg.CRCPolynomial;
end
