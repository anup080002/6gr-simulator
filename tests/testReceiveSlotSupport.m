function ok=testReceiveSlotSupport()
% Independent sample-index enumeration; no simulated success is fabricated.
filters=zeros(17,2); filters([1 8 17],1)=[realmin 1 realmin];
cp=[11 repmat(9,1,13) 10 repmat(9,1,13)];
for slot=0:3
    for symbols={0,6,13,[0 13]}
        selected=symbols{1};
        e=sixgr.phy.waveform.receiveSlotSupport(filters,7,128,cp,14,slot,selected,.5);
        c=reshape(cp,14,[]); c=c(:,mod(slot,2)+1).';
        start=[0 cumsum(128+c(1:end-1))];
        source=[];
        for symbol=selected
            for tap=[0 7 16]
                source=[source start(symbol+1)+fix(.5*c(symbol+1))+(0:127)+7-tap]; %#ok<AGROW>
            end
        end
        assert(e.FirstRequiredSourceSample0RelativeToSlot==min(source) && ...
            e.LastRequiredSourceSample0RelativeToSlot==max(source));
        assert(e.RequiredPreviousSlots==double(min(source)<0));
        assert(e.RequiredFollowingSlots==double(max(source)>=sum(128+c)));
        assert(e.RequiredCommittedThroughTTI==slot+1+e.RequiredFollowingSlots);
        assert(~e.WaveformMeasured && ~e.ResidualISIICIIncluded && ~e.StatisticalCalibrationQualified);
    end
end
% A full-symbol CP violation is not automatically a following-SLOT delay.
interior=sixgr.phy.waveform.receiveSlotSupport(filters,7,128,cp,14,0,6,.5);
assert(~interior.ChannelCyclicPrefixSupport.CircularConvolutionSupported && ...
    interior.RequiredPreviousSlots==0 && interior.RequiredFollowingSlots==0);
% Correctly count >1 slot of memory and variable slot lengths.
long=zeros(4001,1); long([1 end])=1;
e=sixgr.phy.waveform.receiveSlotSupport(long,2000,128,cp,14,3,[0 13],.5);
assert(e.RequiredPreviousSlots==2 && e.RequiredFollowingSlots==2);
e=sixgr.phy.waveform.receiveSlotSupport(filters,7,128,18*ones(1,28),14,0,0:13,.5);
assert(e.RequiredPreviousSlots==0 && e.RequiredFollowingSlots==0);
fprintf('RECEIVE_SLOT_SUPPORT_PASS exact_sample_dependencies=1 interior_not_delayed=1 qualification=0\n');
ok=true;
end
