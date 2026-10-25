function ok=testPBCHDecodedIdentity()
% Actual coded PBCH grids: both half frames, full kSSB and original CRC.
% Component qualification only: no RF, acquisition search or statistical claim.
assert(exist('nrBCH','file')==2,'test:MissingToolbox','Native BCH required.');
cfg=sixgr.config.defaultConfig();cfg.run.strictMode=true;
ncell=17; rows=struct([]); capture=struct([]);
for Lmax=[4 8 64]
    if Lmax==64, values=[0 11 12 15]; else,values=[0 15 16 23 24 31];end
    for half=0:1
        for kssb=values
            if Lmax==4,ssb=2;elseif Lmax==8,ssb=6;else,ssb=43;end
            [grid,bits]=localGrid(ncell,Lmax,half,ssb,kssb,half);
            [pb,info]=sixgr.phy.dl.PBCH_Recovery(grid, ...
                struct('NCellID',ncell,'Lmax',Lmax),cfg, ...
                'CandidateSelection','dmrs_metric_then_single_decode');
            assert(pb.Ok&&pb.BCHCRCValid&&pb.CandidateIdentityConsistent&&pb.ErrFlag==0);
            assert(isequal(int8(pb.TransportBlock),bits)&&pb.SSBIndex==ssb&&pb.HalfFrame==half);
            assert(pb.DecodedKSSB==kssb&&pb.MIBKSSBSubcarrierOffset==kssb&&pb.k_SSB==kssb);
            assert(pb.MIBKSSBLow4==mod(kssb,16)&&pb.Lmax==Lmax&& ...
                pb.KSSBContractVersion=="sixgr_decoded_kssb/v2");
            assert(pb.DecodedMIBState.SSBSubcarrierOffset==mod(kssb,16), ...
                'Original four-bit MIB semantic state must not become the full kSSB.');
            if Lmax==64
                assert(~pb.KSSBHighBitApplicable&&isnan(pb.PBCHKSSBMSB)&&pb.PBCHKSSBHighContribution==0);
            else
                assert(pb.KSSBHighBitApplicable&&pb.PBCHKSSBMSB==floor(kssb/16)&& ...
                    pb.PBCHKSSBHighContribution==16*floor(kssb/16));
            end
            assert(info.PolarDecodesAttempted==1);
            admission=localAdmission(pb);
            assert(sixgr.truth.pbchAcquisitionAccepted(admission));
            row=struct('Lmax',Lmax,'HalfFrame',half,'SSBIndex',ssb,'KSSB',kssb, ...
                'DecodedKSSB',pb.DecodedKSSB,'BCHCRCValid',pb.BCHCRCValid, ...
                'CandidateIdentityConsistent',pb.CandidateIdentityConsistent);
            record=struct('Grid',grid,'Bits',bits,'Receiver',pb,'Info',info);
            if isempty(rows)
                rows=row; capture=record;
            else
                rows(end+1)=row; capture(end+1)=record; %#ok<AGROW>
            end
        end
    end
end
% CRC-aided legacy enumeration must also reach second-half-frame hypotheses.
[grid,~]=localGrid(ncell,4,1,2,23,1);
[legacy,~]=sixgr.phy.dl.PBCH_Recovery(grid,struct('NCellID',ncell,'Lmax',4),cfg);
assert(legacy.Ok&&legacy.SSBIndex==2&&legacy.HalfFrame==1&&legacy.iBar_SSB==6);
% Real native CRC success does not authorize a contradictory DM-RS half frame.
[grid,~]=localGrid(ncell,4,0,2,23,1);
[mismatch,~]=sixgr.phy.dl.PBCH_Recovery(grid,struct('NCellID',ncell,'Lmax',4),cfg, ...
    'CandidateSelection','dmrs_metric_then_single_decode');
assert(mismatch.BCHCRCValid&&mismatch.ErrFlag==0&&~mismatch.Ok&& ...
    ~mismatch.CandidateIdentityConsistent&&isnan(mismatch.DecodedKSSB)&& ...
    isempty(fieldnames(mismatch.DecodedMIBState)));
rejected=localAdmission(mismatch);
assert(rejected.CRCPass==1 && ~sixgr.truth.pbchAcquisitionAccepted(rejected));
accepted=localAdmission(legacy); accepted.Status="FAIL"; % SI may fail after a valid MIB.
assert(sixgr.truth.pbchAcquisitionAccepted(accepted));
for field=["BCHCRCValid","MIBDecoded","CandidateIdentityConsistent","SSBIdentityVerified"]
    bad=accepted; bad.(field)=NaN;
    assert(~sixgr.truth.pbchAcquisitionAccepted(bad));
    assert(~sixgr.truth.pbchAcquisitionAccepted(removevars(accepted,field)));
    bad.(field)=2; assert(~sixgr.truth.pbchAcquisitionAccepted(bad));
end
bad=accepted; bad.Crash=1;
assert(sixgr.truth.pbchAcquisitionAccepted(bad), ...
    'A later combined SI exception cannot erase original accepted BCH evidence.');
