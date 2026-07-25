#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,math,sys,tempfile
from pathlib import Path
try:
    from PIL import Image,ImageDraw,ImageStat
except ImportError as e:raise SystemExit('Pillow required') from e
HERE=Path(__file__).resolve().parent

def truth(v):
    return str(v).strip().upper() in {'1','TRUE','YES','PASS'}
def finite(v):
    try:x=float(str(v).strip())
    except:return None
    return x if math.isfinite(x) else None
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def readcsv(p):
    with p.open(newline='',encoding='utf-8-sig') as f:
        raw=list(csv.reader(f))
    if not raw:return [],[],['empty']
    h=raw[0];err=[]
    if len(h)!=len(set(h)):err.append('duplicate_header')
    rows=[]
    for i,r in enumerate(raw[1:],2):
        if len(r)!=len(h):err.append(f'nonrectangular:{i}')
        else:rows.append(dict(zip(h,r)))
    if not rows:err.append('no_rows')
    return h,rows,err
def contract_rows(name):
    with (HERE/name).open(newline='',encoding='utf-8-sig') as f:return list(csv.DictReader(f))
def source_hash(root,names):
    h=hashlib.sha256()
    for n in sorted(names):
        p=root/n
        if not p.exists():return ''
        h.update(n.encode());h.update(digest(p).encode())
    return h.hexdigest()

def verify(root):
    failures=[]; parsed={}
    cc=contract_rows('desired_pusch_impact_csv_contract.csv'); ic=contract_rows('desired_pusch_impact_image_contract.csv')
    experiments=contract_rows('pusch_impact_experiment_matrix.csv'); mandatory={r['ExperimentID'] for r in experiments}
    rule_defs={r['RuleID']:r for r in contract_rows('pusch_impact_acceptance_rules.csv')}
    for c in cc:
        p=root/c['FileName']; req=[x for x in c['RequiredColumns'].split('|') if x]
        if not p.exists():failures.append('missing_csv:'+p.name);continue
        h,rows,err=readcsv(p); parsed[p.name]=rows
        failures += [p.name+':'+x for x in err]
        miss=[x for x in req if x not in h]
        if miss:failures.append(p.name+':missing_columns:'+','.join(miss));continue
        keys=[x for x in c['PrimaryKey'].split('|') if x];seen=set()
        for i,r in enumerate(rows,2):
            k=tuple(r.get(x,'') for x in keys)
            if k in seen:failures.append(p.name+':duplicate_key:'+str(k))
            seen.add(k)
            if 'Status' in r and str(r['Status']).upper()!='PASS':failures.append(p.name+f':nonpass_line:{i}')
    op=parsed.get('pusch_impact_operating_points.csv',[])
    completed={r.get('ExperimentID','') for r in op if r.get('ExperimentID')}
    missing=sorted(mandatory-completed)
    if missing:failures.append('missing_experiments:'+','.join(missing[:50])+('...' if len(missing)>50 else ''))
    for i,r in enumerate(op,2):
        for f in ['Trials','TBErrors','BLER','CILower','CIUpper','Goodput_bps','MeanMeasuredSINRdB']:
            if finite(r.get(f)) is None:failures.append(f'operating_points:nonfinite:{f}:line={i}')
        bl=finite(r.get('BLER'));lo=finite(r.get('CILower'));hi=finite(r.get('CIUpper'))
        if None not in (bl,lo,hi) and not (0<=lo<=bl<=hi<=1):failures.append(f'operating_points:bad_ci:line={i}')
        if truth(r.get('Incomplete')):failures.append(f'operating_points:incomplete:line={i}')
    ev=parsed.get('pusch_impact_rule_evaluation.csv',[])
    observed_rules={r.get('RuleID','') for r in ev}
    missing_rules=sorted(set(rule_defs)-observed_rules)
    if missing_rules:failures.append('missing_rule_evaluations:'+','.join(missing_rules))
    for i,r in enumerate(ev,2):
        rid=r.get('RuleID',''); sev=rule_defs.get(rid,{}).get('Severity','')
        if sev=='HARD' and not truth(r.get('Passed')):failures.append(f'hard_rule_failed:{rid}:line={i}')
        if rid not in rule_defs:failures.append(f'unknown_rule:{rid}:line={i}')
    eff=parsed.get('pusch_impact_pairwise_effects.csv',[])
    for i,r in enumerate(eff,2):
        for f in ['BaselineValue','TreatmentValue','AbsoluteEffect','CILower','CIUpper','PValue','EffectSize']:
            if finite(r.get(f)) is None:failures.append(f'pairwise_effects:nonfinite:{f}:line={i}')
        p=finite(r.get('PValue'));ap=finite(r.get('AdjustedPValue'))
        if p is not None and not 0<=p<=1:failures.append(f'bad_pvalue:line={i}')
        if ap is not None and not 0<=ap<=1:failures.append(f'bad_adjusted_pvalue:line={i}')
    # image integrity and semantic audit
    audit_rows=parsed.get('pusch_impact_image_semantic_audit.csv',[]); amap={r.get('ImageFile',''):r for r in audit_rows}
    for c in ic:
        name=c['ImageFile'];p=root/name
        if not p.exists():failures.append('missing_png:'+name);continue
        try:
            with Image.open(p) as im:
                im.load();w,h=im.size;stat=ImageStat.Stat(im.convert('L'));var=stat.var[0]
        except Exception as e:failures.append('bad_png:'+name+':'+str(e));continue
        if w<int(c['MinWidth']) or h<int(c['MinHeight']):failures.append('small_png:'+name)
        if var<1.0:failures.append('blank_png:'+name)
        a=amap.get(name)
        if not a:failures.append('missing_image_audit:'+name);continue
        if a.get('PNG_SHA256')!=digest(p):failures.append('png_hash_mismatch:'+name)
        src=[x for x in c['SourceCSV'].split('|') if x]
        if a.get('SourceCSV_SHA256')!=source_hash(root,src):failures.append('source_hash_mismatch:'+name)
        if int(float(a.get('AxesCount','0'))) < int(c['MinAxesCount']):failures.append('axes_count:'+name)
        if int(float(a.get('SeriesCount','0'))) < int(c['MinSeriesCount']):failures.append('series_count:'+name)
        if int(float(a.get('FinitePointCount','0'))) < int(c['MinFinitePointCount']):failures.append('point_count:'+name)
        if c['ExpectedTitleToken'].lower() not in a.get('ActualTitle','').lower():failures.append('title:'+name)
        if ' '.join(c['ExpectedXLabel'].split())!=' '.join(a.get('ActualXLabel','').split()):failures.append('xlabel:'+name)
        if ' '.join(c['ExpectedYLabel'].split())!=' '.join(a.get('ActualYLabel','').split()):failures.append('ylabel:'+name)
    print(json.dumps({'required_experiments':len(mandatory),'completed_experiments':len(completed),'required_rules':len(rule_defs),'evaluated_rules':len(observed_rules),'required_csvs':len(cc),'required_pngs':len(ic),'failures':failures},indent=2))
    return 0 if not failures else 2

