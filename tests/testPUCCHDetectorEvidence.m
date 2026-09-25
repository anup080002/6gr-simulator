function ok=testPUCCHDetectorEvidence()
% Algebraic decision-boundary checks, not RF or statistical qualification.
% No scenario, waveform, noise, threshold policy or toolbox execution is set.
payloads={int8([]),int8(0),int8(1),int8([1;0]),ones(31,1,'int8')};
invalidMetrics={NaN,Inf,-Inf,[],[0.1 0.9],zeros(2),1+1i,'1',"1",true,{},struct()};
invalidCases=0; finiteCases=0; policyCases=0;
for format=0:4
    for k=1:numel(invalidMetrics)
        for j=1:numel(payloads)
            decision=sixgr.phy.pucch.PUCCHDetector.decide( ...
                format,invalidMetrics{k},1/2,payloads{j});
            assert(decision.DTX && ~decision.Detected && ~decision.DetectionMetricValid, ...
                'Invalid metrics must never become detected because decoded bits exist.');
            assert(isscalar(decision.DetectionMetric) && isreal(decision.DetectionMetric));
            assert(decision.DetectionOutcome=="unavailable");
            invalidCases=invalidCases+1;
        end
    end
    % Generic mathematical boundary vectors, not a replacement for YAML
    % policy. Preserve equality and every valid finite metric comparison.
    for threshold=linspace(0,1,5)
        for metric=[-eps,0,threshold-eps,threshold,threshold+eps,1,1+eps]
            for j=1:numel(payloads)
                decision=sixgr.phy.pucch.PUCCHDetector.decide(format,metric,threshold,payloads{j});
                assert(decision.DetectionMetricValid && decision.DTX==(metric<threshold) && ...
                    decision.Detected==(metric>=threshold) && decision.DetectionMetric==metric && ...
                    decision.DetectionThreshold==threshold);
                expected="detected";
                if metric<threshold, expected="dtx"; end
                assert(decision.DetectionOutcome==expected, ...
                    'Detection outcome cannot depend on candidate payload bits.');
                finiteCases=finiteCases+1;
            end
        end
    end
    for threshold={[],NaN,Inf,-Inf,-eps,1+eps,[0 1],1+1i,'1',"1",true,{},struct()}
        id='sixgr:phy:pucch:InvalidDetectionThreshold';
        if isempty(threshold{1}), id='sixgr:phy:pucch:MissingDetectionThreshold'; end
        localReject(@()sixgr.phy.pucch.PUCCHDetector.decide( ...
            format,1,threshold{1},int8(1)),id);
        policyCases=policyCases+1;
    end
end
% Scalar invalid evidence is retained; malformed vectors are not projected.
decision=sixgr.phy.pucch.PUCCHDetector.decide(0,Inf,1/2,int8(1));
assert(isinf(decision.DetectionMetric));
decision=sixgr.phy.pucch.PUCCHDetector.decide(0,[1 0],1/2,int8(1));
assert(isnan(decision.DetectionMetric));
selectionCases=localMetricSelection(invalidMetrics);
fprintf('PUCCH_DETECTOR_EVIDENCE_PASS invalid=%d finite=%d policy=%d RF=0 qualified=0\n', ...
    invalidCases,finiteCases,policyCases);
fprintf('PUCCH_METRIC_SELECTION_PASS cases=%d RF=0 qualified=0\n',selectionCases);
ok=true;
end

function count=localMetricSelection(invalidMetrics)
count=0;
% Exercise the very same selector called by PUCCHReceiver. A strong energy
% observation must not rescue an invalid required correlation metric.
for format=0:1
    for k=1:numel(invalidMetrics)
        metric=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
            format,false,invalidMetrics{k},99,1);
        decision=sixgr.phy.pucch.PUCCHDetector.decide(format,metric,0,int8(1));
        assert(decision.DTX && ~decision.DetectionMetricValid);
        count=count+1;
    end
end
for format=0:1
    for energyRatio=[invalidMetrics {-1}]
        metric=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
            format,false,1,energyRatio{1},1);
        decision=sixgr.phy.pucch.PUCCHDetector.decide(format,metric,0,int8(1));
        assert(decision.DTX && ~decision.DetectionMetricValid);
        count=count+1;
    end
    for ratio=[0 .25 1 2 9 1e12]
        for sequenceMetric=[0 .2 .5 1]
            expected=max(0,(ratio-1)/(ratio+1));
            if format<=1, expected=min(sequenceMetric,expected); end
            metric=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
                format,false,sequenceMetric,ratio,1);
            assert(isequal(metric,expected),'Finite-evidence selection must remain unchanged.');
            count=count+1;
        end
    end
end
% Noncoherent Format 0 does not consume noise/energy as evidence.
for sequenceMetric=[invalidMetrics {0,.2,1}]
    metric=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
        0,true,sequenceMetric{1},NaN,1);
    assert(isequaln(metric,sequenceMetric{1}));
    count=count+1;
end
% Formats 2--4 with 3--11 bits must use the toolbox normalized correlation
% statistic and must never be rescued by a strong energy observation.
for format=2:4
    for payloadBits=3:11
        [metric,source]=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
            format,false,.37,NaN,payloadBits);
        assert(metric==.37 && source=="toolbox_normalized_sequence_correlation");
        metric=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
            format,false,NaN,99,payloadBits);
        assert(isnan(metric),'Energy must not rescue missing short-UCI correlation evidence.');
        count=count+2;
    end
    % At 12 bits and above, nrPUCCHDecode does not define a correlation
    % metric; CRC validates content and energy provides presence evidence.
    [metric,source]=sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
        format,false,0,9,12);
    assert(metric==.8 && source=="normalized_excess_energy_crc_aided");
    count=count+1;
end
localReject(@()sixgr.phy.pucch.PUCCHDetector.selectMetric( ...
    2,false,.5,2,-1),'sixgr:phy:pucch:InvalidDetectorPayloadBitCount');
count=count+1;
end

function localReject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier); return;
end
error('test:MissingRejection','Expected %s.',id);
end
