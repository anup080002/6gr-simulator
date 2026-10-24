function ok=testCSIRSPowerReference()
% Pure comparison + actual native OFDM arithmetic, NOT shared CSI reception.
% Support, columns and powers are declared component inputs. No test creates
% an accepted report, a shared isolation receipt or standardized accuracy.
% A clean-CDM counterexample explicitly prevents conflating that observable
% with independently isolated per-port power in a varying channel.
setup6GRSimToolkit('Verbose',false);
actions={@nativeOFDMScale,@selectionAndSignedPower,@normalizedPower, ...
    @operandGuards,@cleanCDMIsNotIndependentPortPower};
names=["native_OFDM_scale","selection_signed_power","normalized_units", ...
    "operand_guards","clean_CDM_counterexample"];
failures=strings(0,1);
for k=1:numel(actions)
    try
        actions{k}();
        fprintf('CSI_POWER_REFERENCE_GROUP_PASS %s\n',names(k));
    catch failure
        failures(end+1,1)=names(k)+": "+string(failure.identifier)+" "+string(failure.message); %#ok<AGROW>
        fprintf(2,'CSI_POWER_REFERENCE_GROUP_FAIL %s\n',failures(end));
    end
end
assert(isempty(failures),'test:CSIPowerReferenceFailed','%s',strjoin(failures,newline));
fprintf(['CSI_POWER_REFERENCE_PASS groups=%d native_OFDM=1 shared_owner=0 ' ...
    'receiver_decodes=0 multiport_attribution=0 standardized_accuracy=0\n'],numel(actions));
ok=true;
end

function nativeOFDMScale()
cases={6,15,'normal',0;12,30,'normal',1;6,60,'extended',3};
fftSizes=zeros(size(cases,1),1);
reference=[4 1 0]*1e-9;
measured=[2 5 -1]*1e-9;
for k=1:size(cases,1)
    carrier=nrCarrierConfig('NSizeGrid',cases{k,1},'SubcarrierSpacing',cases{k,2}, ...
        'CyclicPrefix',cases{k,3},'NSlot',cases{k,4});
    native=nrOFDMInfo(carrier);
    K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
    slot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
    lengths=double(native.SymbolLengths(slot*L+(1:L)));
    prefixes=double(native.CyclicPrefixLengths(slot*L+(1:L)));
    symbol=L-2; subcarrier=K/2+3; support=[subcarrier symbol];
    source=complex(zeros(K,L,3));
    source(subcarrier+1,symbol+1,:)=reshape(native.Nfft*sqrt(reference*1000),1,1,3);
    wave=nrOFDMModulate(carrier,source,'Windowing',0);
    grid=nrOFDMDemodulate(carrier,wave,'CyclicPrefixFraction',0.5);
    % Independent time-domain useful-symbol power, not the scorer's formula.
    first=sum(lengths(1:symbol))+prefixes(symbol+1)+1;
    useful=wave(first:first+native.Nfft-1,:);
    timePower=mean(abs(useful).^2,1)/1000;
    close(timePower,reference,1e-12);
    close(abs(reshape(grid(subcarrier+1,symbol+1,:),1,[])), ...
        native.Nfft*sqrt(reference*1000),1e-12);
    result=sixgr.phy.refsig.compareCSIRSPowerReference(grid,support,native.Nfft,measured,"sqrt_mW");
    close(result.ReferencePerReceiveColumn,timePower,1e-12);
    assert(result.LinearPowerUnit=="W" && result.NativeFFTSize==native.Nfft && ...
        result.ReferenceRECount==1 && result.ReceiveColumnCount==3);
    close(result.ReferencePower_dBm(1:2),10*log10(reference(1:2))+30,1e-12);
    assert(isinf(result.ReferencePower_dBm(3)) && result.ReferencePower_dBm(3)<0);
    twice=sixgr.phy.refsig.compareCSIRSPowerReference(2*grid,support,native.Nfft,measured,"sqrt_mW");
    close(twice.ReferencePerReceiveColumn,4*reference,1e-12);
    % A real raw native FFT of a unit impulse must have unit magnitude on
    % every occupied subcarrier in this FFT, independently of modulation.
    impulse=complex(zeros(sum(lengths),1));
    fftFirst=sum(lengths(1:symbol))+fix(prefixes(symbol+1)*0.5)+1;
    impulse(fftFirst)=1;
    response=nrOFDMDemodulate(carrier,impulse,'CyclicPrefixFraction',0.5);
    close(abs(response(:,symbol+1)),ones(K,1),1e-12);
    fftSizes(k)=native.Nfft;
    unqualified(result);
