classdef PHYDiagnosticChannelGrid
    % Lossless compact ownership of a large measured Hest diagnostic panel.
    % Rows are materialized one complete RX/TX frequency/time plane at a
    % time. This is storage/serialization only, never a receiver shortcut.
    methods (Static)
        function grid=pack(hest,template,gridHash)
            hest=complex(double(hest));
            shape=size(hest); shape(end+1:4)=1;
            assert(numel(shape)==4 && istable(template) && height(template)==1, ...
                'sixgr:link:PHYDiagnosticGridShape','Require one measured four-dimensional tensor and one schema template.');
            grid=struct('Contract',"PHYDiagnosticChannelGrid/v1",'Tensor',hest, ...
                'Shape',shape,'RowCount',numel(hest),'Template',template, ...
                'GridSHA256',string(gridHash),'ArraySHA256', ...
                string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(hest)));
        end

        function validate(grid,snapshot)
            assert(isstruct(grid) && isscalar(grid) && ...
                all(isfield(grid,{'Contract','Tensor','Shape','RowCount','Template','GridSHA256','ArraySHA256'})) && ...
                string(grid.Contract)=="PHYDiagnosticChannelGrid/v1", ...
                'sixgr:link:PHYDiagnosticGridContract','Require the complete measured-grid contract.');
            shape=size(grid.Tensor); shape(end+1:4)=1;
            assert(isequal(shape,grid.Shape) && numel(grid.Tensor)==grid.RowCount && ...
                grid.RowCount>0 && istable(grid.Template) && height(grid.Template)==1 && ...
                string(grid.ArraySHA256)==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(grid.Tensor)), ...
                'sixgr:link:PHYDiagnosticGridIntegrity','Measured grid dimensions and sample hash must remain unchanged.');
            T=snapshot.SourceTable;
            fields={'SnapshotID','Direction','UEIndex','RNTI','Frame','Slot','TBId'};
            for k=1:numel(fields)
                field=fields{k};
                assert(isequaln(grid.Template.(field),T.(field)(1,:)), ...
                    'sixgr:link:PHYDiagnosticGridIdentity','Grid and bounded panels must belong to the same trial.');
            end
            assert(grid.Template.Panel=="channel_estimate_grid" && ...
                grid.Template.Series=="receiver_hest_exact_tensor" && ...
                isequal(grid.Template.Properties.VariableNames,T.Properties.VariableNames), ...
                'sixgr:link:PHYDiagnosticGridSchema','Retain the canonical full-grid CSV schema.');
        end

        function T=rows(grid,rxIndex,txIndex)
            shape=grid.Shape;
            validateattributes(rxIndex,{'numeric'},{'scalar','integer','>=',1,'<=',shape(3)});
            validateattributes(txIndex,{'numeric'},{'scalar','integer','>=',1,'<=',shape(4)});
            % Complete K-by-L planes preserve unwrap continuity in both
            % axes. Do not unwrap independent arbitrary linear chunks.
            h=grid.Tensor(:,:,rxIndex,txIndex); n=numel(h);
            [k0,l0]=ndgrid(0:shape(1)-1,0:shape(2)-1);
            [mag,wrapped,frequencyPhase,timePhase]=localPolar(h);
            df=nan(size(h)); dt=nan(size(h));
            if shape(1)>1, df(2:end,:)=diff(frequencyPhase,1,1); end
            if shape(2)>1, dt(:,2:end)=diff(timePhase,1,2); end
            T=grid.Template(ones(n,1),:);
            offset=((txIndex-1)*shape(3)+rxIndex-1)*n;
            T.PointIndex=offset+(1:n).';
            T.SubcarrierIndex=k0(:); T.OFDMSymbolIndex=l0(:);
            T.MatlabSubcarrierIndex=k0(:)+1; T.MatlabOFDMSymbolIndex=l0(:)+1;
            start=double(T.NStartGrid(1)); if ~isfinite(start), start=0; end
            T.ResourceBlockIndex=start+floor(k0(:)./12);
            T.SubcarrierInResourceBlock=mod(k0(:),12);
            scs=1000*double(T.SCS_kHz(1));
            if isfinite(scs) && scs>0
                T.FrequencyOffset_Hz=(k0(:)-(shape(1)-1)/2)*scs;
                fc=double(T.CarrierFrequency_Hz(1));
                if isfinite(fc), T.AbsoluteFrequency_Hz=fc+T.FrequencyOffset_Hz; end
            end
            T.RxPortIndex0Based(:)=rxIndex-1; T.TxPortIndex0Based(:)=txIndex-1;
            T.RxAntennaIndex(:)=rxIndex; T.TxPortIndex(:)=txIndex;
            T.XValue=k0(:); T.YValue=l0(:);
            T.XUnit(:)="zero_based_subcarrier_index"; T.YUnit(:)="zero_based_ofdm_symbol_index";
            T.IValue=real(h(:)); T.QValue=imag(h(:));
            T.MagnitudeLinear=abs(h(:)); T.Magnitude_dB=mag(:);
            T.PowerLinear=abs(h(:)).^2; T.Power_dB=mag(:);
            T.MagnitudeValueStatus(:)="exact_receiver_estimate_log_magnitude";
            T.PhaseValueStatus(:)="defined_nonzero_receiver_estimate";
            zero=abs(h(:))==0;
            T.MagnitudeValueStatus(zero)="negative_infinity_exact_zero_receiver_estimate";
            T.PhaseValueStatus(zero)="undefined_zero_receiver_estimate";
            T.Phase_deg=rad2deg(wrapped(:)); T.WrappedPhase_rad=wrapped(:);
            T.UnwrappedPhaseFrequency_rad=frequencyPhase(:); T.UnwrappedPhaseTime_rad=timePhase(:);
            T.PhaseDeltaFrequency_rad=df(:); T.PhaseDeltaTime_rad=dt(:);
            T.GridKind(:)="receiver_channel_estimate"; T.GridSHA256(:)=grid.GridSHA256;
        end
    end
end

function [magnitude,wrapped,frequencyPhase,timePhase]=localPolar(h)
magnitude=20.*log10(abs(h)); wrapped=angle(h);
wrapped(abs(h)==0 | ~isfinite(real(h)) | ~isfinite(imag(h)))=NaN;
frequencyPhase=localUnwrap(wrapped,1); timePhase=localUnwrap(wrapped,2);
end

function phase=localUnwrap(wrapped,dimension)
order=1:ndims(wrapped); order([1 dimension])=order([dimension 1]);
values=permute(wrapped,order); shape=size(values);
values=reshape(values,shape(1),[]);
for column=1:size(values,2)
    defined=isfinite(values(:,column));
    edges=diff([false;defined;false]); starts=find(edges==1); stops=find(edges==-1)-1;
    for segment=1:numel(starts)
        selected=starts(segment):stops(segment);
        values(selected,column)=unwrap(values(selected,column));
    end
end
phase=ipermute(reshape(values,shape),order);
end