assert(isequal(sixgr.truth.pbchAcquisitionAccepted([accepted;rejected]),[true;false]));
% No-signal trials cannot acquire semantic authority from decoded garbage.
[empty,~]=sixgr.phy.dl.PBCH_Recovery(complex(zeros(240,4)), ...
    struct('NCellID',ncell,'Lmax',8),cfg,'CandidateSelection','dmrs_metric_then_single_decode');
assert(~empty.Ok&&isnan(empty.DecodedKSSB));
[emptyLegacy,emptyInfo]=sixgr.phy.dl.PBCH_Recovery(complex(zeros(240,4)), ...
    struct('NCellID',ncell,'Lmax',8),cfg);
assert(~emptyLegacy.Ok&&emptyInfo.PolarDecodesAttempted==numel(emptyInfo.PerCandidate)+1, ...
    'The debug best-candidate re-decode is an actual polar-decoder invocation.');
for invalid={[],[0;1],2,NaN,'1',1i}
    localReject(@()sixgr.phy.broadcast.resolveDecodedKSSB(7,invalid{1},8,true));
end
for invalid={[],16,-1,0.5,NaN,'1',true}
    localReject(@()sixgr.phy.broadcast.resolveDecodedKSSB(invalid{1},1,8,true));
end
localReject(@()sixgr.phy.broadcast.resolveDecodedKSSB(7,1,64,true));
notAccepted=sixgr.phy.broadcast.resolveDecodedKSSB([],[],8,false);
assert(isnan(notAccepted.DecodedKSSB)&&isnan(notAccepted.MIBKSSBLow4));
for invalid={'1',true,NaN,[1 2],-1,1008}
    localReject(@()sixgr.phy.dl.PBCH_Recovery(grid, ...
        struct('NCellID',invalid{1},'Lmax',4),cfg),'sixgr:phy:ia:InvalidCellID');
end
for invalid={char(8),'8',true,NaN,[4 8],10}
    localReject(@()sixgr.phy.dl.PBCH_Recovery(grid, ...
        struct('NCellID',17,'Lmax',invalid{1}),cfg),'sixgr:phy:ia:InvalidLmax');
end
% Preserve native parameter rejection: never retry with a default estimator.
nativeError="";
try
    nrChannelEstimate(grid,grid,'AveragingWindow',[2 1]);
catch err
    nativeError=string(err.identifier);
end
assert(strlength(nativeError)>0);
localReject(@()sixgr.phy.dl.PBCH_Recovery(grid, ...
    struct('NCellID',17,'Lmax',4),cfg,'AveragingWindow',[2 1]),nativeError);
folder=fullfile(pwd,'results','validation','pbch_decoded_identity',char(java.util.UUID.randomUUID()));
mkdir(folder);
save(fullfile(folder,'original_receivers.mat'),'capture','legacy','mismatch','empty','cfg','-v7.3');
sixgr.util.csvWriteTable(fullfile(folder,'native_identity.csv'),struct2table(rows),'PreserveSchema',true);
fprintf('PBCH_DECODED_IDENTITY_PASS native_cases=%d folder=%s\n',numel(rows),folder);
ok=true;
end

function row=localAdmission(pb)
% Native decoder evidence only; declared SSB-grid identity matches this
% component fixture, not a claim of independent timing/cell search.
row=struct2table(struct('BCHCRCValid',pb.BCHCRCValid,'CRCPass',double(pb.ErrFlag==0), ...
    'MIBDecoded',~isempty(fieldnames(pb.DecodedMIBState)), ...
    'CandidateIdentityConsistent',pb.CandidateIdentityConsistent, ...
    'SSBIdentityVerified',pb.CandidateIdentityConsistent,'Status',"PASS", ...
    'Crash',0,'Skipped',0));
end

function [grid,bits]=localGrid(cell,Lmax,half,ssb,kssb,dmrsHalf)
bits=zeros(24,1,'int8'); bits(8)=1;
bits(9:12)=int8(bitget(uint8(mod(kssb,16)),4:-1:1)).';
if Lmax==64,index=ssb;else,index=kssb;end
coded=nrBCH(bits,12,half,Lmax,index,cell);
v=mod(ssb,8);if Lmax==4,v=mod(ssb,4);end
ibar=v;if Lmax==4,ibar=v+4*dmrsHalf;end
grid=complex(zeros(240,4));
grid(nrPSSIndices)=nrPSS(mod(cell,3));
grid(nrSSSIndices)=nrSSS(cell);
grid(nrPBCHDMRSIndices(cell))=nrPBCHDMRS(cell,ibar);
grid(nrPBCHIndices(cell))=nrPBCH(coded,cell,v);
end

function localReject(action,expected)
if nargin<2,expected='sixgr:phy:broadcast:InvalidKSSBEvidence';end
try,action();catch err
    assert(strcmp(err.identifier,expected),'Unexpected rejection: %s',err.identifier);return;
end
error('test:MissingKSSBRejection','Malformed original operands were accepted.');
end
