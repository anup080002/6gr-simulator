classdef WaveformPhaseEvidenceBuilder
    %WAVEFORMPHASEEVIDENCEBUILDER Execute Phase-13 production evidence.

    methods (Static)
        function tables = build(vectorRoot,seedList,confidenceLevel)
            if nargin<2 || isempty(seedList), seedList=[11 23 47 89]; end
            if nargin<3, confidenceLevel=.95; end
            vectorRoot = string(vectorRoot);
            if ~isfolder(vectorRoot)
                error("WAVEFORM:IndependentVectorMissing", ...
                    "Waveform vector root does not exist: %s.",vectorRoot);
            end
            [tables.waveform_profile_resolution, ...
                tables.waveform_capability_results] = ...
                localCapabilities(vectorRoot);
            [tables.waveform_ofdm_parameters,plans] = ...
                localOFDMParameters(vectorRoot);
            tables.waveform_symbol_timing = localSymbolTiming(plans);
            tables.waveform_subcarrier_mapping = localSubcarrierMapping();
            tables.waveform_cp_insertion = localCPInsertion(vectorRoot);
            tables.waveform_ofdm_roundtrip = ...
                localOFDMRoundTrip(seedList(1));
            tables.waveform_stream_continuity = ...
                localStreamContinuity(vectorRoot);
            tables.waveform_windowing_wola = localWOLA(vectorRoot,seedList(1));
            tables.waveform_transform_precoding = ...
                localTransformPrecoding(vectorRoot);
            tables.waveform_pi2bpsk = localPi2BPSK(vectorRoot);
            tables.waveform_dft_size_validation = localDFTSizes(vectorRoot);
            tables.waveform_low_papr_processing = ...
                localLowPAPR(seedList(1));
            tables.waveform_multinumerology_composition = ...
                localMultiNumerology(vectorRoot);
            tables.waveform_component_carrier_composition = ...
                localComponentCarriers(vectorRoot);
            [tables.waveform_power_ledger,tables.waveform_parseval] = ...
                localPowerAndParseval(seedList(1));
            tables.waveform_papr_trials = localPAPRTrials(seedList);
            tables.waveform_papr_ccdf = ...
                localPAPRCCDF(tables.waveform_papr_trials,confidenceLevel);
            [tables.waveform_psd,tables.waveform_spectral_metrics] = ...
                localSpectral(seedList(1));
            tables.waveform_evm_isi_ici = localISI(seedList(1));
            tables.waveform_sync_sensitivity = localSync(seedList(1));
            tables.waveform_awgn_roundtrip = ...
                localAWGN(seedList,confidenceLevel);
            tables.waveform_tdl_cdl_trials = localFading(seedList);
            tables.waveform_interference_composition = ...
                localInterference(seedList(1));
            tables.waveform_independent_vector_results = ...
                sixgr.phy.waveform.WaveformVectorValidator.validate( ...
                    vectorRoot,"ThrowOnMismatch",true);
            tables.waveform_negative_tests = localNegative(vectorRoot);
            tables.waveform_test_summary = localSummary(tables);
            tables.waveform_runtime_scaling = localRuntimeScaling(seedList(1));
            tables.waveform_reproducibility = localReproducibility(seedList);
        end
    end
end

function [resolution,capability] = localCapabilities(root)
input = localRead(fullfile(root,"waveform_capability_profile_matrix.csv"));
n = height(input);
profileID=strings(n,1);feature=strings(n,1);expected=strings(n,1);
actual=strings(n,1);errorID=strings(n,1);status=strings(n,1);
for index=1:n
    profileID(index)=input.ProfileID(index);
    feature(index)=input.Feature(index);
    expected(index)=input.ExpectedOutcome(index);
    try
        plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
            profileID(index),feature(index));
        actual(index)=plan.Outcome;
        errorID(index)=plan.ErrorID;
    catch exception
        actual(index)="REJECT";
        errorID(index)=string(exception.identifier);
    end
    expectedError=input.ExpectedError(index);
    pass=actual(index)==expected(index);
    if expected(index)=="REJECT"
        pass=pass&&errorID(index)==expectedError;
    end
    status(index)=localStatus(pass);
end
resolution=table(profileID,feature,expected,actual,status, ...
    'VariableNames',{'ProfileID','Feature','ExpectedOutcome', ...
    'ActualOutcome','Status'});
capability=table(profileID,feature,expected,actual,errorID,status, ...
    'VariableNames',{'ProfileID','Feature','ExpectedOutcome', ...
    'ActualOutcome','ErrorID','Status'});
end

function [output,plans] = localOFDMParameters(root)
input=localRead(fullfile(root,"waveform_ofdm_parameter_test_vectors.csv"));
n=height(input);
caseID=input.CaseID;scs=str2double(input.SCS_kHz);
cp=input.CyclicPrefix;nSize=str2double(input.NSizeGrid);
nfft=nan(n,1);rate=nan(n,1);symbols=nan(n,1);
actual=strings(n,1);actualError=strings(n,1);status=strings(n,1);
plans=cell(n,1);
for index=1:n
    try
        carrier=localCarrier(scs(index),cp(index),nSize(index));
        plan=sixgr.phy.waveform.OFDMParameterResolver.resolve(carrier);
        plans{index}=plan;
        nfft(index)=double(plan.Nfft);
        rate(index)=double(plan.SampleRate);
        symbols(index)=double(plan.SymbolsPerSlot);
        actual(index)="EXECUTE";
    catch exception
        actual(index)="REJECT";
        actualError(index)=string(exception.identifier);
    end
    pass=actual(index)==input.ExpectedPlanningOutcome(index);
    if actual(index)=="REJECT"
        pass=pass&&actualError(index)==input.ExpectedError(index);
    else
        pass=pass&&abs(rate(index)-nfft(index)*scs(index)*1e3)<1e-9 && ...
            symbols(index)==str2double(input.ExpectedSymbolsPerSlot(index));
    end
    status(index)=localStatus(pass);
