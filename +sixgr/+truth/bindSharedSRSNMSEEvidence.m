function row=bindSharedSRSNMSEEvidence(row,output)
% Copy independent scoring metadata after the practical SRS receiver.
% This does not estimate a channel or fit gain.  When the independent
% reference excludes the receiver LO, the selected qualification score may
% remove one explicitly recorded unit-magnitude common phase.  The raw
% complex-plane score remains exported beside it.
assert(istable(row) && height(row)==1 && ...
    all(ismember({'NMSE_dB','TrueChannelNMSE_dB','NMSEReferenceSource'}, ...
    row.Properties.VariableNames)), ...
    'sixgr:truth:InvalidSRSScoringRow','One actual SRS trial row is required.');
score=sixgr.util.structGet(output,'ChannelNMSEScoring',struct());
row.NMSEScoringAvailable=false;
row.ChannelNMSEComparedComplexValues=0;
row.ChannelNMSEPilotResourceCount=0;
row.ChannelNMSEReferencePlane="unavailable";
row.ChannelNMSEReferenceIncludesRFImpairments=NaN;
row.ChannelNMSEErrorEnergy=NaN;
row.ChannelNMSEReferenceEnergy=NaN;
row.RawChannelNMSE_dB=NaN;
row.RawChannelNMSEErrorEnergy=NaN;
row.RawChannelNMSEReferenceEnergy=NaN;
row.ChannelNMSEGainFitted=false;
row.ChannelNMSEPhaseAligned=false;
row.ChannelNMSEGainOrPhaseFitted=false;
row.ChannelNMSECommonPhaseRotation_rad=NaN;
row.ChannelNMSEQualificationMode="unavailable";
row.ChannelNMSEReceiverTimingIncluded=false;
row.ChannelNMSERecordedReceiverTimingOffset_samples=NaN;
row.ChannelNMSEReceiverCFOIncluded=false;
row.ChannelNMSEExecutedReceiverCFO_Hz=NaN;
row.PreRXClockChannelNMSE_dB=NaN;
if isstruct(score) && isscalar(score) && isempty(fieldnames(score))
    assert(isnan(row.NMSE_dB) && isnan(row.TrueChannelNMSE_dB), ...
        'sixgr:truth:MissingSRSNMSEScoring','A finite shared SRS score cannot lack its independent scoring record.');
    return;
end
required={'Available','dB','ComparedComplexValueCount','PilotResourceCount', ...
    'NumReceiveAntennas','GainOrPhaseFitted','MissingValuesDiscarded'};
assert(isstruct(score) && isscalar(score) && all(isfield(score,required)), ...
    'sixgr:truth:MissingSRSNMSEScoring','The independent scoring record is incomplete.');
reference=sixgr.util.structGet(output,'ChannelNMSEReferenceEvidence',struct());
assert(isstruct(reference) && isscalar(reference) && all(isfield(reference, ...
    {'Source','ReferencePlane','RFImpairmentsIncluded','ReceiverEstimatorInput','GainOrPhaseFitted'})), ...
    'sixgr:truth:MissingSRSNMSEReference','Scoring requires its actual reference-plane evidence.');
phaseAligned=logical(sixgr.util.structGet(score,'PhaseAligned',false));
gainFitted=logical(sixgr.util.structGet(score,'GainFitted',false));
phaseContractOk=(~phaseAligned && ~score.GainOrPhaseFitted) || ...
    (phaseAligned && score.GainOrPhaseFitted && ~gainFitted && ...
    logical(sixgr.util.structGet(reference,'ComparisonPhaseAligned',false)) && ...
    ~logical(sixgr.util.structGet(reference,'ComparisonGainFitted',true)));
assert(isequal(score.Available,true) && phaseContractOk && ...
    ~score.MissingValuesDiscarded && ~reference.ReceiverEstimatorInput && ...
    ~reference.GainOrPhaseFitted && ...
    isequaln(row.NMSE_dB,score.dB) && isequaln(row.TrueChannelNMSE_dB,score.dB) && ...
    string(row.NMSEReferenceSource)==string(reference.Source) && ...
    strlength(string(reference.Source))>0 && strlength(string(reference.ReferencePlane))>0, ...
    'sixgr:truth:InconsistentSRSNMSEScoring','Scoring values, availability and reference provenance must agree.');
