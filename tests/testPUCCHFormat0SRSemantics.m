function ok=testPUCCHFormat0SRSemantics(outputRoot)
% Independent reference sequence, not just mutually consistent TX/RX bugs.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceExists','Choose a new evidence directory.');
mkdir(outputRoot);
v=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/pucch_format0_sr_semantics.yaml');
assert(v.format==0 && all(ismember(v.harq_bit_counts,0:2)) && all(ismember(v.sr_values,[0 1])));
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(v.format,int8(1), ...
    'NSizeGrid',v.num_grid_prbs,'SCS',v.scs_khz,'RNTI',v.rnti, ...
    'ResourceID',v.resource_id,'ConfigurationEpoch',v.configuration_epoch);
threshold=sixgr.phy.pucch.resolveDetectionThreshold(f.Assignment);
rows={}; captures={};
for count=double(v.harq_bit_counts(:).')
    for value=0:2^count-1
        ack=int8(bitget(value,count:-1:1).');
        for sr=double(v.sr_values(:).')
            data=f.Report.Data; data.HARQACKReport=struct('Bits',ack);
            data.SchedulingRequestReports=struct('Bits',int8(sr));
            report=sixgr.phy.pucch.UCIReport(data);
            assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI( ...
                report,f.UEContext,f.FrameState);
            % Receiver owns counts from the test's independently declared
            % opportunity, never the transmitted UCI report or its bit values.
            context=sixgr.phy.pucch.UCIReportContext(struct( ...
                'ReportID',"independent_format0_h"+count, ...
                'ConfigurationEpoch',f.RRCContext.ConfigurationEpoch, ...
                'Sequence1Length',count+1,'Sequence2Length',0, ...
                'HARQACKBits',count,'SRBits',1,'CSIPart1Bits',0, ...
                'CSIPart2Bits',0,'PriorityIndex',0));
            receiverAssignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
                'ObservationID',context.ReportID,'ResourceID',f.Assignment.Resource.ID, ...
                'RNTI',v.rnti,'AbsoluteSlot0',0,'Source',"configured_format0_HARQ_SR_counts", ...
                'TimingSource',"declared_component_slot"),f.RRCContext,context);
            reference=nrPUCCH(f.Carrier,f.Assignment.Resource.toolboxConfig(),{ack,int8(sr)});
            expectedPresent=~isempty(reference);
            tx=[]; rx=[]; txError=""; rxError=""; txMatch=false; rxMatch=false;
            try
                tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,assignment,report);
                actual=tx.Grid(tx.PUCCHIndices);
                if expectedPresent
                    txMatch=isequal(size(actual),size(reference)) && max(abs(actual-reference))<1e-12;
                else
                    txMatch=~any(tx.Waveform(:));
                end
            catch cause
                txError=string(cause.identifier);
            end
            if expectedPresent
                % Feed the independently generated standard API sequence,
                % not this transmitter's potentially wrong sequence, to RX.
                mapped=sixgr.phy.pucch.PUCCHGridMapper.map(f.Carrier,f.Assignment,reference);
                waveform=sixgr.phy.waveform.ofdmModulate(f.Carrier,mapped.Grid);
                try
                    rx=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,f.Carrier,receiverAssignment,context, ...
                        'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation', ...
                        'DetectionThreshold',threshold);
                    rxMatch=rx.ReceiverUsable && rx.ReceiverOnlyAssignment && ...
                        ~rx.OraclePayloadBitsUsed && isequal(rx.DecodedSequence1,[ack;int8(sr)]);
                catch cause
                    rxError=string(cause.identifier);
                end
            end
            row=struct('HARQBits',count,'HARQValue',string(sprintf('%d',ack)), ...
                'SRValue',sr,'ExpectedTransmission',expectedPresent, ...
                'TXSequenceMatchesReference',txMatch,'TransmitErrorID',txError, ...
                'ReceiverCheckApplicable',expectedPresent,'RXMatchesIndependentReference',rxMatch, ...
                'ReceiverErrorID',rxError,'DetectionThreshold',threshold, ...
                'Source',string(v.evidence_scope));
            rows{end+1}=row; %#ok<AGROW>
            captures{end+1}=struct('Report',report,'Context',context,'ReferenceSymbols',reference, ...
                'ActualTransmitter',tx,'IndependentReferenceReceiver',rx); %#ok<AGROW>
        end
    end
end
results=struct2table(vertcat(rows{:}));
writetable(results,fullfile(outputRoot,'format0_sr_reference.csv'));
save(fullfile(outputRoot,'format0_sr_reference.mat'),'v','f','results','captures','threshold');
disp(results);
assert(all(results.TXSequenceMatchesReference) && ...
    all(results.RXMatchesIndependentReference(results.ReceiverCheckApplicable)), ...
    'sixgr:test:PUCCHFormat0SRSemanticsMismatch', ...
    'Format-0 HARQ/SR semantics must match independent reference sequences, including negative-SR silence.');
ok=true;
end
