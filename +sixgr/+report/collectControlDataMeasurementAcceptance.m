function T=collectControlDataMeasurementAcceptance(dl,ul,packets,sdus)
% Family-specific audit metadata, NOT a primary measurement or qualification.
% Every PASS states its exact operands; valid radio failures are not crashes.
arguments
    dl table
    ul table
    packets table = table()
    sdus table = table()
end
p=struct('Family',"",'Direction',"",'Status',"NOT_EXERCISED", ...
    'Reason',"no_original_rows",'Numerator',NaN,'Denominator',NaN, ...
    'Value',NaN,'Unit',"",'SourceRows',0,'EligibleRows',0, ...
    'PhysicalFailures',NaN,'QualificationScope',"retained_operand_consistency_only", ...
    'StatisticallyQualified',false);
T=struct2table(repmat(p,0,1));
for direction=["DL","UL"]
    rows=dl; if direction=="UL", rows=ul; end
    for family=["information_BER","attempt_BLER","unique_transport_goodput", ...
            "HARQ_retry_population","packet_latency","receiver_compute_time", ...
            "spatial_application_identity"]
        r=p; r.Family=family; r.Direction=direction; r.SourceRows=height(rows);
        if isempty(rows), T=[T;struct2table(r)]; continue; end %#ok<AGROW>
        r.Reason="missing_original_operands";
        switch family
            case "information_BER"
                [a,okA]=column(rows,'BitErrors'); [b,okB]=column(rows,'BitsCompared');
                if okA&&okB
                    eligible=isfinite(a)&isfinite(b)&b>0;
                    r.EligibleRows=nnz(eligible);
                    invalid=isinf(a)|isinf(b)| ...
                        (isfinite(a)&(a<0|a~=fix(a)))| ...
                        (isfinite(b)&(b<0|b~=fix(b)))| ...
                        (isfinite(a)&isfinite(b)&a>b);
                    if any(invalid), r=fail(r,"invalid_compared_bit_counts");
                    elseif any(eligible)
                        r=pass(r,sum(a(eligible)),sum(b(eligible)),"information_bit_error_ratio", ...
                            "actual_information_bit_comparator_counts_not_CRC_or_TBS");
                        if ~all(eligible)
                            r.Status="PARTIAL";
                            r.Reason="only_reported_compared_bit_population_available_other_rows_unavailable_or_uncompared";
                        end
                    end
                end
            case "attempt_BLER"
                [crc,a]=column(rows,'CRCPass'); [crash,b]=column(rows,'Crash');
                [attempt,c]=column(rows,'DecodeAttempted');
                if a&&b&&c
                    eligible=crash==0&attempt==1&isfinite(crc);
                    r.EligibleRows=nnz(eligible);
                    malformed=isinf(crash)|isinf(attempt)|isinf(crc)| ...
                        (isfinite(crash)&~ismember(crash,[0 1]))| ...
                        (isfinite(attempt)&~ismember(attempt,[0 1]))| ...
                        (isfinite(crc)&~ismember(crc,[0 1]));
                    if any(malformed), r=fail(r,"nonbinary_attempt_crash_or_CRC_flags");
                    elseif any(eligible)
                        r=pass(r,nnz(eligible&crc==0),nnz(eligible),"failed_attempt_fraction", ...
                            "actual_decoder_attempts_excluding_software_failures");
                        r.PhysicalFailures=r.Numerator;
                        if any(isnan(crash)|isnan(attempt)|(crash==0&attempt==1&isnan(crc)))
                            r.Status="PARTIAL";
                            r.Reason="measured_decoder_population_with_other_unavailable_attempt_or_CRC_operands";
                        end
                    end
                end
            case "unique_transport_goodput"
                [bits,a]=column(rows,'UniqueDeliveredTBBits'); [duration,b]=column(rows,'AirInterfaceTTI_ms');
                if a&&b&&ismember('TransportGoodputKey',rows.Properties.VariableNames)
                    keys=string(rows.TransportGoodputKey);
                    eligible=isfinite(bits)&isfinite(duration)&duration>0&~ismissing(keys)&strlength(keys)>0;
                    r.EligibleRows=nnz(eligible); positive=eligible&bits>0;
                    if any(eligible&(bits<0|bits~=fix(bits))) || ...
                            numel(unique(keys(positive)))~=nnz(positive)
                        r=fail(r,"invalid_or_repeated_unique_delivery_credit");
                    elseif all(eligible)
                        r=pass(r,sum(bits),sum(duration)/1000,"bit_per_second_active_trial_exposure", ...
                            "unique_first_success_transport_bits_not_application_delivery_or_wall_time");
                    end
                end
            case "HARQ_retry_population"
                [retry,ok]=column(rows,'IsRetransmission');
                if ok
                    r.EligibleRows=nnz(retry==1);
                    if r.EligibleRows==0, r.Reason="no_executed_retransmissions";
                    else, r.Reason="retry_rows_exist_terminal_and_soft_buffer_lineage_not_audited"; end
                end
            case "packet_latency"
                r.Reason="requires_original_enqueue_and_completed_reassembly_delivery_clocks";
                if ~isempty(packets)&&ismember('Direction',packets.Properties.VariableNames)
                    own=packets(string(packets.Direction)==direction,:);
                    [complete,hasComplete]=column(own,'ReassemblyCompleteFlag');
                    [remaining,hasRemaining]=column(own,'RemainingBits');
                    if hasComplete&&~isempty(own)&&~any(complete==1)
                        r.Reason="no_completed_application_packet_latency_population";
                        if hasRemaining&&all(remaining>0)
                            r.Reason="all_offered_application_packets_incomplete_censored";
                        end
                        if ~isempty(sdus)&&all(ismember({'Direction','DeliveryEvidenceMode', ...
                                'ProtocolPayloadSameWaveformTruth'},sdus.Properties.VariableNames))
                            mapped=sdus(string(sdus.Direction)==direction,:);
                            if ~isempty(mapped)&&all(mapped.ProtocolPayloadSameWaveformTruth==0)&& ...
                                    all(string(mapped.DeliveryEvidenceMode)=="CRC_CONFIRMED_PACKET_MAPPING")
                                r.Reason=r.Reason+";CRC_mapping_not_decoded_application_fragments";
                            end
                        end
                    end
                end
            case "receiver_compute_time"
                [elapsed,ok]=column(rows,'ComputeLatency_ms');
                if ok&&ismember('ComputeLatencySource',rows.Properties.VariableNames)
                    sources=string(rows.ComputeLatencySource);
                    eligible=isfinite(elapsed)&elapsed>=0&sources=="receiver_instrumented_ldpc_decode";
                    r.EligibleRows=nnz(eligible);
                    if any(eligible)
                        r=pass(r,sum(elapsed(eligible)),nnz(eligible),"mean_host_decode_milliseconds", ...
                            "instrumented_host_duration_not_packet_latency_or_operation_complexity");
                    end
                end
            case "spatial_application_identity"
                r.Reason="requires_exact_received_report_DCI_frozen_and_executed_operator_join";
        end
        T=[T;struct2table(r)]; %#ok<AGROW>
    end
end
end

function [v,ok]=column(T,name)
ok=ismember(name,T.Properties.VariableNames); v=nan(height(T),1);
if ~ok, return; end
x=T.(name); ok=(isnumeric(x)||islogical(x))&&isreal(x)&&size(x,2)==1;
if ok, v=double(x); end
end
function r=pass(r,n,d,unit,reason)
r.Status="PASS"; r.Reason=reason; r.Numerator=n; r.Denominator=d;
r.Value=n/d; r.Unit=unit;
end
function r=fail(r,reason)
r.Status="FAIL"; r.Reason=reason;
end
