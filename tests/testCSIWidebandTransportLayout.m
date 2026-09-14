function ok=testCSIWidebandTransportLayout()
% Independent literal TS 38.212 wideband bit-order vectors, not RF evidence.
setup6GRSimToolkit('Verbose',false);
cases=0;
for withLI=[false true]
 for rank=[1 2]
  request=struct('ReportConfigID',"wideband_wire_fixture",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',rank,'MaxRank',2, ...
    'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',4, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUCCH");
  if withLI, request.ReportQuantity="cri-RI-LI-PMI-CQI"; end
  values=struct('CRI',2,'RI',rank,'CQI_CW0',9,'PMI',0,'LI',rank-1);
  if rank==1, values.PMI=3; end
  pucch=sixgr.phy.mimo.CSIReportConfiguration(request,0);
  encoded=pucch.build(values);
  expected="100111001";
  if rank==2
      expected="101001001";
      if withLI, expected="101101001"; end
  end
  assert(isequal(encoded.Part1Bits,localBits(expected)) && isempty(encoded.Part2Bits));
  assert(~encoded.SeparateEncoding && pucch.part1BitCount()==9);
  request.Rank=3-rank;
  rx=sixgr.phy.mimo.CSIReportConfiguration(request,0);
  decoded=rx.decode(encoded.Part1Bits,int8([]));
  assert(decoded.RI==rank && decoded.PMI==values.PMI && decoded.CQI_CW0==9);
  assert(isfield(decoded,'LI')==withLI);
  [puschBits,pusch]=rx.transcode(encoded.Part1Bits,int8([]),"PUSCH");
  expectedPart1="1001001"; expectedPart2="11";
  if rank==2
      expectedPart1="1011001"; expectedPart2="0";
      if withLI, expectedPart2="10"; end
  end
  assert(isequal(puschBits.Part1Bits,localBits(expectedPart1)) && ...
      isequal(puschBits.Part2Bits,localBits(expectedPart2)));
  [back,~]=pusch.transcode(puschBits.Part1Bits,puschBits.Part2Bits,"PUCCH");
  assert(isequal(back.Part1Bits,encoded.Part1Bits) && isempty(back.Part2Bits));
  if rank==2 && ~withLI
      bad=encoded.Part1Bits; bad(4)=1;
      localReject(@()rx.decode(bad,int8([])),'sixgr:mimo:InvalidCSIPadding');
  end
  cases=cases+2;
 end
end
% A singleton configured rank set uses zero RI bits, including fixed RI=2.
request.AllowedRanks=2; request.Rank=2; request.ReportQuantity="cri-RI-PMI-CQI";
restricted=sixgr.phy.mimo.CSIReportConfiguration(request,0);
encoded=restricted.build(struct('RI',2,'CRI',2,'PMI',0,'CQI_CW0',9));
assert(isequal(encoded.Part1Bits,localBits("1001001")));
decoded=restricted.decode(encoded.Part1Bits,encoded.Part2Bits);
assert(decoded.RI==2);
request.Rank=1;
localReject(@()sixgr.phy.mimo.CSIReportConfiguration(request,0),'sixgr:mimo:InvalidRI');
% Higher-port X1/X2 order and LI-before-PMI, from the same normative tables.
request=rmfield(request,'AllowedRanks'); request.Ports=4; request.Rank=2;
request.N1=2; request.N2=1; request.O1=4; request.O2=1; request.CodebookMode=1;
config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
values=struct('CRI',2,'RI',2,'CQI_CW0',9,'LI',1,'PMI_I11',3,'PMI_I13',1,'PMI_I2',1);
encoded=config.build(values);
assert(isequal(encoded.Part1Bits,localBits("101011111001")));
[pusch,~]=config.transcode(encoded.Part1Bits,encoded.Part2Bits,"PUSCH");
assert(isequal(pusch.Part2Bits,localBits("01111")));
request.ReportQuantity="cri-RI-LI-PMI-CQI";
config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
encoded=config.build(values);
assert(isequal(encoded.Part1Bits,localBits("1011011111001")));
[pusch,~]=config.transcode(encoded.Part1Bits,encoded.Part2Bits,"PUSCH");
assert(isequal(pusch.Part2Bits,localBits("101111")));
% TS 38.214 5.2.1.4.2: i1-only reporting is not full PMI; omit i2/LI.
request.ReportQuantity="cri-RI-i1-CQI";
config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
encoded=config.build(values);
assert(isequal(encoded.Part1Bits,localBits("10101111001")));
[pusch,puschConfig]=config.transcode(encoded.Part1Bits,encoded.Part2Bits,"PUSCH");
assert(isequal(pusch.Part2Bits,localBits("0111")));
decoded=puschConfig.decode(pusch.Part1Bits,pusch.Part2Bits);
assert(decoded.PMI_I11==3 && decoded.PMI_I13==1 && ...
    ~isfield(decoded,'PMI_I2') && ~isfield(decoded,'PMI') && ~isfield(decoded,'LI'));
% cri-RI-CQI uses physical rank-minus-one (fixed port-dependent width),
% not the restricted codebook ordinal, even if only one rank is allowed.
request.ReportQuantity="cri-RI-CQI"; request.AllowedRanks=2;
config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
encoded=config.build(values);
assert(isequal(encoded.Part1Bits,localBits("10011001")));
assert(config.decode(encoded.Part1Bits,encoded.Part2Bits).RI==2);
bad=encoded.Part1Bits; bad(3:4)=int8([1;0]);
localReject(@()config.decode(bad,encoded.Part2Bits),'sixgr:mimo:InvalidRI');
cases=cases+7;
% CRI uses ceil(log2(N)) bits but only N of those values name resources.
% Cover both transports, every valid value and every spare value for these
% cardinalities. The bit strings below use MATLAB dec2bin, not the serializer.
for channel=["PUCCH","PUSCH"]
 for count=[1 2 3 5 6 7 8 16 31 32 33 63 64]
    request=struct('ReportConfigID',"cri_domain_fixture",'Epoch',0, ...
        'CodebookType',"typeI-SinglePanel",'Ports',1,'Rank',1,'MaxRank',1, ...
        'ReportQuantity',"cri-CQI",'NumCSIResources',count, ...
        'FrequencyGranularity',"wideband",'UCIChannel',channel);
    config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    width=ceil(log2(count));
    for cri=0:2^width-1
        criBits=zeros(0,1,'int8');
        if width>0, criBits=int8(dec2bin(cri,width).'-'0'); end
        bits=[criBits;int8([1;0;0;1])];
        values=struct('CRI',cri,'CQI_CW0',9);
        if cri<count
            encoded=config.build(values);
            assert(isequal(encoded.Part1Bits,bits));
            decoded=config.decode(bits,int8([]));
            assert(decoded.CRI==cri && decoded.CQI_CW0==9);
        else
            localReject(@()config.build(values),'sixgr:mimo:InvalidCRI');
            localReject(@()config.decodePart1(bits),'sixgr:mimo:InvalidCRI');
            localReject(@()config.decode(bits,int8([])),'sixgr:mimo:InvalidCRI');
        end
    end
    for invalid={-1,count,0.5,NaN,Inf,1i,'0'}
        values=struct('CRI',invalid{1},'CQI_CW0',9);
        localReject(@()config.build(values),'sixgr:mimo:InvalidCRI');
    end
    if count==1
        encoded=config.build(struct('CQI_CW0',9));
        assert(isequal(encoded.Part1Bits,int8([1;0;0;1])), ...
            'The single configured resource uses zero CRI bits, not a fabricated measurement.');
    end
 end
end
ok=true; fprintf('CSI_WIDEBAND_WIRE_FORMAT_PASS literal_cases=%d plus padding/rank guards\n',cases);
end

function bits=localBits(token)
bits=int8(char(token).'-'0');
end

function localReject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s.',id,err.identifier); return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
