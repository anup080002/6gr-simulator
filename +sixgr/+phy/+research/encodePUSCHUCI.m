function coded=encodePUSCHUCI(bits,E,modulation)
% Public NR coding primitives plus explicit experimental Qm=10 short UCI.
% The one/two-bit mother code keeps its two informative positions per QAM
% symbol; remaining positions are x placeholders, not payload or zero bits.
validateattributes(bits,{'numeric','logical'},{'vector','real','finite','nonempty'});
assert(all(ismember(bits,[0 1])),'sixgr:research:NonBinaryUCI','UCI must be binary.');
validateattributes(E,{'numeric'},{'scalar','real','finite','integer','positive'});
bits=int8(bits(:)); modulation=string(modulation);
if modulation~="1024QAM" || numel(bits)>2
    coded=int8(nrUCIEncode(bits,E,char(modulation)));
    return;
end
periodSymbols=1+2*(numel(bits)==2);
mother=reshape(nrUCIEncode(bits,2*periodSymbols,'QPSK'),2,periodSymbols);
extended=-ones(10,periodSymbols,'int8');
extended(1:2,:)=mother;
period=extended(:);
coded=period(mod((0:E-1).',numel(period))+1);
end