end
assert(numel(unique(fftSizes))>1,'test:CSIPowerNfftCoverage','Exercise genuinely different native FFT sizes.');
end

function selectionAndSignedPower()
grid=complex(zeros(4,2,3)); support=[0 0;3 1];
reference=[4 1 0];
for r=1:3
    grid(:,:,r)=sqrt(reference(r));
end
% Powers are declared normalized component inputs; no receive branch plane.
result=sixgr.phy.refsig.compareCSIRSPowerReference(grid,support,8,[2 5 -1],"normalized_complex_baseband");
assert(isequal(result.ReferencePerReceiveColumn,[4 1 0]) && ...
    isequal(result.MeasuredSignedPerReceiveColumn,[2 5 -1]) && ...
    isequal(result.LinearErrorPerReceiveColumn,[-2 4 -1]) && ...
    result.MeasuredSelectedColumn0==1 && result.ReferenceSelectedColumn0==0 && ...
    result.ReferenceAtMeasuredSelectedColumn==1);
close(result.ReportedError_dB,10*log10(5/4),1e-12);
close(result.MeasuredSelectedColumnError_dB,10*log10(5),1e-12);
assert(~result.PerReceiveColumnErrorDefined(3) && isnan(result.PerReceiveColumnError_dB(3)) && ...
    isnan(result.MeasuredLogPower_dB(3)) && result.ReferenceLogPower_dB(3)==-Inf);
allNonpositive=sixgr.phy.refsig.compareCSIRSPowerReference(grid,support,8,[0 -2 -1],"normalized_complex_baseband");
assert(~allNonpositive.MeasuredReportingAvailable && allNonpositive.MeasuredSignedMaximumPower==0 && ...
    isnan(allNonpositive.MeasuredReportedPower) && isnan(allNonpositive.MeasuredSelectedColumn0) && ...
    isnan(allNonpositive.ReferenceAtMeasuredSelectedColumn) && isnan(allNonpositive.ReportedError_dB) && ...
    all(isnan(allNonpositive.MeasuredLogPower_dB)) && ...
    isequal(allNonpositive.MeasuredSignedPerReceiveColumn,[0 -2 -1]));
zero=sixgr.phy.refsig.compareCSIRSPowerReference(zeros(size(grid)),support,8,[2 5 -1],"normalized_complex_baseband");
assert(zero.ReferenceMaximumPower==0 && all(zero.ReferenceLogPower_dB==-Inf) && ...
    isnan(zero.ReferenceSelectedColumn0) && isnan(zero.ReportedError_dB) && ...
    all(isnan(zero.PerReceiveColumnError_dB)) && zero.ReferenceAtMeasuredSelectedColumn==0);
reverse=sixgr.phy.refsig.compareCSIRSPowerReference(grid,flipud(support),8,[2 5 -1],"normalized_complex_baseband");
assert(isequaln(reverse,result),'test:CSIPowerSupportOrder','Unique support ordering must not alter power.');
unqualified(result);
end

function normalizedPower()
grid=complex(reshape(1:24,4,2,3)); support=[0 0;3 1]; measured=[1 2 3];
small=sixgr.phy.refsig.compareCSIRSPowerReference(grid,support,8,measured,"normalized_complex_baseband");
large=sixgr.phy.refsig.compareCSIRSPowerReference(grid,support,32,measured,"normalized_complex_baseband");
assert(isequal(small.ReferencePerReceiveColumn,large.ReferencePerReceiveColumn) && ...
    small.RawGridAmplitudeDivisor==1 && small.LinearPowerUnit=="unit_RE" && ...
    all(isnan(small.ReferencePower_dBm)) && all(isnan(small.MeasuredPower_dBm)));
absolute=sixgr.phy.refsig.compareCSIRSPowerReference(grid,support,8,measured,"sqrt_mW");
close(absolute.ReferencePerReceiveColumn,small.ReferencePerReceiveColumn/(8^2*1000),1e-12);
asSingle=sixgr.phy.refsig.compareCSIRSPowerReference(single(grid),support,8,measured,"normalized_complex_baseband");
assert(isequal(asSingle.ReferencePerReceiveColumn,small.ReferencePerReceiveColumn));
unqualified(small);
end

