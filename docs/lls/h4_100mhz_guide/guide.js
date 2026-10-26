/* Read-only teaching UI: no simulator control, external JS or synthetic run evidence. */
'use strict';
(() => {
const {CHAPTERS, esc, S, T, N} = window.H4Guide;
const $=id=>document.getElementById(id), cache=new Map();
let current='',currentSection='',currentTopic='',epoch=0;
const json=url=>{if(!cache.has(url))cache.set(url,fetch(url).then(r=>{if(!r.ok)throw Error(`${r.status}: ${url}`);return r.json();}).catch(e=>{cache.delete(url);throw e;}));return cache.get(url);};
const plain=html=>{const d=document.createElement('div');d.innerHTML=html;return d.textContent;};
const index=CHAPTERS.map(c=>`${c.title} ${c.lead} ${plain(c.body())}`.toLowerCase());
// Reading order is deliberately independent of the authored chapter array.
// Existing chapter hashes and bodies remain the canonical detail pages.
const chapterByID=new Map(CHAPTERS.map(c=>[c.id,c]));
const reading=(id,label='',section='')=>({id,label:label||chapterByID.get(id)?.title||id,section});
const playbook=(id,label)=>reading('channel-playbooks',label,`playbook-${id}`);
const TOPICS=[
 {id:'orientation',title:'Orientation & link architecture',lead:'Start with the vocabulary, processing boundaries and production source owners.',entries:['start','fundamentals','architecture','engineering-handbook'].map(id=>reading(id))},
 {id:'configuration',title:'Configuration & execution',lead:'Resolve YAML, choose the experiment and understand execution scope before running it.',entries:['configuration-map','configuration','parameters','run-families','scenarios','recipe','n40-reference-sweep'].map(id=>reading(id))},
 {id:'antennas',title:'BS / UE, antennas & ports',lead:'Keep physical arrays, waveform columns, logical ports, layers and codebook dimensions distinct.',entries:['mimo','antenna-port-power-audit','port-layer-measurement-flow'].map(id=>reading(id))},
 {id:'waveform',title:'Waveform, frame & resources',lead:'Follow the radio clock, resource grid, OFDM transform and allocation boundaries.',entries:['grid','ofdm','resource-efficiency'].map(id=>reading(id))},
 {id:'transmit',title:'Transmit chain & coding',lead:'Follow information bits through coding, rate matching, modulation and mapping.',entries:['tx','coding'].map(id=>reading(id))},
 {id:'radio-link',title:'RF, channel, power & noise',lead:'Separate propagation, RF processing, waveform normalization and the declared noise reference.',entries:['channel-model-lab','channel','rf-port-lab','rf','power','absolute-power-n40','type1o-power-and-sliv'].map(id=>reading(id))},
 {id:'initial-access',title:'Initial access, SSB & PBCH',lead:'Acquire cell identity, synchronization and broadcast information from received samples.',entries:[reading('access'),playbook('ssb','SSB / PSS / SSS / PBCH execution')]},
 {id:'random-access',title:'PRACH, timing advance & RRC',lead:'Trace random access and connection state without confusing detection with completed access.',entries:[reading('prach'),playbook('prach','PRACH → RAR → Msg3 → connection')]},
 {id:'spatial-feedback',title:'Beams, CSI-RS, SRS & TRS',lead:'Generate, receive and interpret spatial and tracking measurements before using feedback.',entries:[reading('beam'),reading('referencesignals'),playbook('csirs','CSI-RS / CSI-IM measurement'),playbook('srs','SRS sounding and UL spatial evidence'),playbook('trs','TRS tracking and QCL timing')]},
 {id:'control',title:'PDCCH & received DCI',lead:'Follow control search, decoding and semantic admission into a later data grant.',entries:[reading('pdcch'),playbook('pdcch','PDCCH transmitter-to-receiver procedure')]},
 {id:'downlink-data',title:'PDSCH & DL-SCH',lead:'Follow the complete connected downlink data procedure, from admission to received CRC and delivery.',entries:[playbook('pdsch','PDSCH: full connected DL data chain')]},
 {id:'uplink-data',title:'PUSCH, PUCCH & UCI',lead:'Keep uplink data, HARQ-ACK, CSI, DTX and independent decode outcomes separate.',entries:[playbook('pusch','PUSCH: full connected UL data chain'),reading('uci')]},
 {id:'receive',title:'Receiver algorithms',lead:'Work through synchronization, estimation, equalization, soft decisions and decoding.',entries:[reading('rx'),reading('receiver-algorithm-lab'),reading('flexran-algorithm-review'),playbook('demodulation','DM-RS / PT-RS, equalization and soft decoding')]},
 {id:'scheduling',title:'Scheduling, adaptation & HARQ',lead:'Join causal measurements, legal grants, retransmissions, delivery and checkpoint state.',entries:['scheduler','adaptation','harq','causal-flow','restart-flow'].map(id=>reading(id))},
 {id:'measurements',title:'Measurements & results',lead:'Read definitions, units, populations, original evidence and availability before interpreting a plot.',entries:['measurements','measurement-operator-maths','measurement-contract','worked-calculations','outputs','dashboard-reading','output-atlas','result-reading','qualification','threshold-authority'].map(id=>reading(id))},
 {id:'references',title:'Source & standards reference',lead:'Use the searchable registers and versioned references to verify the implementation basis.',entries:['channel-playbooks','algorithm-register','comparison','standards-crosswalk','sources','glossary','references'].map(id=>reading(id))}
];
// Newly authored chapters remain reachable until their topic is assigned.
const assigned=new Set(TOPICS.flatMap(t=>t.entries.filter(e=>!e.section).map(e=>e.id)));
const unassigned=CHAPTERS.filter(c=>!assigned.has(c.id));
TOPICS.at(-1).entries.push(...unassigned.map(c=>reading(c.id)));
Object.assign(window.H4Guide,{topics:TOPICS,unassignedTopicChapters:unassigned.map(c=>c.id)});
const readingHref=e=>`#${e.id}${e.section?'?section='+encodeURIComponent(e.section):''}`;
const topicHref=t=>`#topic-${t.id}`;
const readingSearch=new Map(TOPICS.flatMap(t=>t.entries.map(e=>{
 let text=index[CHAPTERS.findIndex(c=>c.id===e.id)]||'';
 if(e.section.startsWith('playbook-')){
  const fragment=document.createElement('div');fragment.innerHTML=chapterByID.get(e.id).body();
  const detail=[...fragment.querySelectorAll('[data-playbook]')].find(n=>`playbook-${n.dataset.playbook}`===e.section);
  text=detail?.textContent.toLowerCase()||text;
 }
 return [readingHref(e),text];
})));
function topicFor(id,section=''){
 return (section&&TOPICS.find(t=>t.entries.some(e=>e.id===id&&e.section===section)))||
  TOPICS.find(t=>t.entries.some(e=>e.id===id&&!e.section))||TOPICS.at(-1);
}
const val=v=>v===undefined?'Not declared here':typeof v==='string'?v:JSON.stringify(v);
const getPath=(obj,p)=>String(p).split('.').reduce((x,k)=>x?.[k],obj);
// A real CSV parser: quoted commas/newlines and escaped quotes are valid in
// the generated JSON-bearing documentation inventory.
function parseCSV(text){
 const rows=[];let row=[],field='',quoted=false;
 for(let i=0;i<text.length;i++){
  const c=text[i];
  if(c==='"'){if(quoted&&text[i+1]==='"'){field+='"';i++;}else quoted=!quoted;}
  else if(c===','&&!quoted){row.push(field);field='';}
  else if((c==='\n'||c==='\r')&&!quoted){
   if(c==='\r'&&text[i+1]==='\n')i++;
   row.push(field);if(row.some(v=>v!==''))rows.push(row);row=[];field='';
  }else field+=c;
 }
 if(quoted)throw Error('Incomplete quoted field in documentation CSV');
 if(field||row.length){row.push(field);rows.push(row);}
 return rows;
}
window.H4Guide.parseEvidenceCSV=parseCSV;
function fieldReading(raw,label){
 const key=String(raw),text=(key+' '+label).toLowerCase();
 const rules=[
  [/configured.*snr|appliedawgnsnr/,'Configured/applied experiment reference in dB, not automatically measured receiver SINR.'],
  [/posteqsinr|post.equaliz.*sinr/,'Receiver post-equalization SINR. Read estimator/source/status and per-layer versus wideband scope.'],
  [/nmse/,'Channel-error energy ratio in dB when numeric; inspect independent reference plane, coordinate matching and compared count.'],
  [/evm/,'Error-vector metric or its provenance. RMS ratio and percent differ by100; reference type and applicability are essential.'],
  [/rsrp|rssi|rsrq/,'Reference/total power or quality ratio. Use the exact suffix/plane: dBm requires calibration; normalized dB does not.'],
  [/available.*sample|delivery|delivered|due.slot/,'Causal availability, delivery or scheduled due event; not necessarily resource/transmit time.'],
  [/slot/,'Radio-slot identity: use the explicit zero/one-based and source/due/delivery convention; not wall-clock time.'],
  [/cfo|frequency.*offset/,'Frequency offset estimate, correction or scoring reference in the stated plane. Do not replace an independent residual with injected minus applied.'],
  [/timing|advance/,'Timing/correction/TA in named sample/Tc/time units. Capture offset, propagation and quantized command are distinct.'],
  [/crc/,'Actual decoder CRC outcome or applicability; not an arbitrary SINR threshold and not necessarily semantic command acceptance.'],
  [/rnti|ueindex|ue.id/,'Radio or simulator endpoint identity. UE index, temporary RNTI and operational C-RNTI need not be numerically equal.'],
  [/tbs|tbsize|transportblock/,'Actual transport-block size/identity. Use exact grant/coding allocation; never reconstruct from aggregate served bits.'],
  [/prb|symbolstart|numsymbols|recount|resource.*count/,'Executed allocation/resource-set quantity. Check index origin, unique-RE versus per-port counting and reserved/pilot overlap.'],
  [/rank|layers/,'Configured capability, recommended rank or actual transmitted layers depending on field name. Do not substitute one for another.'],
  [/pmi|precod|tci|qcl|beam/,'Spatial/control identity or application evidence. Check codebook/matrix domain, causal source and actual weights.'],
  [/mcs|cqi|modulation|coderate/,'Adaptation/coding choice in a named table. Index alone is insufficient without direction, table authority and source feedback.'],
  [/sha|hash/,'Content identity at its declared plane/serialization. A TX, RX-sample, CSV and MAT-file hash are not interchangeable.'],
  [/bler|error.*count|trial.*count|confidence/,'Error/population statistic. Keep original TBs, retries, candidates and independent episodes distinct.'],
  [/throughput|goodput|rate_mbps/,'Bit rate with a defined numerator and duration. Unique delivery differs from repeated scheduled TB bits.'],
  [/status|source|scope|reason|role|applicable/,'Interpretation/provenance field. It limits the meaning of nearby numbers; missing, not applicable and failed are distinct.'],
  [/_hz$|sample.rate/,'Frequency/rate in Hz; carrier center, sample rate, CFO and Doppler are different quantities.'],
  [/_dbm$/,'Absolute power referenced to1mW; requires an explicitly calibrated plane.'],
  [/_db$/,'Logarithmic ratio/reference in dB. Inspect the metric definition before assigning absolute-power meaning.']
 ];
 return (rules.find(([p])=>p.test(text))||[null,'Use the producer, exact column label and family explanation. This index does not invent a definition from an unfamiliar name.'])[1];
}
async function evidenceExplorer(stamp,params){
 try{
  const path='docs/lls/h4_100mhz_guide/evidence-catalog.csv';
  const payload=await json('/api/source?path='+encodeURIComponent(path));if(stamp!==epoch)return;
  const matrix=parseCSV(payload.text),head=matrix.shift();
  const entries=matrix.map(values=>{
   if(values.length!==head.length)throw Error('Documentation CSV row width mismatch');
   const r=Object.fromEntries(head.map((k,i)=>[k,values[i]]));
   return {...r,paths:JSON.parse(r.paths_json),fields:JSON.parse(r.fields_json),details:JSON.parse(r.details_json)};
  });
  const meta=entries.find(r=>r.kind==='inventory')?.details;
  if(!meta||meta.scope!=='documentation_inventory_not_measurement_or_acceptance')throw Error('Unexpected inventory scope');
  const rows=entries.filter(r=>r.kind!=='inventory');
  $('evidence-inventory-summary').innerHTML=`<strong>Dated documentation inventory — not run acceptance.</strong><br>
   Generated ${esc(meta.created_utc)}. ${rows.length} entries; ${rows.filter(r=>r.kind==='observed_file').length} observed files including snapshot revisions.<br>
   Retained run: <code>${esc(meta.run_folder||'No run inspected')}</code><br>
   Declared charts/tables are conditional capabilities, not completed outputs. Observed files are presence/header evidence only. Source hashes are retained in the downloadable inventory.`;
  $('artifact-search').value=params.get('q')||'';
  if([...$('artifact-kind').options].some(o=>o.value===params.get('kind')))$('artifact-kind').value=params.get('kind');
  function renderRow(r){
   const f=window.H4Guide.evidenceInterpretation(r);
   const fieldRows=r.fields.map(item=>Array.isArray(item)?[String(item[0]),String(item[1])]:[String(item),'']);
   const fieldHTML=fieldRows.length?`<details><summary>${fieldRows.length} ${r.kind==='dashboard_panel'?'display labels':'columns / mappings'}</summary>
    ${T(['Raw column / label','Display label when mapped','Reading note (not schema validation)'],fieldRows.map(([raw,label])=>[
      `<code>${esc(raw)}</code>`,esc(label),esc(fieldReading(raw,label))]))}</details>`:'No column schema extracted for this entry; inspect its exact source/manifest.';
   const d=r.details;
   const pairing=d.plotted_csv?`<p><strong>Live pair:</strong> <code>${esc(d.base+d.plotted_csv)}</code><br><code>${esc(d.base+d.png)}</code></p>`:'';
   const presence=r.kind==='observed_file'?`<p><strong>Observed:</strong> ${esc(d.inspection)}.
     ${Object.hasOwn(d,'first_record_seen')?`First record seen: ${d.first_record_seen?'yes':'no'}; width matches header: ${d.first_record_matches_header_width?'yes':'no'}.`:''}
     ${d.changed_during_read?'Changed during inspection; not an atomic snapshot.':''}</p>`:'';
   const sourceLink=!r.source?'':r.source.endsWith('.json')?
    `<a href="https://github.com/anup080002/6gr-simulator/blob/main/${r.source.split('/').map(encodeURIComponent).join('/')}" target="_blank" rel="noopener noreferrer">Declaration · committed GitHub source ↗</a>`:
    S(r.source,'Producer / declaration source');
   return [`<strong>${esc(r.title)}</strong><br><span class="badge">${esc(r.kind.replaceAll('_',' '))}</span>
      ${r.paths.map(p=>`<div><code>${esc(p)}</code></div>`).join('')}${pairing}${presence}`,
     `<p><strong>Related interpretation:</strong> ${esc(f.title)}.</p><p>${esc(f.observe)}</p><p>${esc(f.plots)}</p>
      <p class="doc-note">Topic matching is a reading aid, not proof of this artifact’s schema, availability or metric validity.</p>
      ${sourceLink}<p><a href="#dashboard-reading">Full interpretation guide</a></p>`,
     `${fieldHTML}<details><summary>Exact extracted metadata / applicability</summary><pre>${esc(JSON.stringify(d,null,2))}</pre></details>`];
  }
  const update=()=>{const q=$('artifact-search').value.trim().toLowerCase(),kind=$('artifact-kind').value;
   table($('artifact-table'),rows.filter(r=>(!kind||r.kind===kind)&&JSON.stringify(r).toLowerCase().includes(q)),
    ['Output / panel and identity','Meaning and useful observations','Exact fields and metadata'],renderRow,0,12);};
  $('artifact-search').oninput=update;$('artifact-kind').onchange=update;update();
 }catch(e){if(stamp===epoch)error('evidence-inventory-summary',e);}
}
function flatten(obj,prefix='',out=[]){Object.entries(obj||{}).forEach(([k,v])=>{const p=prefix?`${prefix}.${k}`:k;if(v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length)flatten(v,p,out);else out.push({path:p,value:v});});return out;}
const STARTER_READINGS=[['start','Start here'],['fundamentals','Radio fundamentals'],['dashboard-reading','Understand the results'],['configuration-map','Choose a configuration'],['glossary','Terms explained']];
function navigation(){
 const q=$('search').value.trim().toLowerCase();let matches=0;
 const html=TOPICS.map((topic,i)=>{
  const topicMatch=`${topic.title} ${topic.lead}`.toLowerCase().includes(q);
  const entries=topic.entries.filter(e=>!q||topicMatch||e.label.toLowerCase().includes(q)||readingSearch.get(readingHref(e)).includes(q));
  if(!entries.length)return '';
  matches+=entries.length;
  const active=topic.id===currentTopic;
  const links=entries.map(e=>{
   const selected=active&&current===e.id&&(!e.section||e.section===currentSection);
   return `<a class="nav-reading${selected?' active':''}" href="${readingHref(e)}"${selected?' aria-current="page"':''}>${esc(e.label)}</a>`;
  }).join('');
  return `<details class="nav-topic${active?' current-topic':''}" data-topic="${topic.id}"${q||active?' open':''}>
   <summary><span class="topic-number">${String(i+1).padStart(2,'0')}</span><span class="topic-name">${esc(topic.title)}</span></summary>
   <div class="topic-readings"><a class="topic-overview" href="${topicHref(topic)}"${active&&current.startsWith('topic-')?' aria-current="page"':''}>Topic overview <span aria-hidden="true">↗</span></a>${links}</div></details>`;
 }).join('');
 const beginner=STARTER_READINGS.some(([id])=>id===current);
 const starters=`<div class="starter-navigation" aria-label="Start with the essentials">${STARTER_READINGS.map(([id,label])=>`<a href="#${id}"${current===id?' aria-current="page"':''}>${label}</a>`).join('')}</div>`;
 $('navigation').innerHTML=(!q?starters:'')+`<details id="advanced-navigation"${q||!beginner?' open':''}><summary>${q?'Search results':'All technical topics'} <span>${q?matches:TOPICS.length}</span></summary>${html||'<p class="nav-empty">No topic or subsection matches. Try a shorter term.</p>'}</details>`;
 $('nav-status').textContent=q?`${matches} matching readings · clear search to return`:'Start simple. Open technical topics when you need more detail.';
 $('navigation').setAttribute('aria-label',q?'Search results by topic':'Guide navigation');
 // Native details provide keyboard operation; open one topic at a time when
 // not searching. Search intentionally opens all matching topic groups.
 $('navigation').querySelectorAll('.nav-topic').forEach(detail=>detail.addEventListener('toggle',()=>{
  if(detail.isConnected&&detail.open&&!$('search').value.trim())$('navigation').querySelectorAll('.nav-topic[open]').forEach(other=>{if(other!==detail)other.open=false;});
 }));
}
function contextHeader(topic,position=''){
 const number=TOPICS.indexOf(topic)+1;
 $('breadcrumb').textContent=`${String(number).padStart(2,'0')} / ${topic.title}`;
 return `<div class="reading-context"><a href="${topicHref(topic)}">Topic ${String(number).padStart(2,'0')} · ${esc(topic.title)}</a>${position?`<span>${esc(position)}</span>`:''}</div>`;
}
function readingFooter(topic,entryIndex=-1){
 const topicIndex=TOPICS.indexOf(topic),previous=topic.entries[entryIndex-1],next=topic.entries[entryIndex+1];
 const back=entryIndex<0?(TOPICS[topicIndex-1]?{href:topicHref(TOPICS[topicIndex-1]),label:TOPICS[topicIndex-1].title}:null):
  previous?{href:readingHref(previous),label:previous.label}:{href:topicHref(topic),label:topic.title+' overview'};
 const forward=entryIndex<0?{href:readingHref(topic.entries[0]),label:topic.entries[0].label}:
  next?{href:readingHref(next),label:next.label}:TOPICS[topicIndex+1]?{href:topicHref(TOPICS[topicIndex+1]),label:TOPICS[topicIndex+1].title}:null;
 $('chapter-footer').innerHTML=(back?`<a class="reading-previous" href="${back.href}"><small>← Previous reading</small>${esc(back.label)}</a>`:'<span></span>')+
  (forward?`<a class="reading-next" href="${forward.href}"><small>${entryIndex<0?'Start this topic':'Read next'} →</small>${esc(forward.label)}</a>`:'<a href="#topic-orientation">Return to the guide overview ↑</a>');
}
function renderTopic(topic){
 $('content').innerHTML=contextHeader(topic)+`<div class="eyebrow">Ordered topic guide</div><h1>${esc(topic.title)}</h1><p class="lead">${esc(topic.lead)}</p>
  <p class="doc-note">Read the subsections in order or jump directly to a question. Existing chapters, source links and detailed explanations are retained; grouping is not an execution or qualification claim.</p>
  <ol class="topic-cards">${topic.entries.map((e,i)=>`<li><a href="${readingHref(e)}"><span class="reading-index">${String(i+1).padStart(2,'0')}</span><div><strong>${esc(e.label)}</strong><p>${esc(e.section?'Targeted procedure in the existing channel-by-channel walkthrough.':chapterByID.get(e.id).lead)}</p><span class="reading-action">Read ${e.section?'procedure':'chapter'} →</span></div></a></li>`).join('')}</ol>`;
 document.title=`${topic.title} · SixGR Field Guide`;readingFooter(topic);
}
function topicDirectory(){
 return `<details id="all-topics"><summary>Explore all ${TOPICS.length} technical topics</summary><section class="guide-topic-directory" aria-label="Guide topic index"><h2 id="guide-topic-index">Read the guide in ${TOPICS.length} ordered topics</h2>
  <p>Go deeper with the equations, channel procedures, source code and standards references. Each topic has its own reading order.</p>
  <ol>${TOPICS.map((t,i)=>`<li><a href="${topicHref(t)}"><span>${String(i+1).padStart(2,'0')}</span>${esc(t.title)}</a></li>`).join('')}</ol></section></details>`;
}
function pageOutline(chapter){
 const content=$('chapter-body');
 // Give existing playbook details stable, explicit routing targets without
 // copying their content into new chapters or changing authored old IDs.
 content.querySelectorAll('[data-playbook]').forEach(node=>{if(!node.id)node.id=`playbook-${node.dataset.playbook}`;});
 const headings=[...content.querySelectorAll('h2, details.playbook > summary, details.eng-contract > summary')];
 const entries=headings.map((node,i)=>{
  const target=node.tagName==='SUMMARY'?node.parentElement:node;
  if(!target.id){
   const slug=plain(node.innerHTML).toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')||String(i+1);
   let id=`section-${slug}`,suffix=2;while(document.getElementById(id))id=`section-${slug}-${suffix++}`;target.id=id;
  }
  return `<li><a href="#${chapter.id}?section=${encodeURIComponent(target.id)}">${esc(node.textContent.trim())}</a></li>`;
 });
 if(entries.length)$('page-outline').innerHTML=`<details class="page-outline"${entries.length<=8?' open':''}><summary>On this page <span>${entries.length} subsections</span></summary><ol>${entries.join('')}</ol></details>`;
}
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
  const topic=TOPICS.find(t=>`topic-${t.id}`===requested);
  const idx=CHAPTERS.findIndex(c=>c.id===requested);
  if(idx<0&&!topic){location.hash='start';return;}
  current=requested;currentSection=params.get('section')||'';
  const activeTopic=topic||topicFor(current,currentSection);currentTopic=activeTopic.id;
  const stamp=++epoch;navigation();
  $('sidebar').classList.remove('open');$('menu').setAttribute('aria-expanded','false');
  window.scrollTo({top:0,behavior:'instant'});
  if(topic){renderTopic(topic);return;}
  const c=CHAPTERS[idx];
  const entryIndex=activeTopic.entries.findIndex(e=>e.id===c.id&&(!e.section||e.section===currentSection));
  const context=contextHeader(activeTopic,`Reading ${entryIndex+1} of ${activeTopic.entries.length}`);
  $('content').innerHTML=(c.id==='start'?'<div class="eyebrow">SixGR, explained step by step</div>':context)+`<h1>${esc(c.title)}</h1><p class="lead">${esc(c.lead)}</p><div id="page-outline"></div>${c.id==='start'?'':window.H4Guide.chapterAuthority(c.id)}<article id="chapter-body">${c.body()}${c.id==='start'?topicDirectory():''}</article>`;
  document.title=`${c.title} · SixGR Field Guide`;
  readingFooter(activeTopic,entryIndex);
  const labs={start:hero,architecture:flow,grid,mimo:rankLab,harq:harqLab,rf:qamLab,prach:prachLab};
  if(labs[c.id])labs[c.id]();
  window.H4Guide.initMethodChapter(c.id);
  window.H4Guide.initEngineeringChapter?.(c.id);
  if(c.id==='configuration')configExplorer(stamp);
  if(c.id==='parameters')parameterExplorer(stamp,params);
  if(c.id==='scenarios')scenarioExplorer(stamp,params);
  if(c.id==='output-atlas')evidenceExplorer(stamp,params);
  if(c.id!=='start')pageOutline(c);
  // Deep links stay inside the chapter router. Open the containing details
  // before scrolling; a subsection ID must never be mistaken for a chapter.
  const section=params.get('section');
  if(section){
    const target=document.getElementById(section);
    if(target&&$('content').contains(target)){
      for(let node=target;node&&node!==$('content');node=node.parentElement){
        if(node.tagName==='DETAILS')node.open=true;
      }
      requestAnimationFrame(()=>{if(stamp===epoch)target.scrollIntoView({block:'start',behavior:'instant'});});
    }
  }
}
$('search').oninput=navigation;$('menu').onclick=()=>{$('sidebar').classList.toggle('open');$('menu').setAttribute('aria-expanded',String($('sidebar').classList.contains('open')));};document.addEventListener('keydown',e=>{if(e.key==='Escape'){$('sidebar').classList.remove('open');$('menu').setAttribute('aria-expanded','false');}});
$('close-menu').onclick=()=>{$('sidebar').classList.remove('open');$('menu').setAttribute('aria-expanded','false');$('menu').focus();};
try{document.body.classList.toggle('dark',localStorage.getItem('sixgr-guide-theme')==='dark');}catch{}
$('theme').onclick=()=>{document.body.classList.toggle('dark');try{localStorage.setItem('sixgr-guide-theme',document.body.classList.contains('dark')?'dark':'light');}catch{}};$('print').onclick=()=>window.print();window.addEventListener('hashchange',route);route();
})();
