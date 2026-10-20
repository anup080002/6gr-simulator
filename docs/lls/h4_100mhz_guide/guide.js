/* Read-only teaching UI: no simulator control, external JS or synthetic run evidence. */
'use strict';
(() => {
const {CHAPTERS, esc, S, T, N} = window.H4Guide;
const $=id=>document.getElementById(id), cache=new Map();
let current='',epoch=0;
const json=url=>{if(!cache.has(url))cache.set(url,fetch(url).then(r=>{if(!r.ok)throw Error(`${r.status}: ${url}`);return r.json();}).catch(e=>{cache.delete(url);throw e;}));return cache.get(url);};
const plain=html=>{const d=document.createElement('div');d.innerHTML=html;return d.textContent;};
const index=CHAPTERS.map(c=>`${c.title} ${c.lead} ${plain(c.body())}`.toLowerCase());
const val=v=>v===undefined?'Not declared here':typeof v==='string'?v:JSON.stringify(v);
const getPath=(obj,p)=>String(p).split('.').reduce((x,k)=>x?.[k],obj);
function flatten(obj,prefix='',out=[]){Object.entries(obj||{}).forEach(([k,v])=>{const p=prefix?`${prefix}.${k}`:k;if(v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length)flatten(v,p,out);else out.push({path:p,value:v});});return out;}
function navigation(){const q=$('search').value.trim().toLowerCase();let group='',html='',count=0;CHAPTERS.forEach((c,i)=>{if(q&&!index[i].includes(q))return;count++;if(group!==c.group){group=c.group;html+=`<div class="nav-group">${esc(group)}</div>`;}html+=`<a href="#${c.id}"${c.id===current?' class="active" aria-current="page"':''}><span>${String(i+1).padStart(2,'0')}</span>${esc(c.title)}</a>`;});$('navigation').innerHTML=html||'<p>No chapter matches. Try a shorter term.</p>';$('navigation').setAttribute('aria-label',`${count} matching chapters`);}
function table(target,rows,heads,rowFn,page=0,size=40){const pages=Math.max(1,Math.ceil(rows.length/size));page=Math.max(0,Math.min(page,pages-1));target.innerHTML=`<div class="pagination"><span>${rows.length?page*size+1:0}–${Math.min(rows.length,(page+1)*size)} of ${rows.length}</span><button data-prev ${!page?'disabled':''}>Previous</button><button data-next ${page===pages-1?'disabled':''}>Next</button><span>Page ${page+1}/${pages}</span></div>`+(rows.length?T(heads,rows.slice(page*size,(page+1)*size).map(rowFn)):'<p class="empty">No matches. Nothing has been substituted.</p>');target.querySelector('[data-prev]').onclick=()=>table(target,rows,heads,rowFn,page-1,size);target.querySelector('[data-next]').onclick=()=>table(target,rows,heads,rowFn,page+1,size);}
function error(id,e){if($(id))$(id).innerHTML=N('Could not load local documentation data',esc(e.message)+' Start serve.py using the documented command; do not open index.html directly.',true);}
async function configExplorer(stamp){try{const d=await json('/api/reference');if(stamp!==epoch)return;if(!d.available)throw Error(d.reason);$('config-summary').innerHTML=`<strong>${d.snapshot_matches_yaml?'Snapshot matches all inherited YAML hashes.':'WARNING: YAML changed since this snapshot.'}</strong><br>Generated ${esc(d.created)} · MATLAB ${esc(d.matlab)} · ${d.sources.length} inherited source occurrences.<br>Configuration only; not a completed-run receipt.`+(d.source_changes_since_snapshot.length?`<p>${esc(d.source_changes_since_snapshot.join(', '))}</p>`:'');const rows=flatten(d.resolved);const update=()=>{const q=$('config-filter').value.toLowerCase();table($('config-values'),rows.filter(r=>`${r.path} ${val(r.value)}`.toLowerCase().includes(q)),['Resolved field','Value'],r=>[`<code>${esc(r.path)}</code>`,`<code>${esc(val(r.value))}</code>`]);};$('config-filter').oninput=update;update();$('config-sources').innerHTML=T(['Merge sequence','Source','SHA-256'],d.sources.map((s,i)=>[i+1,S(s.path,s.path),`<code>${esc(s.sha256)}</code>`]));}catch(e){if(stamp===epoch)error('config-summary',e);}}
async function parameterExplorer(stamp,params){
  let loadID=0;
  const requestedKind=params.get('kind');
  if(['scenario','matrix','core'].includes(requestedKind))$('catalog-kind').value=requestedKind;
  $('parameter-search').value=params.get('q')||'';
  async function load(){
    const serial=++loadID;
    try{
      const kind=$('catalog-kind').value;
      const [d,ref]=await Promise.all([json('/api/catalog?kind='+kind),json('/api/reference')]);
      if(stamp!==epoch||serial!==loadID)return;
      const cat=d.catalog,rows=[];
      if(kind==='core'){
        const visit=(obj,prefix='')=>Object.entries(obj||{}).forEach(([key,rule])=>{
          const path=prefix?`${prefix}.${key}`:key;
          if(!rule||typeof rule!=='object')return;
          if(Object.hasOwn(rule,'value_type'))rows.push({name:path.split('.')[0],field:key,rule,scope:'native core',path});
          else visit(rule,path);
        });
        visit(cat.parameters);
      }else{
        for(const[scope,sections]of[['section',cat.sections],['object',cat.nested_sections]])
          Object.entries(sections||{}).forEach(([name,section])=>Object.entries(section.parameters||{}).forEach(([field,rule])=>{
            const declared=scope==='section'?name:section.path;
            const path=typeof declared==='string'?`${declared}.${field}`:undefined;
            rows.push({name,field,rule,scope,path,current:kind==='scenario'&&path?getPath(ref.resolved,path):undefined});
          }));
      }
      const names=[...new Set(rows.map(r=>r.name))].sort();
      $('parameter-section').innerHTML='<option value="">All sections / objects</option>'+names.map(n=>`<option value="${esc(n)}">${esc(n)}</option>`).join('');
      if(names.includes(params.get('section')))$('parameter-section').value=params.get('section');
      const provenance=kind==='core'?'Read directly from the current native core catalog; not a resolved SLS run.':d.snapshot_matches_sources?'Installed-loader snapshot hashes match.':'WARNING: missing provenance or changed source; regenerate snapshots.';
      $('parameter-summary').innerHTML=`<strong>${rows.length.toLocaleString()} parameter rules</strong> · ${Object.keys(cat.sections||cat.parameters||{}).length} top-level sections · ${Object.keys(cat.nested_sections||{}).length} nested-object schemas.<br>${provenance} Declared options are not execution qualification.`+(kind==='core'?'<p>For SLS, prefix native paths below with <code>sls.config.</code>. The request loader also enforces mode-specific restrictions: for example <code>run.mode=system</code> and no development calibration. A core default is not necessarily the effective SLS value.</p>':'');
      const update=()=>{
        const q=$('parameter-search').value.toLowerCase(),section=$('parameter-section').value,filter=$('parameter-rule').value;
        const selected=rows.filter(r=>{
          const type=r.rule.type||r.rule.value_type;
          const match=filter==='all'||(filter==='enum'&&Object.hasOwn(r.rule,'allowed_values'))||
            (filter==='boolean'&&type==='boolean')||(filter==='range'&&['min','max','min_exclusive','max_exclusive','min_length','max_length'].some(k=>Object.hasOwn(r.rule,k)));
          return (!section||r.name===section)&&match&&JSON.stringify(r).toLowerCase().includes(q);
        });
        table($('parameter-table'),selected,['Parameter / schema','Type and constraints','Declared default / example'],r=>[
          `<code>${esc(r.path||`${r.name} :: ${r.field}`)}</code><br><small>${esc(r.scope)}: ${esc(r.name)}</small>`,
          `<strong>${esc(val(r.rule.type||r.rule.value_type))}</strong>`+Object.entries(r.rule).filter(([k])=>!['type','value_type','default'].includes(k)).map(([k,v])=>`<div><code>${esc(k)}</code>: ${esc(val(v))}</div>`).join(''),
          `<strong>Declared default:</strong> ${esc(val(r.rule.default))}`+(kind==='scenario'?`<br><strong>H4:</strong> <code>${esc(val(r.current))}</code>`:kind==='core'?'<br><small>No resolved SLS value asserted.</small>':'')]);
      };
      $('parameter-search').oninput=update;$('parameter-section').onchange=update;$('parameter-rule').onchange=update;update();
      const extras=document.createElement('details');extras.innerHTML='<summary>Catalog provenance and value maps</summary><pre></pre>';
      extras.querySelector('pre').textContent=JSON.stringify({metadata:d.metadata,top_level_order:cat.top_level_order,value_maps:cat.value_maps},null,2);$('parameter-summary').append(extras);
    }catch(e){if(stamp===epoch&&serial===loadID)error('parameter-summary',e);}
  }
  $('catalog-kind').onchange=load;await load();
}
async function scenarioExplorer(stamp,params){try{const d=await json('/api/scenarios');if(stamp!==epoch)return;const rows=d.entries;const categories=[...new Set(rows.map(r=>r.category))].sort();$('scenario-category').innerHTML='<option value="">All YAML categories</option>'+categories.map(c=>`<option value="${esc(c)}">${esc(c)}</option>`).join('');if(categories.includes(params.get('category')))$('scenario-category').value=params.get('category');$('scenario-search').value=params.get('q')||'';$('scenario-summary').innerHTML=`<strong>${rows.length} YAML files, including ${rows.filter(r=>r.category==='scenarios').length} scenario files.</strong><br>Also includes band, channel, RF, MIMO, schema and matrix building blocks. Not every file is a standalone run. Metadata is leaf-file metadata; inheritance is not guessed. No acceptance is inferred from filenames.`;const update=()=>{const q=$('scenario-search').value.toLowerCase(),category=$('scenario-category').value;table($('scenario-table'),rows.filter(r=>(!category||r.category===category)&&JSON.stringify(r).toLowerCase().includes(q)),['File / category','Declared metadata','Inherited files'],r=>{const parents=Array.isArray(r.inherits)?r.inherits:r.inherits?[r.inherits]:[];return[S(r.path,r.path.replace('simulator/configs/',''))+`<br><span class="badge">${esc(r.category)}</span>`,r.error?`<strong>Parse issue</strong><p>${esc(r.error)}</p>`:`<pre>${esc(JSON.stringify(r.meta||{},null,2))}</pre><small>Acceptance: not assessed here.</small>`,parents.length?parents.map(p=>`<div><code>${esc(p)}</code></div>`).join(''):'No inherits declared here'];},0,20);};$('scenario-search').oninput=update;$('scenario-category').onchange=update;update();}catch(e){if(stamp===epoch)error('scenario-summary',e);}}

const svg=(body,w=800,h=300,label='Educational diagram')=>`<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(label)}" xmlns="http://www.w3.org/2000/svg">${body}</svg>`;
const tx=(x,y,t,size=14,fill='#c3e8d7')=>`<text x="${x}" y="${y}" font-family="Segoe UI, Arial, sans-serif" font-size="${size}" fill="${fill}">${esc(t)}</text>`;
function hero(){const nodes=[['01','CONFIGURE','YAML → frozen grant'],['02','TRANSMIT','bits → layers → samples'],['03','PROPAGATE','CDL-C + RF + noise'],['04','RECEIVE','estimate → decode → CRC']];$('hero-diagram').innerHTML=svg(`<rect width="800" height="240" rx="12" fill="#123733"/>${tx(24,34,'ONE LINK. MANY CAUSAL OWNERS.',12)}${nodes.map((n,i)=>{const x=24+i*195;return`<rect x="${x}" y="67" width="167" height="107" rx="9" fill="#224e43" stroke="#70ba9a"/>${tx(x+15,92,n[0],12,'#9edac1')}${tx(x+15,119,n[1],17,'#f4fff8')}${tx(x+15,145,n[2],10)}${i<3?`<path d="M ${x+170} 119 h 22 l -6 -4 m 6 4 l -6 4" stroke="#a4dbc5" fill="none"/>`:''}`;}).join('')}<path d="M 700 181 v 24 H 105 v -24" fill="none" stroke="#dfa853" stroke-dasharray="4 4"/>${tx(254,227,'Received feedback changes only future grants',12,'#f2c57d')}`,800,240,'YAML to transmitter, channel and receiver, with causal feedback');}
function flow(){const stages=[['Configuration',['load','builder'],'Validate inheritance, aliases, units and cross-field constraints. The executed internal configuration—not a filename—controls the run.'],['Event runtime',['runtime','stream'],'Run access, timers, signal occasions and receiver completions on the causal sample clock. Resource time and availability are distinct.'],['Frozen grant',['scheduler','job'],'Bind UE, RNTI, BWP, rank, MCS, PRBs, symbols and HARQ epoch. A later CSI report cannot change an issued grant.'],['TX chain',['dltx','ultx'],'Create the original TB, code, rate match, map symbols and layers, apply the authorized precoder and synthesize OFDM.'],['Propagation / RF',['channel','rfstream'],'Evolve channel and oscillator state; apply RF and noise at the declared planes. Perfect references remain scoring-only.'],['RX chain',['dlrx','ulrx'],'Acquire timing, estimate channel/noise, equalize, form LLRs, combine compatible attempts and decode CRC.'],['Feedback',['uci','csi','srs'],'Complete independently scheduled UCI and causal CSI/SRS state. Never infer an expected layout from transmitted payloads.'],['Publication',['exports','packets'],'Publish actual physical outcomes and unique delivery accounting. Publication success is separate from CRC success.']];const root=$('flow-map');root.innerHTML='<div class="flow-buttons"></div><div class="flow-detail" aria-live="polite"></div>';root.querySelector('.flow-buttons').innerHTML=stages.map((s,i)=>`<button data-stage="${i}" aria-pressed="false">${i+1}. ${esc(s[0])}</button>`).join('');const select=i=>{root.querySelectorAll('[data-stage]').forEach((b,j)=>{b.classList.toggle('selected',i===j);b.setAttribute('aria-pressed',String(i===j));});const s=stages[i];root.querySelector('.flow-detail').innerHTML=`<h3>${esc(s[0])}</h3><p>${esc(s[2])}</p><div class="file-list">${s[1].map(k=>S(k)).join('')}</div>`;};root.onclick=e=>{const b=e.target.closest('[data-stage]');if(b)select(Number(b.dataset.stage));};select(0);}
function grid(){const update=()=>{const slot=Number($('slot-select').value),roles=slot<3?'DDDDDDDDDDDDDD':slot===3?'DDDDDDDDDDGGUU':'UUUUUUUUUUUUUU';const colors={D:'#266b5d',G:'#9c854e',U:'#30668c'};let body=tx(20,25,`Slot ${slot+1} / 5 · 0.5 ms · symbol roles (not a measured grant)`,14,'#31564c');[...roles].forEach((role,i)=>{const x=38+i*52;body+=`<rect x="${x}" y="50" width="48" height="145" rx="4" fill="${colors[role]}"/>${tx(x+17,80,role,17,'white')}${tx(x+15,221,String(i),12,'#31564c')}`;});body+=tx(20,255,'D = downlink     G = guard     U = uplink     Symbols indexed 0–13',13,'#31564c');const explain=slot===3?'10 DL, 2 guard and 2 UL symbols. An 11-symbol PUSCH cannot fit here; its legality is checked, not bypassed.':slot===4?'A full UL slot is not all PUSCH: SRS, PUCCH, UCI multiplexing and the received grant determine the allocation.':'PDCCH and reference signals reserve REs. The 273 configured PRBs are a grid limit, not proof of a full-band data grant.';$('grid-lab').innerHTML=svg(body,800,280,'Fourteen OFDM symbol direction roles')+`<p>${esc(explain)}</p>`;};$('slot-select').onchange=update;update();}
function rankLab(){const update=()=>{const snr=Number($('rank-snr').value),spread=Number($('rank-spread').value);$('rank-snr-value').textContent=`${snr} dB`;$('rank-spread-value').textContent=`${spread} dB strongest-to-weakest power spread`;const powers=[0,spread/3,2*spread/3,spread].map(x=>10**(-x/10));const ranks=[1,2,4],rates=ranks.map(r=>powers.slice(0,r).reduce((s,p)=>s+Math.log2(1+10**(snr/10)*p/r),0));const max=Math.max(1,...rates);let body=tx(24,30,'Fixed total transmit power; illustrative singular-mode gains',14,'#31564c');rates.forEach((rate,i)=>{const y=60+i*65,w=520*rate/max;body+=tx(24,y+21,`Rank ${ranks[i]}`,15,'#31564c')+`<rect x="110" y="${y}" width="${w}" height="34" rx="5" fill="#237b65"/>`+tx(120+w,y+23,rate.toFixed(2)+' bit/s/Hz',13,'#31564c');});$('rank-lab').innerHTML=svg(body,800,265,'Ideal information rates for ranks one, two and four')+`<p>Mode power gains: ${powers.map(x=>x.toFixed(4)).join(', ')}. Highest illustrative rate: rank ${ranks[rates.indexOf(Math.max(...rates))]}. The actual receiver uses its configured CSI/codebook policy, not this calculator.</p>`;};$('rank-snr').oninput=update;$('rank-spread').oninput=update;update();}
function harqLab(){let generation=0,attempt=0,delivered=false,done=false,history=[];const render=()=>{$('harq-lab').innerHTML=T(['Original TB identity','Attempt','RV','Outcome'],history.map((h,i)=>[`TEACHING-TB-${generation}`,i+1,[0,2,3,1][i],esc(h)]))+`<p><strong>Unique delivered bits: ${delivered?1000:0}.</strong> ${done?(delivered?'CRC success: no further attempt is allowed for this TB.':'Retry limit reached: the TB remains undelivered.'):`Attempt ${attempt+1} is pending; the original 1,000 information bits are retained.`}</p>`;$('harq-ack').disabled=done;$('harq-nack').disabled=done;};const reset=()=>{generation++;attempt=0;delivered=false;done=false;history=['Pending receiver outcome'];render();};$('harq-reset').onclick=reset;$('harq-nack').onclick=()=>{if(done)return;history[attempt]='CRC failure; NACK after declared delay';if(attempt===3)done=true;else{attempt++;history.push('Pending; same TB, compatible soft buffer');}render();};$('harq-ack').onclick=()=>{if(done)return;history[attempt]='CRC pass; one unique delivery; delayed ACK';done=true;delivered=true;render();};reset();}
function qamLab(){const draw=()=>{const M=Number($('qam-select').value),snr=Number($('qam-snr').value),phase=Number($('qam-phase').value);$('qam-snr-value').textContent=`${snr} dB`;$('qam-phase-value').textContent=`${phase}°`;const canvas=$('qam-canvas'),ctx=canvas.getContext('2d'),w=canvas.width,h=canvas.height;ctx.fillStyle='#f1f6f1';ctx.fillRect(0,0,w,h);const scale=90,cx=w/2,cy=h/2;ctx.strokeStyle='#b8cdc1';ctx.beginPath();ctx.moveTo(0,cy);ctx.lineTo(w,cy);ctx.moveTo(cx,0);ctx.lineTo(cx,h);ctx.stroke();ctx.fillStyle='#426355';ctx.font='12px Segoe UI';ctx.fillText('Quadrature',10,19);ctx.fillText('In-phase',w-65,cy-9);let state=126;const random=()=>{state=(1664525*state+1013904223)>>>0;return(state+.5)/4294967296;};const normal=()=>Math.sqrt(-2*Math.log(random()))*Math.cos(2*Math.PI*random());const side=Math.sqrt(M),norm=Math.sqrt(2*(M-1)/3),sigma=Math.sqrt(10**(-snr/10)/2),theta=phase*Math.PI/180;let e=0,energy=0;ctx.fillStyle='#13876a88';for(let i=0;i<1600;i++){const re=(2*Math.floor(random()*side)-side+1)/norm,im=(2*Math.floor(random()*side)-side+1)/norm;const yr=re*Math.cos(theta)-im*Math.sin(theta)+sigma*normal(),yi=re*Math.sin(theta)+im*Math.cos(theta)+sigma*normal();e+=(yr-re)**2+(yi-im)**2;energy+=re*re+im*im;ctx.beginPath();ctx.arc(cx+yr*scale,cy-yi*scale,1.8,0,2*Math.PI);ctx.fill();}ctx.fillStyle='#b86713';for(let a=0;a<side;a++)for(let b=0;b<side;b++){const x=cx+(2*a-side+1)/norm*scale,y=cy-(2*b-side+1)/norm*scale;ctx.fillRect(x-1,y-1,2,2);}$('qam-readout').textContent=`Teaching samples only. ${M}-QAM (${Math.log2(M)} bits/symbol); paired raw RMS EVM ${(100*Math.sqrt(e/energy)).toFixed(2)}%. Includes uncompensated phase rotation. No standards EVM window, channel estimator, coding or hardware measurement is simulated. Orange: ideal points; green: educational samples.`;};['qam-select','qam-snr','qam-phase'].forEach(id=>$(id).oninput=draw);draw();}

function prachLab() {
  const update = () => {
    const lra = Number($('prach-lra').value);
    const rx = Number($('prach-rx').value);
    const symbols = Number($('prach-symbols').value);
    if (!Number.isSafeInteger(rx) || rx < 1 || !Number.isSafeInteger(symbols) || symbols < 1) {
      $('prach-threshold').textContent = 'Enter positive integer RX-column and useful-symbol counts.';
      return;
    }
    const coefficients = {139:[0.1,0],839:[0.02,0],1151:[0.01,0.0005],571:[0.02,0.001]};
    const [factor,offset] = coefficients[lra];
    const threshold = factor / Math.sqrt(rx * symbols) + offset;
    $('prach-threshold').textContent =
      `T = ${factor} / √(${rx} × ${symbols})${offset ? ' + '+offset : ''} = ${threshold.toPrecision(15)}. `+
      'Dimensionless MathWorks receiver default; not a 3GPP-mandated formula or measured false-alarm probability.';
  };
  ['prach-lra','prach-rx','prach-symbols'].forEach(id => $(id).oninput = update);
  update();
}

let source={lines:[],path:'',first:0,match:-1};
function drawSource(first=0){source.first=Math.max(0,Math.min(first,Math.max(0,source.lines.length-1)));const end=Math.min(source.lines.length,source.first+240);const code=$('source-code');code.innerHTML=`<div class="source-pages"><button data-source-page="prev" ${!source.first?'disabled':''}>Previous lines</button><span>Lines ${source.first+1}–${end} of ${source.lines.length}</span><button data-source-page="next" ${end===source.lines.length?'disabled':''}>Next lines</button></div>`+source.lines.slice(source.first,end).map((line,j)=>{const i=j+source.first;return`<div id="source-line-${i}" class="source-line${i===source.match?' highlight':''}${/^\s*(%|#|\/\/)/.test(line)?' comment':''}"><span class="line-no">${i+1}</span><span class="line-text">${esc(line)||' '}</span></div>`;}).join('');code.scrollTop=0;if(source.match>=source.first&&source.match<end)requestAnimationFrame(()=>$('source-line-'+source.match)?.scrollIntoView({block:'center'}));}
function findSource(next=false){const query=$('source-find').value.toLowerCase();if(!query)return;const start=next?source.match+1:0;let found=source.lines.findIndex((s,i)=>i>=start&&s.toLowerCase().includes(query));if(found<0&&next)found=source.lines.findIndex(s=>s.toLowerCase().includes(query));source.match=found;$('source-next').textContent=found<0?'No match':'Find next';if(found>=0)drawSource(Math.max(0,found-45));}
async function openSource(path,find=''){const dialog=$('source-dialog');if(!dialog.open)dialog.showModal();$('source-title').textContent=path;$('source-meta').textContent='Loading current repository source…';$('source-code').textContent='';$('source-find').value=find;$('source-download').href='/raw?path='+encodeURIComponent(path);$('source-download').target='_blank';try{const r=await fetch('/api/source?path='+encodeURIComponent(path));if(!r.ok)throw Error(await r.text());const d=await r.json();if($('source-title').textContent!==path)return;source={lines:d.text.split(/\r?\n/),path,first:0,match:-1};$('source-meta').textContent=`Current main working-tree source (not a run snapshot) · SHA-256 ${d.sha256}`;drawSource();if(find)findSource();}catch(e){$('source-meta').textContent='Source not loaded: '+e.message;}}
document.addEventListener('click',e=>{const a=e.target.closest('[data-source]');if(a){e.preventDefault();openSource(a.dataset.source,a.dataset.find||'');}const page=e.target.closest('[data-source-page]');if(page)drawSource(source.first+(page.dataset.sourcePage==='prev'?-240:240));});
$('close-source').onclick=()=>$('source-dialog').close();$('source-dialog').addEventListener('click',e=>{if(e.target===$('source-dialog')){const r=e.target.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)e.target.close();}});
$('source-find').onkeydown=e=>{if(e.key==='Enter')findSource(true);};$('source-find').oninput=()=>findSource();$('source-next').onclick=()=>findSource(true);
function route(){
  const [anchor,query='']=location.hash.slice(1).split('?'),requested=anchor||'start',params=new URLSearchParams(query);
  if(requested==='content'){$('content').focus();return;}
  const idx=CHAPTERS.findIndex(c=>c.id===requested);
  if(idx<0){location.hash='start';return;}
  const c=CHAPTERS[idx];current=c.id;const stamp=++epoch;navigation();
  $('content').innerHTML=`<div class="eyebrow"><span class="chapter-number">${String(idx+1).padStart(2,'0')}</span>${esc(c.group)}</div><h1>${esc(c.title)}</h1><p class="lead">${esc(c.lead)}</p>${window.H4Guide.chapterAuthority(c.id)}${c.body()}`;
  document.title=`${c.title} · SixGR Field Guide`;
  $('chapter-footer').innerHTML=(idx?`<a href="#${CHAPTERS[idx-1].id}">← ${esc(CHAPTERS[idx-1].title)}</a>`:'<span>SixGR · Local field guide</span>')+(idx<CHAPTERS.length-1?`<a href="#${CHAPTERS[idx+1].id}">${esc(CHAPTERS[idx+1].title)} →</a>`:'<a href="#start">Back to the beginning ↑</a>');
  $('sidebar').classList.remove('open');$('menu').setAttribute('aria-expanded','false');
  window.scrollTo({top:0,behavior:'instant'});
  const labs={start:hero,architecture:flow,grid,mimo:rankLab,harq:harqLab,rf:qamLab,prach:prachLab};
  if(labs[c.id])labs[c.id]();
  window.H4Guide.initMethodChapter(c.id);
  if(c.id==='configuration')configExplorer(stamp);
  if(c.id==='parameters')parameterExplorer(stamp,params);
  if(c.id==='scenarios')scenarioExplorer(stamp,params);
}
$('search').oninput=navigation;$('menu').onclick=()=>{$('sidebar').classList.toggle('open');$('menu').setAttribute('aria-expanded',String($('sidebar').classList.contains('open')));};document.addEventListener('keydown',e=>{if(e.key==='Escape'){$('sidebar').classList.remove('open');$('menu').setAttribute('aria-expanded','false');}});
try{document.body.classList.toggle('dark',localStorage.getItem('sixgr-guide-theme')==='dark');}catch{}
$('theme').onclick=()=>{document.body.classList.toggle('dark');try{localStorage.setItem('sixgr-guide-theme',document.body.classList.contains('dark')?'dark':'light');}catch{}};$('print').onclick=()=>window.print();window.addEventListener('hashchange',route);route();
})();