# Minimal synthetic self-test for contracts and corruption detection.
def write(path,cols,rows):
    with path.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=cols);w.writeheader();w.writerows(rows)
def selftest():
    cc=contract_rows('desired_pusch_impact_csv_contract.csv');ic=contract_rows('desired_pusch_impact_image_contract.csv');ex=contract_rows('pusch_impact_experiment_matrix.csv');rules=contract_rows('pusch_impact_acceptance_rules.csv')
    with tempfile.TemporaryDirectory() as td:
        root=Path(td); data={}
        for c in cc:
            cols=c['RequiredColumns'].split('|'); rows=[]
            if c['FileName']=='pusch_impact_operating_points.csv':
                for e in ex:
                    r={x:'1' for x in cols};r.update(RunID='SYN',ExperimentID=e['ExperimentID'],FamilyID=e['FamilyID'],PairID=e['PairID'],Variant=e['Variant'],OperatingPointID='OP1',BLER='0.1',CILower='0.08',CIUpper='0.12',Incomplete='0',Status='PASS');rows.append(r)
            elif c['FileName']=='pusch_impact_rule_evaluation.csv':
                for q in rules:
                    r={x:'1' for x in cols};r.update(RunID='SYN',RuleID=q['RuleID'],FamilyID=q['FamilyID'],ExperimentID='SYN',PairID='SYN',Metric=q['Metric'],Passed='1',Status='PASS');rows.append(r)
            elif c['FileName']=='pusch_impact_pairwise_effects.csv':
                r={x:'1' for x in cols};r.update(RunID='SYN',FamilyID='F01',PairID='P',OperatingPointKey='O',Metric='BLER',BaselineValue='0.2',TreatmentValue='0.1',AbsoluteEffect='-0.1',CILower='-0.2',CIUpper='-0.01',PValue='0.01',AdjustedPValue='0.02',EffectSize='0.5',Status='PASS');rows=[r]
            elif c['FileName']=='pusch_impact_image_semantic_audit.csv':
                continue
            else:
                r={x:'1' for x in cols};r['Status']='PASS';rows=[r]
            write(root/c['FileName'],cols,rows);data[c['FileName']]=rows
        # images and semantics
        semcols=[x for x in next(c for c in cc if c['FileName']=='pusch_impact_image_semantic_audit.csv')['RequiredColumns'].split('|')]
        sem=[]
        for idx,c in enumerate(ic):
            w=max(1000,int(c['MinWidth']));h=max(650,int(c['MinHeight']));im=Image.new('RGB',(w,h),'white');d=ImageDraw.Draw(im);d.rectangle((50,40,w-40,h-60),outline='black',width=3)
            for k in range(80):
                x=60+k*(w-120)//80;y=60+((k*47+idx*31)%(h-140));d.ellipse((x-2,y-2,x+2,y+2),fill='black')
            im.save(root/c['ImageFile'])
            src=[x for x in c['SourceCSV'].split('|') if x]
            sem.append(dict(ImageFile=c['ImageFile'],SourceCSV=c['SourceCSV'],Width=w,Height=h,AxesCount=c['MinAxesCount'],SeriesCount=c['MinSeriesCount'],FinitePointCount=c['MinFinitePointCount'],ExpectedXLabel=c['ExpectedXLabel'],ActualXLabel=c['ExpectedXLabel'],ExpectedYLabel=c['ExpectedYLabel'],ActualYLabel=c['ExpectedYLabel'],ExpectedTitleToken=c['ExpectedTitleToken'],ActualTitle='Synthetic '+c['ExpectedTitleToken'],SourceCSV_SHA256=source_hash(root,src),PNG_SHA256=digest(root/c['ImageFile']),Status='PASS'))
        write(root/'pusch_impact_image_semantic_audit.csv',semcols,sem)
        good=verify(root)
        sem[0]['PNG_SHA256']='0'*64;write(root/'pusch_impact_image_semantic_audit.csv',semcols,sem)
        bad=verify(root)
        print('selftest',good,bad)
        return 0 if good==0 and bad==2 else 3

def main():
    ap=argparse.ArgumentParser();ap.add_argument('output_dir',nargs='?',type=Path);ap.add_argument('--self-test',action='store_true');a=ap.parse_args()
    if a.self_test:return selftest()
    if not a.output_dir:return 2
    return verify(a.output_dir.resolve())
if __name__=='__main__':raise SystemExit(main())
