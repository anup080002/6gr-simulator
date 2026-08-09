classdef WaveformVectorValidator
    %WAVEFORMVECTORVALIDATOR Execute the independent phase-13 math oracles.

    methods (Static)
        function result = validate(vectorRoot,varargin)
            ip = inputParser;
            ip.addParameter("ThrowOnMismatch",true,@(x)islogical(x)&&isscalar(x));
            ip.parse(varargin{:});
            vectorRoot = string(vectorRoot);
            if ~isfolder(vectorRoot)
                error("WAVEFORM:IndependentVectorMissing", ...
                    "Waveform vector root does not exist: %s.",vectorRoot);
            end
            rows = repmat(localTemplate(),0,1);
            rows = [rows; localSmallFFT(vectorRoot)]; %#ok<AGROW>
            rows = [rows; localCP(vectorRoot)]; %#ok<AGROW>
            rows = [rows; localDFT(vectorRoot)]; %#ok<AGROW>
            rows = [rows; localPi2BPSK(vectorRoot)]; %#ok<AGROW>
            rows = [rows; localWOLA(vectorRoot)]; %#ok<AGROW>
            rows = [rows; localPAPR(vectorRoot)]; %#ok<AGROW>
            rows = [rows; localSpectral(vectorRoot)]; %#ok<AGROW>
            result = struct2table(rows,"AsArray",true);
            if ip.Results.ThrowOnMismatch && any(result.MismatchCount ~= 0)
                error("WAVEFORM:IndependentVectorMismatch", ...
                    "%d phase-13 independent vector cases mismatched.", ...
                    sum(result.MismatchCount ~= 0));
            end
        end
    end
end

function rows = localSmallFFT(root)
vectors = localRead(fullfile(root,"waveform_small_fft_test_vectors.csv"));
expected = localRead(fullfile(root,"expected_waveform_small_fft_samples.csv"));
rows = repmat(localTemplate(),height(vectors),1);
for ii = 1:height(vectors)
    vectorID = vectors.VectorID(ii);
    mask = expected.VectorID == vectorID;
    want = complex(str2double(expected.ExpectedReal(mask)), ...
        str2double(expected.ExpectedImag(mask)));
    grid = complex(localPipe(vectors.GridReal(ii)), ...
        localPipe(vectors.GridImag(ii)));
    [got,~] = sixgr.phy.waveform.CanonicalOFDMModulator.math( ...
        reshape(grid,[],1),str2double(vectors.Nfft(ii)), ...
        str2double(vectors.CP(ii)));
    rows(ii) = localResult("small_fft",vectorID,want,got,1e-12, ...
        "independent_unitary_ifft");
end
end

function rows = localCP(root)
vectors = localRead(fullfile(root,"waveform_cp_test_vectors.csv"));
expected = localRead(fullfile(root,"expected_waveform_cp_samples.csv"));
rows = repmat(localTemplate(),0,1);
cursor = 0;
seenVectorIDs = strings(0,1);
for ii = 1:height(vectors)
    vectorID = vectors.VectorID(ii);
    count = str2double(vectors.UsefulLength(ii)) + ...
        str2double(vectors.CPLength(ii));
    selection = cursor + (1:count);
    cursor = cursor + count;
    if any(expected.VectorID(selection) ~= vectorID)
        error("WAVEFORM:IndependentVectorMismatch", ...
            "CP vector ordering differs at %s.",vectorID);
    end
    want = complex(str2double(expected.ExpectedReal(selection)), ...
        str2double(expected.ExpectedImag(selection)));
    input = complex(localPipe(vectors.InputReal(ii)), ...
        localPipe(vectors.InputImag(ii)));
    got = sixgr.phy.waveform.CPInsertionRemoval.insert( ...
        input,str2double(vectors.CPLength(ii)));
    result = localResult("cyclic_prefix",vectorID,want,got,1e-12, ...
        "independent_sample_copy");
    if any(seenVectorIDs == vectorID)
        if result.MismatchCount ~= 0
            error("WAVEFORM:IndependentVectorMismatch", ...
                "Repeated CP oracle %s produced inconsistent samples.", ...
                vectorID);
        end
        continue;
    end
    seenVectorIDs(end+1) = vectorID; %#ok<AGROW>
    rows(end+1) = result; %#ok<AGROW>
end
rows = rows(:);
end

function rows = localDFT(root)
vectors = localRead(fullfile(root,"waveform_dft_spreading_test_vectors.csv"));
expected = localRead(fullfile(root,"expected_waveform_dft_coefficients.csv"));
rows = repmat(localTemplate(),height(vectors),1);
for ii = 1:height(vectors)
    vectorID = vectors.VectorID(ii);
    mask = expected.VectorID == vectorID;
    want = complex(str2double(expected.ExpectedReal(mask)), ...
        str2double(expected.ExpectedImag(mask)));
    input = complex(localPipe(vectors.InputReal(ii)), ...
        localPipe(vectors.InputImag(ii)));
    m = str2double(vectors.M(ii));
    got = sixgr.phy.waveform.UnitaryDFTSpreader.apply(input,m);
    roundTrip = sixgr.phy.waveform.UnitaryDFTDespreader.apply(got,m);
    mismatch = max(abs(got(:)-want(:))) > 5e-11 || ...
        localNMSE(input,roundTrip) > 1e-24;
    rows(ii) = localResult("unitary_dft",vectorID,want,got,5e-11, ...
        "independent_closed_form_dft");
    rows(ii).MismatchCount = double(mismatch);
    rows(ii).Status = localPass(~mismatch);
end
end

