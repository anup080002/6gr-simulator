function ok=testResearchIdealDelayedHARQ()
% Actual NACK/RV sequence/ACK, delayed process reuse and no double count.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
c=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'tests','fixtures','research_ideal_delayed_harq.yaml'));
s=c.toStruct(); state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
for d=["DL","UL"]
    if d=="DL", first=0; else, first=4; end
    h=sixgr.phy.research.IdealDelayedHARQ(s,d);
    h.advance(first); [p,tb,sc]=h.reserve(s,first);
    tx=sixgr.phy.research.SharedChannelLink.transmit(sc,first,tb,d,'HARQKey',p.HARQKey);
    h.transmitted(p,tx); options=h.receiveOptions(p);
    rx=sixgr.phy.research.SharedChannelLink.receive(sc,first,localNoisy(tx,0),d,options{:});
    assert(~rx.CRCPass && ~rx.HARQCombiningApplied);
    h.received(p,rx);
    localThrows(@()h.received(p,rx),'sixgr:research:DuplicateHARQReception');
    h.advance(first+1); [waiting,~,~]=h.reserve(s,first+1);
    assert(isempty(fieldnames(waiting)) && isempty(h.Feedback));
    assert(~h.Entity.onFeedback(h.RNTI,p.HARQ.HarqID,true,'SourceSlot',first-1,'FeedbackSlot',first+1));
    h.advance(first+4); assert(numel(h.Feedback)==1 && ~h.Feedback.CRCPass);
    changed=s; section="research_"+lower(d);
    changed.(section).num_layers=2;
    changed.(section).dmrs_port_set=[0 1];
    changed.(section).modulation='256QAM';
    changed.(section).target_code_rate=0.82;
    % A second transmission need not recover an almost-erased systematic RV.
    % Exercise the configured IR sequence; still require exact recovery within
    % its fixed maximum, with no decoder/noise/gate change to the actual run.
    for attempt=2:s.research_harq.max_transmissions
        attemptSlot=first+8*(attempt-1);
        h.advance(attemptSlot); [retx,repeated,sc]=h.reserve(changed,attemptSlot);
        assert(retx.HARQKey==p.HARQKey && retx.HARQ.RV==s.research_harq.rv_sequence(attempt) && retx.HARQ.IsRetransmission);
        assert(isequal(repeated,tb));
        assert(retx.Allocation.NumLayers==p.Allocation.NumLayers && ...
            retx.Allocation.Modulation==p.Allocation.Modulation && ...
            retx.Allocation.TargetCodeRate==p.Allocation.TargetCodeRate && ...
            retx.Allocation.TransportBlockSize==p.Allocation.TransportBlockSize && ...
            isequal(retx.Allocation.Precoder,p.Allocation.Precoder));
        tx=sixgr.phy.research.SharedChannelLink.transmit(sc,attemptSlot,repeated,d,'HARQKey',retx.HARQKey);
        h.transmitted(retx,tx); options=h.receiveOptions(retx);
        waveform=localNoisy(tx,40);
        rx=sixgr.phy.research.SharedChannelLink.receive(sc,attemptSlot,waveform,d,options{:});
        fprintf('HARQ_STRESS_ATTEMPT direction=%s attempt=%d RV=%d combined=%d CRC=%d bit_errors=%d\n', ...
            d,attempt,retx.HARQ.RV,rx.HARQCombiningApplied,rx.CRCPass,sum(rx.TransportBlock~=tb));
        assert(rx.HARQCombiningApplied);
        if attempt==2
            foreign=options; foreign{2}=retx.HARQKey+"_foreign";
            localThrows(@()sixgr.phy.research.SharedChannelLink.receive(sc,attemptSlot,waveform,d,foreign{:}), ...
                'sixgr:research:IncompatibleHARQSoftBuffer');
        end
        h.received(retx,rx); h.advance(attemptSlot+4);
        if rx.CRCPass, break; end
    end
    assert(rx.CRCPass && isequal(rx.TransportBlock,tb),'Exact recovery within the configured IR sequence is required.');
    T=h.Entity.getDeliveryLedger();
    assert(height(T)==attempt && sum(T.FirstSuccessDelivery)==1 && sum(T.CountedGoodputBits)==numel(tb));
    assert(h.pendingCount()==0 && isempty(h.Queue));
    assert(~h.Entity.onFeedback(h.RNTI,retx.HARQ.HarqID,true,'SourceSlot',attemptSlot,'FeedbackSlot',attemptSlot+4));
    h.advance(attemptSlot+8); [fresh,~,~]=h.reserve(changed,attemptSlot+8);
    assert(fresh.HARQKey~=p.HARQKey && ~fresh.HARQ.IsRetransmission);
    assert(fresh.Allocation.NumLayers==2 && fresh.Allocation.Modulation=="256QAM" && ...
        fresh.Allocation.TargetCodeRate==changed.(section).target_code_rate);
    assert(h.Feedback(1).AttemptIndex==1 && all([h.Feedback(2:end).AttemptIndex]>1));
    nextOptions=h.receiveOptions(fresh); assert(isempty(nextOptions{4}));
    fprintf('RESEARCH_IDEAL_HARQ_COMPONENT_PASS direction=%s attempts=%d NACK_ACK=1 unique_bits=%d feedback_delay_slots=%d\n', ...
        d,attempt,numel(tb),s.research_harq.feedback_delay_slots);
end
ok=true;
fprintf('RESEARCH_IDEAL_DELAYED_HARQ_PASS physical_feedback_waveform=0 final_throughput_acceptance=0\n');
end

function waveform=localNoisy(tx,snr)
variance=(1/tx.Allocation.NumLayers)/10^(snr/10)/tx.OFDM.SampleToGridNoiseVarianceGain;
waveform=tx.Waveform+sqrt(variance/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
end

function localThrows(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection %s.',id);
end