function operandGuards()
grid=ones(4,2,2); support=[0 0;3 1]; measured=[1 -2];
call=@(g,s,n,m,u)sixgr.phy.refsig.compareCSIRSPowerReference(g,s,n,m,u);
id='sixgr:refsig:CSIRSPowerReferenceOperands';
mustReject(@()call(grid,[support;support(1,:)],8,measured,"sqrt_mW"),id);
mustReject(@()call(grid,[4 0],8,measured,"sqrt_mW"),id);
mustReject(@()call(grid,[0 2],8,measured,"sqrt_mW"),id);
mustReject(@()call(grid,[0.5 0],8,measured,"sqrt_mW"),id);
mustReject(@()call(grid,[-1 0],8,measured,"sqrt_mW"),id);
mustReject(@()call(grid,zeros(0,2),8,measured,"sqrt_mW"),id);
mustReject(@()call(grid,[0 0 0],8,measured,"sqrt_mW"),id);
for n=[0 3 8.5 Inf NaN]
    mustReject(@()call(grid,support,n,measured,"sqrt_mW"),id);
end
mustReject(@()call(grid,support,8,1,"sqrt_mW"),id);
mustReject(@()call(grid,support,8,[1 NaN],"sqrt_mW"),id);
mustReject(@()call(grid,support,8,[1 Inf],"sqrt_mW"),id);
mustReject(@()call(grid,support,8,[1 2i],"sqrt_mW"),id);
mustReject(@()call(ones(4,2,2,2),support,8,measured,"sqrt_mW"),id);
bad=grid; bad(1)=NaN;
mustReject(@()call(bad,support,8,measured,"sqrt_mW"),id);
mustReject(@()call(grid,support,8,measured,"sqrt_W"),'sixgr:refsig:CSIRSPowerReferenceUnit');
mustReject(@()call(grid,support,8,measured,""),'sixgr:refsig:CSIRSPowerReferenceUnit');
mustReject(@()call(grid,support,8,measured,string(missing)),'sixgr:refsig:CSIRSPowerReferenceUnit');
mustReject(@()call(grid,support,8,measured,["sqrt_mW","sqrt_mW"]),'sixgr:refsig:CSIRSPowerReferenceUnit');
end

function cleanCDMIsNotIndependentPortPower()
% Declared two-port orthogonal pilot component; channel varies over one tile.
% The actual noiseless port-3000 contribution has power one, but despreading
% the clean composite gives zero. Neither noise nor another port is required
% for this counterexample, so a clean estimator rerun cannot prove accuracy.
carrier=nrCarrierConfig('NSizeGrid',1);
reference=complex(zeros(12,14,2));
reference(1:2,1,1)=[1;1]; reference(1:2,1,2)=[1;-1];
isolated=complex(zeros(12,14)); isolated(1:2,1)=[1;-1];
cdm=sixgr.phy.refsig.measureCSIRSCDMPortPower(carrier,reference,isolated,[2 1],0);
direct=sixgr.phy.refsig.compareCSIRSPowerReference(isolated,[0 0;1 0],16, ...
    cdm.SignedPort3000PowerPerBranch,"normalized_complex_baseband");
assert(cdm.RawPort3000PowerPerBranch==0 && direct.ReferencePerReceiveColumn==1 && ...
    direct.MeasuredSignedPerReceiveColumn==0 && ~direct.MeasuredReportingAvailable && ...
    isnan(direct.ReportedError_dB));
% Nonlinear F(x0+x1) also has no additive F(x0)+F(x1) attribution in general.
x0=[1;1]; x1=[1;-1]; F=@(x)x.*abs(x).^2;
assert(~isequal(F(x0+x1),F(x0)+F(x1)));
unqualified(direct);
end

function unqualified(result)
assert(result.PowerComparisonPerformed && ~result.MeasuredPowerClipped && ...
    ~result.SharedOwnerBound && ~result.ComponentIsolationProved && ...
    ~result.IndependentPortAttributionProved && ~result.StandardizedRSRPAccuracyQualified && ...
    ~result.HardwareQualified && result.ReferencePlane=="caller_supplied_not_established_by_arithmetic");
end

function close(actual,expected,tolerance)
assert(isequal(size(actual),size(expected)) && ...
    all(abs(actual-expected)<=tolerance*max(abs(expected),realmin),'all'), ...
    'test:CSIPowerArithmetic','Native/reference power arithmetic mismatch.');
end

function mustReject(action,id)
try
    action();
catch failure
    assert(strcmp(failure.identifier,id),'test:CSIPowerWrongError','Expected %s, got %s.',id,failure.identifier);
    return;
end
error('test:CSIPowerMissingError','Expected %s.',id);
end