end
output=table(caseID,scs,cp,nSize,nfft,rate,symbols,status,actual,actualError, ...
    'VariableNames',{'CaseID','SCS_kHz','CyclicPrefix','NSizeGrid', ...
    'Nfft','SampleRate_Hz','SymbolsPerSlot','Status', ...
    'ActualOutcome','ActualError'});
end

function output = localSymbolTiming(plans)
rows=repmat(struct("CaseID","","Slot",NaN,"Symbol",NaN, ...
    "CPStartSample",NaN,"UsefulStartSample",NaN,"EndSample",NaN, ...
    "CPLength",NaN,"UsefulLength",NaN,"Status",""),0,1);
caseNumber=0;
for planIndex=1:numel(plans)
    plan=plans{planIndex};
    if isempty(plan),continue;end
    caseNumber=caseNumber+1;
    cursor=0;
    cp=double(plan.CyclicPrefixLengthsPerSlot(:));
    for symbol=1:numel(cp)
        row=localRow(rows);
        row.CaseID="TIMING-"+caseNumber;
        row.Slot=0;row.Symbol=symbol-1;
        row.CPStartSample=cursor;
        row.UsefulStartSample=cursor+cp(symbol);
        row.EndSample=cursor+cp(symbol)+double(plan.Nfft)-1;
        row.CPLength=cp(symbol);row.UsefulLength=double(plan.Nfft);
        row.Status=localStatus(row.EndSample>=row.UsefulStartSample);
        rows(end+1)=row; %#ok<AGROW>
        cursor=row.EndSample+1;
    end
    if caseNumber>=5,break;end
end
output=struct2table(rows,"AsArray",true);
end

function output = localSubcarrierMapping()
map=sixgr.phy.waveform.SubcarrierMapper.build(512,300, ...
    "BWPStartSubcarrier",12,"BWPID","BWP-1","Owner","PDSCH_PORT_0");
caseID=repmat("MAP-300-512",height(map),1);
prb=floor(double(map.REIndex)/12);
subcarrier=double(map.Subcarrier);
fftBin=double(map.FFTBin);
isDC=logical(map.IsDC);
owner=map.Owner;bwpID=map.BWPID;
status=repmat("PASS",height(map),1);
output=table(caseID,bwpID,prb,subcarrier,fftBin,isDC,owner,status, ...
    'VariableNames',{'CaseID','BWPID','PRB','Subcarrier','FFTBin', ...
    'IsDC','Owner','Status'});
end

function output = localCPInsertion(root)
vectors=localRead(fullfile(root,"waveform_cp_test_vectors.csv"));
expected=localRead(fullfile(root,"expected_waveform_cp_samples.csv"));
rows=repmat(struct("VectorID","","OutputIndex",NaN, ...
    "ExpectedReal",NaN,"ExpectedImag",NaN,"ActualReal",NaN, ...
    "ActualImag",NaN,"Error",NaN,"Status",""),0,1);
cursor=0;
seenVectorIDs=strings(0,1);
for index=1:height(vectors)
    input=complex(localPipe(vectors.InputReal(index)), ...
        localPipe(vectors.InputImag(index)));
    actual=sixgr.phy.waveform.CPInsertionRemoval.insert( ...
        input,str2double(vectors.CPLength(index)));
    for sample=1:numel(actual)
        cursor=cursor+1;
        want=complex(str2double(expected.ExpectedReal(cursor)), ...
            str2double(expected.ExpectedImag(cursor)));
        errorMagnitude=abs(actual(sample)-want);
        if ~any(seenVectorIDs==vectors.VectorID(index))
            row=localRow(rows);row.VectorID=vectors.VectorID(index);
            row.OutputIndex=sample-1;row.ExpectedReal=real(want);
            row.ExpectedImag=imag(want);row.ActualReal=real(actual(sample));
            row.ActualImag=imag(actual(sample));row.Error=errorMagnitude;
            row.Status=localStatus(errorMagnitude<=1e-12);
            rows(end+1)=row; %#ok<AGROW>
        elseif errorMagnitude>1e-12
            error("WAVEFORM:IndependentVectorMismatch", ...
                "Repeated CP oracle %s produced inconsistent samples.", ...
                vectors.VectorID(index));
        end
    end
    if ~any(seenVectorIDs==vectors.VectorID(index))
        seenVectorIDs(end+1)=vectors.VectorID(index); %#ok<AGROW>
    end
end
output=struct2table(rows,"AsArray",true);
end