function rows = localPi2BPSK(root)
vectors = localRead(fullfile(root,"waveform_pi2bpsk_test_vectors.csv"));
expected = localRead(fullfile(root,"expected_waveform_pi2bpsk_symbols.csv"));
rows = repmat(localTemplate(),height(vectors),1);
for ii = 1:height(vectors)
    vectorID = vectors.VectorID(ii);
    mask = expected.VectorID == vectorID;
    want = complex(str2double(expected.ExpectedReal(mask)), ...
        str2double(expected.ExpectedImag(mask)));
    bits = localPipe(vectors.Bits(ii));
    got = sixgr.phy.waveform.PiOver2BPSKMapper.map( ...
        bits,str2double(vectors.StartSymbolIndex(ii)));
    rows(ii) = localResult("pi2_bpsk",vectorID,want,got,1e-12, ...
        "independent_symbol_formula");
end
end

function rows = localWOLA(root)
vectors = localRead(fullfile(root,"waveform_wola_test_vectors.csv"));
expected = localRead(fullfile(root,"expected_waveform_wola_coefficients.csv"));
rows = repmat(localTemplate(),height(vectors),1);
for ii = 1:height(vectors)
    vectorID = vectors.VectorID(ii);
    mask = expected.VectorID == vectorID;
    want = [str2double(expected.Rise(mask)); ...
        str2double(expected.Fall(mask)); ...
        str2double(expected.SumSquares(mask))];
    overlap = str2double(vectors.OverlapSamples(ii));
    [rise,fall] = sixgr.phy.waveform.WindowingProfile.coefficients(overlap);
    got = [rise(:);fall(:);rise(:).^2+fall(:).^2];
    rows(ii) = localResult("wola",vectorID,want,got,1e-12, ...
        "independent_complementary_window");
end
end

function rows = localPAPR(root)
vectors = localRead(fullfile(root,"waveform_papr_test_vectors.csv"));
expected = localRead(fullfile(root,"expected_waveform_papr_analytical.csv"));
rows = repmat(localTemplate(),height(vectors),1);
for ii = 1:height(vectors)
    n = str2double(vectors.Length(ii));
    signalType = vectors.SignalType(ii);
    switch signalType
        case "constant"
            samples = ones(n,1);
        case "single_impulse"
            samples = [sqrt(n);zeros(n-1,1)];
        case "alternating"
            samples = (-1).^(0:n-1).';
        case "two_tone_time"
            index = (0:n-1).';
            samples = exp(1j*2*pi*index/n) + exp(1j*4*pi*index/n);
        otherwise
            samples = exp(1j*2*pi*(0:n-1).'/n);
    end
    measured = sixgr.phy.waveform.PAPRMeasurement.measure(samples,1);
    want = str2double(expected.ExpectedPAPR_dB( ...
        expected.VectorID == vectors.VectorID(ii)));
    rows(ii) = localResult("papr",vectors.VectorID(ii),want, ...
        measured.PAPR_dB,1e-10,"independent_analytical_power");
end
end

function rows = localSpectral(root)
vectors = localRead(fullfile(root,"waveform_spectral_test_vectors.csv"));
expected = localRead(fullfile(root,"expected_waveform_spectral_analytical.csv"));
rows = repmat(localTemplate(),height(vectors),1);
for ii = 1:height(vectors)
    nfft = str2double(vectors.Nfft(ii));
    tone = str2double(vectors.ToneBin(ii));
    amplitude = str2double(vectors.Amplitude(ii));
    samples = amplitude*exp(1j*2*pi*tone*(0:nfft-1).'/nfft);
    measured = sixgr.phy.waveform.SpectralMeasurement.measure( ...
        samples,str2double(vectors.SampleRate_Hz(ii)), ...
        "FFTSize",nfft,"AnalysisWindow",vectors.Window(ii), ...
        "OccupiedBand_Hz",[-inf inf],"GuardBands_Hz",[0 0]);
    row = expected(expected.VectorID == vectors.VectorID(ii),:);
    [~,peakOneBased] = max(measured.PSD);
    peakBin = mod(peakOneBased-1-floor(nfft/2),nfft);
    want = [str2double(row.ExpectedPeakBin); ...
        str2double(row.ExpectedIntegratedPower); ...
        str2double(row.ExpectedParsevalError)];
    got = [peakBin;measured.SpectralIntegralPower;measured.Error_dB];
    rows(ii) = localResult("spectral",vectors.VectorID(ii),want,got, ...
        1e-10,"independent_single_tone_parseval");
end
end

function row = localResult(family,id,want,got,tolerance,oracle)
want = double(want(:)); got = double(got(:));
if numel(want) ~= numel(got)
    mismatch = 1;
else
    mismatch = double(any(abs(want-got) > ...
        tolerance.*max(1,abs(want))));
end
row = localTemplate();
row.Family = string(family);
row.VectorID = string(id);
row.ExpectedDigest = sixgr.phy.waveform.WaveformHash.numeric(want);
row.ActualDigest = sixgr.phy.waveform.WaveformHash.numeric(got);
row.MismatchCount = mismatch;
row.OracleType = string(oracle);
row.Status = localPass(mismatch == 0);
end

function value = localNMSE(reference,actual)
value = sum(abs(actual(:)-reference(:)).^2)/max(sum(abs(reference(:)).^2),eps);
end

function value = localPipe(text)
value = str2double(split(string(text),"|"));
end

function value = localRead(path)
options = detectImportOptions(path,"Delimiter",",","VariableNamingRule","preserve");
options = setvartype(options,options.VariableNames,"string");
value = readtable(path,options);
end

function value = localPass(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function row = localTemplate()
row = struct("Family","","VectorID","","ExpectedDigest","", ...
    "ActualDigest","","MismatchCount",NaN,"OracleType","","Status","");
end