validateattributes(score.PilotResourceCount,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(score.NumReceiveAntennas,{'numeric'},{'scalar','integer','positive','finite'});
assert(score.ComparedComplexValueCount==score.PilotResourceCount*score.NumReceiveAntennas, ...
    'sixgr:truth:IncompleteSRSNMSEScoring','Every scored pilot and receive branch must be counted.');
row.NMSEScoringAvailable=score.Available;
[row.ChannelNMSEErrorEnergy,row.ChannelNMSEReferenceEnergy]=localScoringEnergies(score);
row.ChannelNMSEComparedComplexValues=double(score.ComparedComplexValueCount);
row.ChannelNMSEPilotResourceCount=double(score.PilotResourceCount);
row.ChannelNMSEReferencePlane=string(reference.ReferencePlane);
row.ChannelNMSEReferenceIncludesRFImpairments=double(reference.RFImpairmentsIncluded);
row.ChannelNMSEGainFitted=gainFitted;
row.ChannelNMSEPhaseAligned=phaseAligned;
row.ChannelNMSEGainOrPhaseFitted=logical(score.GainOrPhaseFitted);
row.ChannelNMSECommonPhaseRotation_rad=double(sixgr.util.structGet( ...
    score,'CommonPhaseRotation_rad',NaN));
row.ChannelNMSEQualificationMode=string(sixgr.util.structGet( ...
    output,'ChannelNMSEQualificationMode', ...
    localPhaseMode(phaseAligned)));
row.ChannelNMSEReceiverTimingIncluded=logical(sixgr.util.structGet(reference,'ReceiverTimingIncluded',false));
row.ChannelNMSEReceiverCFOIncluded=logical(sixgr.util.structGet(reference,'ReceiverCFOIncluded',false));
if row.ChannelNMSEReceiverTimingIncluded
    delay=double(reference.RecordedReceiverTimingOffset_samples);
    validateattributes(delay,{'double'},{'scalar','real','finite','integer','nonnegative'});
    row.ChannelNMSERecordedReceiverTimingOffset_samples=delay;
end
if row.ChannelNMSEReceiverCFOIncluded
    hz=double(reference.ExecutedReceiverCFO_Hz);
    validateattributes(hz,{'double'},{'scalar','real','finite'});
    row.ChannelNMSEExecutedReceiverCFO_Hz=hz;
end
row.PreRXClockChannelNMSE_dB=double(sixgr.util.structGet(output,'PreRXClockChannelNMSE_dB',NaN));
raw=sixgr.util.structGet(output,'RawChannelNMSEScoring',struct());
if isstruct(raw) && isscalar(raw) && ~isempty(fieldnames(raw))
    assert(all(isfield(raw,{'Available','dB','GainOrPhaseFitted', ...
        'MissingValuesDiscarded','ComparedComplexValueCount'})) && ...
        raw.Available && ~raw.GainOrPhaseFitted && ...
        ~raw.MissingValuesDiscarded && ...
        raw.ComparedComplexValueCount==score.ComparedComplexValueCount, ...
        'sixgr:truth:InvalidRawSRSNMSEScoring', ...
        'The retained raw SRS NMSE must be complete and must not fit gain or phase.');
    row.RawChannelNMSE_dB=double(raw.dB);
    [row.RawChannelNMSEErrorEnergy,row.RawChannelNMSEReferenceEnergy]=localScoringEnergies(raw);
end
end

function [numerator,denominator]=localScoringEnergies(score)
assert(all(isfield(score,{'ErrorEnergy','ReferenceEnergy'})), ...
    'sixgr:truth:MissingSRSNMSEEnergy','Retain the actual scoring operands; do not reconstruct them from NMSE.');
numerator=double(score.ErrorEnergy); denominator=double(score.ReferenceEnergy);
validateattributes(numerator,{'double'},{'scalar','real','finite','nonnegative'});
validateattributes(denominator,{'double'},{'scalar','real','finite','positive'});
expected=10*log10(numerator/denominator);
assert(isequaln(expected,double(score.dB)) || ...
    (isfinite(expected) && isfinite(score.dB) && abs(expected-score.dB)<1e-10), ...
    'sixgr:truth:InconsistentSRSNMSEEnergy','Exported NMSE must equal its own measured error/reference energy ratio.');
end

function mode=localPhaseMode(phaseAligned)
if phaseAligned
    mode="common_receiver_LO_phase_equivalent_no_gain_fit";
else
    mode="raw_complex_plane_aligned";
end
end