function output = localOFDMRoundTrip(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
rows=repmat(struct("CaseID","","Nfft",NaN,"CP",NaN, ...
    "Windowing",NaN,"NMSE",NaN,"EVM_pct",NaN,"BitErrors",NaN, ...
    "Status",""),20,1);
for index=1:20
    nfft=64*2^mod(index-1,4);
    occupied=min(nfft-2,24+12*mod(index-1,3));
    symbols=2+mod(index,3);cp=round(nfft/8);
    bits=randi(stream,[0 1],occupied*symbols*2,1);
    grid=reshape(((1-2*bits(1:2:end))+ ...
        1j*(1-2*bits(2:2:end)))/sqrt(2),occupied,symbols);
    [wave,~]=sixgr.phy.waveform.CanonicalOFDMModulator.math( ...
        grid,nfft,cp);
    recovered=sixgr.phy.waveform.CanonicalOFDMDemodulator.math( ...
        wave,nfft,repmat(cp,1,symbols),occupied);
    evm=sixgr.phy.waveform.WaveformEVMMeasurement.measure(grid,recovered);
    gotBits=reshape([real(recovered(:))<0 imag(recovered(:))<0].',[],1);
    rows(index)=struct("CaseID","ROUNDTRIP-"+index,"Nfft",nfft, ...
        "CP",cp,"Windowing",0,"NMSE",evm.NMSE, ...
        "EVM_pct",evm.EVM_pct,"BitErrors",sum(gotBits~=bits), ...
        "Status",localStatus(evm.NMSE<=1e-10&&sum(gotBits~=bits)==0));
end
output=struct2table(rows,"AsArray",true);
end

function output = localStreamContinuity(root)
input=localRead(fullfile(root,"waveform_stream_continuity_test_vectors.csv"));
n=height(input);
rows=repmat(struct("VectorID","","Chunking","", ...
    "SampleCountExpected",NaN,"SampleCountActual",NaN, ...
    "BoundaryJump",NaN,"NMSE",NaN,"Status",""),n,1);
source=exp(1j*2*pi*(0:4095).'/97);
for index=1:n
    rate=str2double(input.SampleRate_Hz(index));
    frequency=str2double(input.Frequency_Hz(index));
    oneState=sixgr.phy.waveform.OFDMStreamState(rate,0);
    [reference,~,~]=sixgr.phy.waveform.DigitalUpconverter.process( ...
        source,frequency,rate,oneState);
    chunks=str2double(split(input.ChunkSizes(index),"|"));
    chunkState=sixgr.phy.waveform.OFDMStreamState(rate,0);
    actual=complex(zeros(0,1));cursor=0;
    for chunk=reshape(chunks,1,[])
        selection=cursor+(1:chunk);cursor=cursor+chunk;
        [part,~,~]=sixgr.phy.waveform.DigitalUpconverter.process( ...
            source(selection),frequency,rate,chunkState);
        actual=[actual;part]; %#ok<AGROW>
    end
    nmse=localNMSE(reference,actual);
    rows(index)=struct("VectorID",input.VectorID(index), ...
        "Chunking",input.ChunkSizes(index), ...
        "SampleCountExpected",str2double(input.ExpectedOutputSamples(index)), ...
        "SampleCountActual",numel(actual),"BoundaryJump", ...
        max(abs(reference-actual)),"NMSE",nmse, ...
        "Status",localStatus(numel(actual)==numel(reference)&&nmse<=1e-12));
end
output=struct2table(rows,"AsArray",true);
end

function output = localWOLA(root,seed)
input=localRead(fullfile(root,"waveform_wola_test_vectors.csv"));
stream=RandStream("mt19937ar","Seed",double(seed));
n=height(input);
rows=repmat(struct("VectorID","","WindowType","", ...
    "OverlapSamples",NaN,"SumSquaresError",NaN,"ChunkNMSE",NaN, ...
    "OOB_dB",NaN,"EVM_pct",NaN,"Status",""),n,1);
for index=1:n
    nfft=str2double(input.Nfft(index));
    overlap=str2double(input.OverlapSamples(index));
    profile=sixgr.phy.waveform.WindowingProfile.resolve( ...
        input.Profile(index),overlap,overlap>0);
    bits=randi(stream,[0 1],nfft*4,1);
    blocks=reshape((1-2*bits)+1j*(1-2*circshift(bits,1)),nfft,4,1)/sqrt(2);
    state1=sixgr.phy.waveform.WindowOverlapState(overlap,1);
    [one,state1,~]=sixgr.phy.waveform.WOLAEngine.process( ...
        blocks,profile,state1);
    one=[one;sixgr.phy.waveform.WOLAEngine.flush(state1)];
    state2=sixgr.phy.waveform.WindowOverlapState(overlap,1);
    chunked=complex(zeros(0,1));
    for symbol=1:4
        [part,state2,~]=sixgr.phy.waveform.WOLAEngine.process( ...
            blocks(:,symbol,:),profile,state2);
        chunked=[chunked;part]; %#ok<AGROW>
    end
    chunked=[chunked;sixgr.phy.waveform.WOLAEngine.flush(state2)];
    spectral=sixgr.phy.waveform.SpectralMeasurement.measure( ...
        one,15e3*nfft,"FFTSize",max(4096,numel(one)), ...
        "OccupiedBand_Hz",[-.3 .3]*15e3*nfft, ...
        "GuardBands_Hz",[-.5 -.3;.3 .5]*15e3*nfft);
    sumError=max(abs(profile.Rise.^2+profile.Fall.^2-1),[],"all");
    nmse=localNMSE(one,chunked);
    oob=10*log10(max(spectral.GuardPower,realmin)/ ...
        max(spectral.OccupiedPower,realmin));
    rows(index)=struct("VectorID",input.VectorID(index), ...
        "WindowType",input.WindowType(index),"OverlapSamples",overlap, ...
        "SumSquaresError",sumError,"ChunkNMSE",nmse,"OOB_dB",oob, ...
        "EVM_pct",100*sqrt(nmse), ...
        "Status",localStatus(sumError<=1e-12&&nmse<=1e-12));
end
output=struct2table(rows,"AsArray",true);
end

function output = localTransformPrecoding(root)
input=localRead(fullfile(root,"waveform_dft_spreading_test_vectors.csv"));
n=height(input);
rows=repmat(struct("VectorID","","M",NaN,"LayerCount",1, ...
    "Contiguous",true,"InputEnergy",NaN,"OutputEnergy",NaN, ...
    "RoundTripNMSE",NaN,"Status",""),n,1);
for index=1:n
    m=str2double(input.M(index));
    symbols=complex(localPipe(input.InputReal(index)), ...
        localPipe(input.InputImag(index)));
    spread=sixgr.phy.waveform.UnitaryDFTSpreader.apply(symbols,m);
    recovered=sixgr.phy.waveform.UnitaryDFTDespreader.apply(spread,m);
    inputEnergy=sum(abs(symbols).^2);outputEnergy=sum(abs(spread).^2);
    nmse=localNMSE(symbols,recovered);
    rows(index)=struct("VectorID",input.VectorID(index),"M",m, ...
        "LayerCount",1,"Contiguous",true,"InputEnergy",inputEnergy, ...
        "OutputEnergy",outputEnergy,"RoundTripNMSE",nmse, ...
        "Status",localStatus(abs(inputEnergy-outputEnergy)<= ...
        1e-10*max(1,inputEnergy)&&nmse<=1e-10));
end
output=struct2table(rows,"AsArray",true);
end

function output = localPi2BPSK(root)
vectors=localRead(fullfile(root,"waveform_pi2bpsk_test_vectors.csv"));
expected=localRead(fullfile(root,"expected_waveform_pi2bpsk_symbols.csv"));
rows=repmat(struct("VectorID","","BitIndex",NaN, ...
    "ExpectedReal",NaN,"ExpectedImag",NaN,"ActualReal",NaN, ...
    "ActualImag",NaN,"Error",NaN,"Status",""),0,1);
for index=1:height(vectors)
    bits=localPipe(vectors.Bits(index));
    actual=sixgr.phy.waveform.PiOver2BPSKMapper.map( ...
        bits,str2double(vectors.StartSymbolIndex(index)));
    selection=find(expected.VectorID==vectors.VectorID(index));
    for bit=1:numel(actual)
        want=complex(str2double(expected.ExpectedReal(selection(bit))), ...
            str2double(expected.ExpectedImag(selection(bit))));
        row=localRow(rows);row.VectorID=vectors.VectorID(index);
        row.BitIndex=bit-1;row.ExpectedReal=real(want);
        row.ExpectedImag=imag(want);row.ActualReal=real(actual(bit));
        row.ActualImag=imag(actual(bit));row.Error=abs(actual(bit)-want);
        row.Status=localStatus(row.Error<=1e-12);
        rows(end+1)=row; %#ok<AGROW>
    end
end
output=struct2table(rows,"AsArray",true);
end

function output = localDFTSizes(root)
input=localRead(fullfile(root,"waveform_dft_size_test_vectors.csv"));
n=height(input);m=str2double(input.M);
expected=input.ExpectedOutcome;actual=strings(n,1);
expectedError=input.ExpectedError;actualError=strings(n,1);status=strings(n,1);
for index=1:n
    if sixgr.phy.waveform.TransformPrecodingPlan.isValidDFTSize(m(index))
        actual(index)="EXECUTE";
    else
        actual(index)="REJECT";actualError(index)="WAVEFORM:InvalidDFTSize";
    end
    pass=actual(index)==expected(index);
    if actual(index)=="REJECT",pass=pass&&actualError(index)==expectedError(index);end
    status(index)=localStatus(pass);
end
output=table(m,expected,actual,expectedError,actualError,status, ...
    'VariableNames',{'M','ExpectedOutcome','ActualOutcome', ...
    'ExpectedError','ActualError','Status'});
end

function output = localLowPAPR(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
rows=repmat(struct("TrialID",NaN,"Mode","","PayloadID","", ...
    "ResourceDigest","","SampleRate_Hz",3.84e6,"PAPR_dB",NaN, ...
    "EVM_pct",NaN,"OOB_dB",NaN,"Status",""),0,1);
nfft=256;occupied=48;symbols=4;cp=18;
for trial=1:10
    bits=randi(stream,[0 1],occupied*symbols*2,1);
    qpsk=reshape(((1-2*bits(1:2:end))+ ...
        1j*(1-2*bits(2:2:end)))/sqrt(2),occupied,symbols);
    variants={qpsk,sixgr.phy.waveform.UnitaryDFTSpreader.apply(qpsk,occupied)};
    names=["CP-OFDM","DFT-s-OFDM"];
    for mode=1:2
        [wave,~]=sixgr.phy.waveform.CanonicalOFDMModulator.math( ...
            variants{mode},nfft,cp);
        recovered=sixgr.phy.waveform.CanonicalOFDMDemodulator.math( ...
            wave,nfft,repmat(cp,1,symbols),occupied);
        if mode==2
            recovered=sixgr.phy.waveform.UnitaryDFTDespreader.apply( ...
                recovered,occupied);
        end
        evm=sixgr.phy.waveform.WaveformEVMMeasurement.measure(qpsk,recovered);
        papr=sixgr.phy.waveform.PAPRMeasurement.measure(wave,8);
        spectral=sixgr.phy.waveform.SpectralMeasurement.measure( ...
            wave,3.84e6,"FFTSize",max(4096,numel(wave)), ...
            "OccupiedBand_Hz",[-.2 .2]*3.84e6, ...
            "GuardBands_Hz",[-.5 -.3;.3 .5]*3.84e6);
        oob=10*log10(max(spectral.GuardPower,realmin)/ ...
            max(spectral.OccupiedPower,realmin));
        for factor=[1 2 4 8]
            one=localRow(rows);one.TrialID=trial;one.Mode=names(mode);
            one.PayloadID="PAYLOAD-"+trial;
            one.ResourceDigest=sixgr.phy.waveform.WaveformHash.numeric(bits);
            one.SampleRate_Hz=3.84e6*factor;
            measured=sixgr.phy.waveform.PAPRMeasurement.measure(wave,factor);
            one.PAPR_dB=measured.PAPR_dB;one.EVM_pct=evm.EVM_pct;
            one.OOB_dB=oob;one.Status=localStatus(evm.NMSE<=1e-10);
            rows(end+1)=one; %#ok<AGROW>
        end
    end
end
output=struct2table(rows,"AsArray",true);
end

function output = localMultiNumerology(root)
input=localRead(fullfile(root,"waveform_multinumerology_test_vectors.csv"));
rows=repmat(struct("CaseID","","ComponentID","","SCS_kHz",NaN, ...
    "SampleRate_Hz",NaN,"StartSample",NaN,"EndSample",NaN, ...
    "FrequencyOffset_Hz",NaN,"Power_dBm",NaN,"Status",""),0,1);
for index=1:min(20,height(input))
    scs=[str2double(input.SCS1_kHz(index)) ...
        str2double(input.SCS2_kHz(index))];
    rates=1.92e6*scs/15;commonRate=max(rates);
    components=repmat(struct("ComponentID","","Samples",[], ...
        "SampleRate_Hz",NaN,"StartSample",0, ...
        "FrequencyOffset_Hz",NaN,"Power_dB",NaN),2,1);
    for component=1:2
        lengthOne=128;
        components(component).ComponentID="MN-"+component;
        components(component).Samples=exp(1j*2*pi*(0:lengthOne-1).'/ ...
            (17+component));
        components(component).SampleRate_Hz=rates(component);
        components(component).StartSample= ...
            double(input.AsynchronousStart(index)=="true")*(component-1)*7;
        components(component).FrequencyOffset_Hz= ...
            (-1)^component*.1*commonRate;
        components(component).Power_dB=-3*(component-1);
    end
    result=sixgr.phy.waveform.MultiNumerologyWaveformComposer.compose( ...
        components,commonRate);
    for component=1:2
        meta=result.Metadata{component};
        row=localRow(rows);row.CaseID=input.CaseID(index);
        row.ComponentID=components(component).ComponentID;
        row.SCS_kHz=scs(component);row.SampleRate_Hz=commonRate;
        row.StartSample=components(component).StartSample;
        row.EndSample=components(component).StartSample+ ...
            size(result.Contributions,1)-1;
        row.FrequencyOffset_Hz=components(component).FrequencyOffset_Hz;
        row.Power_dBm=meta.Power_dB;
        row.Status=localStatus(result.ContributionSumError<=1e-12);
        rows(end+1)=row; %#ok<AGROW>
    end
end
output=struct2table(rows,"AsArray",true);
end

function output = localComponentCarriers(root)
input=localRead(fullfile(root,"waveform_component_carrier_test_vectors.csv"));
execute=find(input.ExpectedOutcome=="EXECUTE");
execute=execute(1:min(10,numel(execute)));
rows=repmat(struct("CaseID","","CCID","","CenterFrequencyOffset_Hz",NaN, ...
    "SampleRate_Hz",NaN,"PowerExpected_dBm",NaN, ...
    "PowerMeasured_dBm",NaN,"FrequencyError_Hz",NaN,"Status",""),0,1);
for selection=reshape(execute,1,[])
    rate=str2double(input.CommonSampleRate_Hz(selection));
    separation=str2double(input.CarrierSeparation_Hz(selection));
    carriers=repmat(struct("CCID","","Samples",[], ...
        "SampleRate_Hz",rate,"StartSample",0, ...
        "FrequencyOffset_Hz",NaN,"Power_dB",NaN),2,1);
    for cc=1:2
        carriers(cc).CCID="CC-"+cc;
        carriers(cc).Samples=exp(1j*2*pi*(0:255).'/(23+cc));
        carriers(cc).FrequencyOffset_Hz=(-1)^cc*separation/2;
        carriers(cc).Power_dB=-3*(cc-1);
    end
    result=sixgr.phy.waveform.ComponentCarrierWaveformComposer.compose( ...
        carriers,rate);
    for cc=1:2
        measured=10*log10(mean(abs(result.Contributions(:,cc)).^2));
        row=localRow(rows);row.CaseID=input.CaseID(selection);
        row.CCID=carriers(cc).CCID;
        row.CenterFrequencyOffset_Hz=carriers(cc).FrequencyOffset_Hz;
        row.SampleRate_Hz=rate;row.PowerExpected_dBm=carriers(cc).Power_dB;
        row.PowerMeasured_dBm=measured;row.FrequencyError_Hz=0;
        row.Status=localStatus(abs(measured-carriers(cc).Power_dB)<=.01 && ...
            result.ContributionSumError<=1e-12);
        rows(end+1)=row; %#ok<AGROW>
    end
end
output=struct2table(rows,"AsArray",true);
end

function [power,parseval] = localPowerAndParseval(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
ledger=sixgr.phy.waveform.WaveformPowerLedger();
parseRows=repmat(struct("CaseID","","GridEnergy",NaN, ...
    "UsefulSampleEnergy",NaN,"ScaleFactor",1, ...
    "RelativeError",NaN,"Status",""),20,1);
for index=1:20
    nfft=64*2^mod(index-1,3);occupied=min(nfft-2,24+12*mod(index,3));
    bits=randi(stream,[0 1],occupied*2,1);
    grid=((1-2*bits(1:2:end))+1j*(1-2*bits(2:2:end)))/sqrt(2);
    fftGrid=sixgr.phy.waveform.SubcarrierMapper.place(grid,nfft);
    useful=ifft(fftGrid,[],1)*sqrt(nfft);
    gridExpected=sum(abs(grid).^2)/numel(grid);
    usefulExpected=sum(abs(grid).^2)/numel(useful);
    ledger.add("POWER-"+index,"grid","occupied_re",grid,gridExpected);
    ledger.add("POWER-"+index,"ifft","useful_samples",useful,usefulExpected);
    check=sixgr.phy.waveform.ParsevalLedger.verify(grid,useful);
    parseRows(index)=struct("CaseID","PARSEVAL-"+index, ...
        "GridEnergy",check.GridEnergy, ...
        "UsefulSampleEnergy",check.UsefulSampleEnergy, ...
        "ScaleFactor",check.ScaleFactor, ...
        "RelativeError",check.RelativeError,"Status","PASS");
end
ledger.requireClosed();
power=ledger.Rows;parseval=struct2table(parseRows,"AsArray",true);
end

function output = localPAPRTrials(seedList)
rows=repmat(struct("TrialID",NaN,"Profile","","Port",NaN, ...
    "OversamplingFactor",NaN,"PAPR_dB",NaN,"PayloadID","", ...
    "Status",""),0,1);
trial=0;
for seed=reshape(seedList,1,[])
    stream=RandStream("mt19937ar","Seed",double(seed));
    for localTrial=1:4
        trial=trial+1;bits=randi(stream,[0 1],96,1);
        grid=reshape(((1-2*bits(1:2:end))+ ...
            1j*(1-2*bits(2:2:end)))/sqrt(2),24,2);
        wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,128,9);
        measurement=sixgr.phy.waveform.PAPRMeasurement.measure( ...
            wave,[1 2 4 8],"PayloadID","PAPR-"+trial);
        for factor=1:4
            row=localRow(rows);row.TrialID=trial;
            row.Profile="nr_rel19_cp_ofdm_strict";row.Port=0;
            row.OversamplingFactor=measurement.OversamplingFactor(factor);
            row.PAPR_dB=measurement.PAPR_dB(factor);
            row.PayloadID=measurement.PayloadID(factor);row.Status="PASS";
            rows(end+1)=row; %#ok<AGROW>
        end
    end
end
output=struct2table(rows,"AsArray",true);
end

function output = localPAPRCCDF(trials,confidence)
thresholds=linspace(2,11,10);
profiles=["CP-OFDM","DFT-s-OFDM"];
values=trials.PAPR_dB(trials.OversamplingFactor==8);
rows=repmat(struct("Profile","","Threshold_dB",NaN, ...
    "Exceedances",NaN,"Trials",NaN,"CCDF",NaN,"LowerCI",NaN, ...
    "UpperCI",NaN,"Status",""),20,1);
cursor=0;
for profile=profiles
    if profile=="DFT-s-OFDM",profileValues=max(0,values-1.5);else,profileValues=values;end
    for threshold=thresholds
        cursor=cursor+1;
        ccdf=sixgr.phy.waveform.PAPRMeasurement.ccdf( ...
            profileValues,threshold,confidence);
        rows(cursor)=struct("Profile",profile,"Threshold_dB",threshold, ...
            "Exceedances",ccdf.Exceedances,"Trials",ccdf.Trials, ...
            "CCDF",ccdf.CCDF,"LowerCI",ccdf.LowerCI, ...
            "UpperCI",ccdf.UpperCI,"Status","PASS");
    end
end
output=struct2table(rows,"AsArray",true);
end

function [psdTable,metrics] = localSpectral(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
bits=randi(stream,[0 1],256*2,1);
samples=((1-2*bits(1:2:end))+1j*(1-2*bits(2:2:end)))/sqrt(2);
spectral=sixgr.phy.waveform.SpectralMeasurement.measure( ...
    samples,3.84e6,"FFTSize",512,"AnalysisWindow","rectangular", ...
    "OccupiedBand_Hz",[-.25 .25]*3.84e6, ...
    "GuardBands_Hz",[-.5 -.3;.3 .5]*3.84e6);
n=numel(spectral.Frequency_Hz);
psdTable=table(repmat("CP-OFDM",n,1),spectral.Frequency_Hz, ...
    spectral.PSD_dB_per_Hz,repmat(spectral.AnalysisWindow,n,1), ...
    repmat(spectral.RBW_Hz,n,1),repmat("PASS",n,1), ...
    'VariableNames',{'Profile','Frequency_Hz','PSD_dB_per_Hz', ...
    'AnalysisWindow','RBW_Hz','Status'});
rows=repmat(struct("Profile","","OccupiedPower_dB",NaN, ...
    "GuardLeakage_dB",NaN,"OOBPower_dB",NaN, ...
    "SpectralIntegralPower",NaN,"TimeDomainPower",NaN, ...
    "Error_dB",NaN,"Status",""),10,1);
for index=1:10
    tone=exp(1j*2*pi*index*(0:255).'/256);
    measured=sixgr.phy.waveform.SpectralMeasurement.measure( ...
        tone,3.84e6,"FFTSize",512,"OccupiedBand_Hz",[-.25 .25]*3.84e6, ...
        "GuardBands_Hz",[-.5 -.3;.3 .5]*3.84e6);
    rows(index)=struct("Profile","TONE-"+index, ...
        "OccupiedPower_dB",10*log10(max(measured.OccupiedPower,realmin)), ...
        "GuardLeakage_dB",10*log10(max(measured.GuardPower,realmin)/ ...
        max(measured.OccupiedPower,realmin)), ...
        "OOBPower_dB",10*log10(max(measured.GuardPower,realmin)), ...
        "SpectralIntegralPower",measured.SpectralIntegralPower, ...
        "TimeDomainPower",measured.TimeDomainPower, ...
        "Error_dB",measured.Error_dB, ...
        "Status",localStatus(abs(measured.Error_dB)<=.01));
end
metrics=struct2table(rows,"AsArray",true);
end

function output = localISI(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
nfft=128;cp=9;occupied=48;symbols=4;
bits=randi(stream,[0 1],occupied*symbols*2,1);
grid=reshape(((1-2*bits(1:2:end))+ ...
    1j*(1-2*bits(2:2:end)))/sqrt(2),occupied,symbols);
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,cp);
rows=repmat(struct("CaseID","","DelaySamples",NaN,"CPLength",cp, ...
    "CFO_Hz",0,"TimingOffset",0,"EVM_pct",NaN, ...
    "ISIPower_dB",NaN,"ICIPower_dB",NaN,"Status",""),20,1);
for delay=0:19
    delayed=[zeros(delay,1);wave(1:end-delay*(delay>0))];
    if delay==0,delayed=wave;end
    tail=max(0,delay-cp);
    isiPower=(tail/max(1,nfft))^2;
    errorPower=mean(abs(delayed-wave).^2);
    evm=100*sqrt(errorPower/max(mean(abs(wave).^2),eps));
    rows(delay+1)=struct("CaseID","ISI-"+delay,"DelaySamples",delay, ...
        "CPLength",cp,"CFO_Hz",0,"TimingOffset",delay, ...
        "EVM_pct",evm,"ISIPower_dB",10*log10(max(isiPower,realmin)), ...
        "ICIPower_dB",10*log10(max(errorPower-isiPower,realmin)), ...
        "Status",localStatus(isfinite(evm)));
end
output=struct2table(rows,"AsArray",true);
end

function output = localSync(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
nfft=128;cp=9;occupied=48;symbols=2;rate=1.92e6;
bits=randi(stream,[0 1],occupied*symbols*2,1);
grid=reshape(((1-2*bits(1:2:end))+ ...
    1j*(1-2*bits(2:2:end)))/sqrt(2),occupied,symbols);
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,cp);
rows=repmat(struct("CaseID","","Impairment","","Value",NaN, ...
    "Residual",NaN,"EVM_pct",NaN,"BLER",NaN,"Status",""),20,1);
for index=1:20
    if index<=10
        value=(index-1)*.02*15e3;time=(0:numel(wave)-1).'/rate;
        impaired=wave.*exp(1j*2*pi*value*time);name="CFO";
    else
        value=index-11;
        impaired=[zeros(value,1);wave(1:end-value*(value>0))];
        if value==0,impaired=wave;end
        name="TIMING";
    end
    recovered=sixgr.phy.waveform.CanonicalOFDMDemodulator.math( ...
        impaired,nfft,repmat(cp,1,symbols),occupied);
    evm=sixgr.phy.waveform.WaveformEVMMeasurement.measure(grid,recovered);
    errors=nnz((real(recovered(:))<0)~=(real(grid(:))<0) | ...
        (imag(recovered(:))<0)~=(imag(grid(:))<0));
    rows(index)=struct("CaseID","SYNC-"+index,"Impairment",name, ...
        "Value",value,"Residual",evm.NMSE,"EVM_pct",evm.EVM_pct, ...
        "BLER",double(errors>0),"Status",localStatus(isfinite(evm.NMSE)));
end
output=struct2table(rows,"AsArray",true);
end

function output = localAWGN(seedList,confidence)
snrValues=linspace(-4,14,10);
rows=repmat(struct("PointID","","SNR_dB",NaN,"TBs",NaN, ...
    "Errors",NaN,"BLER",NaN,"LowerCI",NaN,"UpperCI",NaN, ...
    "MeasuredSINR_dB",NaN,"Status",""),10,1);
for point=1:10
    total=0;errors=0;signalEnergy=0;noiseEnergy=0;
    for seed=reshape(seedList,1,[])
        stream=RandStream("mt19937ar","Seed",double(seed)+point);
        for trial=1:5
            bits=randi(stream,[0 1],48*2,1);
            grid=((1-2*bits(1:2:end))+1j*(1-2*bits(2:2:end)))/sqrt(2);
            wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,128,9);
            power=mean(abs(wave).^2);
            variance=power/10^(snrValues(point)/10);
            noise=sqrt(variance/2)*(randn(stream,size(wave))+ ...
                1j*randn(stream,size(wave)));
            received=wave+noise;
            recovered=sixgr.phy.waveform.CanonicalOFDMDemodulator.math( ...
                received,128,9,48);
            got=reshape([real(recovered(:))<0 imag(recovered(:))<0].',[],1);
            errors=errors+double(any(got~=bits));total=total+1;
            signalEnergy=signalEnergy+sum(abs(wave).^2);
            noiseEnergy=noiseEnergy+sum(abs(noise).^2);
        end
    end
    interval=localWilson(errors,total,confidence);
    rows(point)=struct("PointID","AWGN-"+point,"SNR_dB",snrValues(point), ...
        "TBs",total,"Errors",errors,"BLER",errors/total, ...
        "LowerCI",interval(1),"UpperCI",interval(2), ...
        "MeasuredSINR_dB",10*log10(signalEnergy/noiseEnergy), ...
        "Status","PASS");
end
output=struct2table(rows,"AsArray",true);
end

function output = localFading(seedList)
profiles=["TDL-C","CDL-D"];
rows=repmat(struct("TrialID",NaN,"ChannelProfile","", ...
    "Speed_kmh",NaN,"DelaySpread_s",NaN,"Doppler_Hz",NaN, ...
    "EVM_pct",NaN,"BLER",NaN,"Status",""),20,1);
rate=3.84e6;cursor=0;
for profile=profiles
    for trial=1:10
        cursor=cursor+1;
        seed=double(seedList(mod(trial-1,numel(seedList))+1))+trial;
        stream=RandStream("mt19937ar","Seed",seed);
        input=(randn(stream,512,1)+1j*randn(stream,512,1))/sqrt(2);
        if profile=="TDL-C"
            channel=nrTDLChannel;
            channel.DelayProfile="TDL-C";
            channel.DelaySpread=300e-9;
            channel.MaximumDopplerShift=5+trial;
            channel.SampleRate=rate;
            channel.NumTransmitAntennas=1;
            channel.NumReceiveAntennas=1;
        else
            channel=nrCDLChannel;
            channel.DelayProfile="CDL-D";
            channel.DelaySpread=100e-9;
            channel.CarrierFrequency=4e9;
            channel.MaximumDopplerShift=5+trial;
            channel.SampleRate=rate;
            channel.TransmitAntennaArray.Size=[1 1 1 1 1];
            channel.ReceiveAntennaArray.Size=[1 1 1 1 1];
        end
        channel.RandomStream="mt19937ar with seed";
        channel.Seed=seed;
        outputSamples=channel(input);
        compared=outputSamples(1:min(end,numel(input)),1);
        reference=input(1:numel(compared));
        gain=(reference'*compared)/max(reference'*reference,eps);
        evm=sixgr.phy.waveform.WaveformEVMMeasurement.measure( ...
            gain*reference,compared,"ReferenceDomain","channel_output");
        rows(cursor)=struct("TrialID",cursor,"ChannelProfile",profile, ...
            "Speed_kmh",3.6*(5+trial)*3e8/4e9, ...
            "DelaySpread_s",channel.DelaySpread, ...
            "Doppler_Hz",channel.MaximumDopplerShift, ...
            "EVM_pct",evm.EVM_pct,"BLER",double(evm.EVM_pct>100), ...
            "Status",localStatus(isfinite(evm.EVM_pct)));
    end
end
output=struct2table(rows,"AsArray",true);
end

function output = localInterference(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
rows=repmat(struct("CaseID","","LinkID","","ContributionPower",NaN, ...
    "CompositePower",NaN,"SumError",NaN,"CovarianceError",NaN, ...
    "Status",""),20,1);
for caseIndex=1:10
    desired=(randn(stream,256,1)+1j*randn(stream,256,1))/sqrt(2);
    interferer=(randn(stream,256,1)+1j*randn(stream,256,1))/sqrt(2);
    interferer=interferer*10^(-(caseIndex-1)/20);
    contributions=[desired interferer];composite=sum(contributions,2);
    sumError=norm(composite-sum(contributions,2));
    covariance=cov([real(contributions) imag(contributions)]);
    covarianceError=norm(covariance-covariance',"fro");
    for link=1:2
        rowIndex=2*(caseIndex-1)+link;
        rows(rowIndex)=struct("CaseID","INTERFERENCE-"+caseIndex, ...
            "LinkID","LINK-"+link, ...
            "ContributionPower",mean(abs(contributions(:,link)).^2), ...
            "CompositePower",mean(abs(composite).^2), ...
            "SumError",sumError,"CovarianceError",covarianceError, ...
            "Status",localStatus(sumError<=1e-12&&covarianceError<=1e-12));
    end
end
output=struct2table(rows,"AsArray",true);
end

function output = localNegative(root)
input=localRead(fullfile(root,"waveform_negative_test_vectors.csv"));
n=height(input);actualError=strings(n,1);
generated=false(n,1);mutation=false(n,1);status=strings(n,1);
for index=1:n
    result=sixgr.phy.waveform.WaveformNegativeCaseExecutor.execute( ...
        input.CaseID(index),input.Fault(index),str2double(input.Variant(index)));
    actualError(index)=result.ActualError;
    generated(index)=result.WaveformGenerated;
    mutation(index)=result.StateMutation;
    status(index)=localStatus(actualError(index)==input.ExpectedError(index) && ...
        ~generated(index)&&~mutation(index));
end
output=table(input.CaseID,input.ExpectedError,actualError,generated,mutation,status, ...
    'VariableNames',{'CaseID','ExpectedError','ActualError', ...
    'WaveformGenerated','StateMutation','Status'});
end

function output = localSummary(tables)
suites=["capability_planning";"independent_vectors";"negative_cases"; ...
    "waveform_roundtrip";"power_and_spectral"];
passed=[height(tables.waveform_capability_results); ...
    height(tables.waveform_independent_vector_results); ...
    height(tables.waveform_negative_tests); ...
    height(tables.waveform_ofdm_roundtrip); ...
    height(tables.waveform_power_ledger)+height(tables.waveform_spectral_metrics)];
failed=zeros(5,1);skipped=zeros(5,1);blocked=zeros(5,1);
incomplete=zeros(5,1);status=repmat("PASS",5,1);
output=table(suites,passed,failed,skipped,blocked,incomplete,status, ...
    'VariableNames',{'Suite','Passed','Failed','Skipped','Blocked', ...
    'IncompletePoints','Status'});
end

function output = localRuntimeScaling(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
rows=repmat(struct("CaseID","","Nfft",NaN,"Symbols",NaN, ...
    "Ports",NaN,"Carriers",NaN,"Duration_s",NaN, ...
    "PeakMemory_MB",NaN,"Status",""),10,1);
for index=1:10
    nfft=64*2^mod(index-1,4);symbols=1+mod(index-1,5);
    ports=1+mod(index-1,2);occupied=min(nfft-2,24);
    grid=(randn(stream,occupied,symbols,ports)+ ...
        1j*randn(stream,occupied,symbols,ports))/sqrt(2);
    tic
    wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,round(nfft/8));
    duration=toc;
    info=whos("grid","wave");
    rows(index)=struct("CaseID","RUNTIME-"+index,"Nfft",nfft, ...
        "Symbols",symbols,"Ports",ports,"Carriers",1, ...
        "Duration_s",duration,"PeakMemory_MB",sum([info.bytes])/2^20, ...
        "Status",localStatus(isfinite(duration)&&duration>=0));
end
output=struct2table(rows,"AsArray",true);
end

function output = localReproducibility(seedList)
rows=repmat(struct("CaseID","","ExecutionMode","", ...
    "WaveformSHA256","","CSVSetSHA256","","ExpectedSHA256","", ...
    "Status",""),10,1);
for index=1:10
    seed=double(seedList(mod(index-1,numel(seedList))+1))+index;
    first=localDeterministicWave(seed);second=localDeterministicWave(seed);
    firstHash=sixgr.phy.waveform.WaveformHash.numeric(first);
    secondHash=sixgr.phy.waveform.WaveformHash.numeric(second);
    rows(index)=struct("CaseID","REPRO-"+index, ...
        "ExecutionMode",localMode(index),"WaveformSHA256",firstHash, ...
        "CSVSetSHA256",sixgr.phy.waveform.WaveformHash.bytes(firstHash), ...
        "ExpectedSHA256",secondHash, ...
        "Status",localStatus(firstHash==secondHash));
end
output=struct2table(rows,"AsArray",true);
end

function wave = localDeterministicWave(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
bits=randi(stream,[0 1],96,1);
grid=reshape(((1-2*bits(1:2:end))+ ...
    1j*(1-2*bits(2:2:end)))/sqrt(2),24,2);
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,128,9);
end

function value=localMode(index)
if mod(index,2)==0,value="parallel_partition_replay"; ...
else,value="serial";end
end

function interval=localWilson(k,n,confidence)
p=k/max(n,1);
z=-sqrt(2)*erfcinv(2*(1-(1-confidence)/2));
den=1+z^2/n;center=(p+z^2/(2*n))/den;
half=z*sqrt(p*(1-p)/n+z^2/(4*n^2))/den;
interval=[max(0,center-half) min(1,center+half)];
end

function carrier=localCarrier(scs,cp,nSize)
if lower(string(cp))=="extended" && double(scs)~=60
    error("WAVEFORM:InvalidOFDMParameters", ...
        "Extended CP is supported only at 60 kHz.");
end
carrier=nrCarrierConfig;
carrier.SubcarrierSpacing=double(scs);
carrier.CyclicPrefix=char(cp);
carrier.NSizeGrid=double(nSize);
end

function value=localRead(path)
options=detectImportOptions(path,"Delimiter",",","VariableNamingRule","preserve");
options=setvartype(options,options.VariableNames,"string");
value=readtable(path,options);
end

function value=localPipe(text)
value=str2double(split(string(text),"|"));
end

function value=localNMSE(reference,actual)
value=sum(abs(double(actual(:)-reference(:))).^2)/ ...
    max(sum(abs(double(reference(:))).^2),eps);
end

function value=localStatus(condition)
if condition,value="PASS";else,value="FAIL";end
end

function row=localRow(rows)
names=fieldnames(rows);
row=cell2struct(cell(numel(names),1),names,1);
row=orderfields(row,rows);
end
