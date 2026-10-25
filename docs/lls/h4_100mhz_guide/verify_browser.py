"""Focused browser checks, optional screenshots. Requires installed Playwright/Chromium."""
import argparse
import json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect


def verify_topic_navigation(page, base, screenshots=None):
    """Navigation/UI only: preserve authored content, routes and tools."""
    page.goto(base + '/#start', wait_until='networkidle')
    chapters = page.evaluate('window.H4Guide.CHAPTERS.map(c=>({id:c.id,title:c.title}))')
    topics = page.evaluate('window.H4Guide.topics')
    assert 12 <= len(topics) <= 16
    assert not page.evaluate('window.H4Guide.unassignedTopicChapters')
    owned = [entry['id'] for topic in topics for entry in topic['entries'] if not entry['section']]
    assert len(owned) == len(set(owned)) == len(chapters)
    assert set(owned) == {chapter['id'] for chapter in chapters}
    expect(page.locator('#navigation > .nav-topic')).to_have_count(len(topics))
    expect(page.locator('#navigation > .nav-topic[open]')).to_have_count(1)
    assert page.locator('#navigation .nav-reading:visible').count() < len(chapters)
    expect(page.locator('#nav-status')).to_contain_text('preserved chapters')
    expect(page.locator('#guide-topic-index')).to_have_text(f'Read the guide in {len(topics)} ordered topics')
    expect(page.locator('.guide-topic-directory li')).to_have_count(len(topics))
    expect(page.locator('#chapter-footer .reading-next')).to_have_attribute('href', '#fundamentals')

    # All old chapter hashes render their original title, with ordered context
    # rather than redirecting to a replacement page or silently losing detail.
    for chapter in chapters:
        page.goto(base + '/#' + chapter['id'], wait_until='domcontentloaded')
        expect(page.locator('h1')).to_have_text(chapter['title'])
        expect(page.locator('.reading-context')).to_contain_text('Reading')
        expect(page.locator('#chapter-body')).not_to_be_empty()
        expect(page.locator('#navigation a[aria-current="page"]')).to_have_count(1)
        assert page.evaluate('''() => [...document.querySelectorAll('.page-outline a')].every(a=>{
            const section=new URLSearchParams(a.hash.split('?')[1]).get('section');
            return Boolean(document.getElementById(section));
        })'''), chapter['id']
    # Each topic is a small ordered table of contents over the same sources.
    for topic in topics:
        page.goto(base + '/#topic-' + topic['id'], wait_until='domcontentloaded')
        expect(page.locator('h1')).to_have_text(topic['title'])
        expect(page.locator('.topic-cards > li')).to_have_count(len(topic['entries']))
        expect(page.locator('#chapter-footer .reading-next')).to_have_attribute(
            'href', '#' + topic['entries'][0]['id'] + (
                '?section=' + topic['entries'][0]['section'] if topic['entries'][0]['section'] else ''))
    # Targeted procedure links open the original playbook, never a copied body.
    for topic in topics:
        for entry in topic['entries']:
            if not entry['section']:
                continue
            page.goto(base + '/#' + entry['id'] + '?section=' + entry['section'],
                      wait_until='domcontentloaded')
            expect(page.locator('#' + entry['section'])).to_have_attribute('open', '')
            expect(page.locator('#navigation .current-topic')).to_have_attribute('data-topic', topic['id'])
            expect(page.locator('#' + entry['section'] + ' > summary')).to_be_visible()

    page.goto(base + '/#coding', wait_until='networkidle')
    page.locator('.page-outline a').first.click()
    assert '?section=' in page.url
    expect(page.locator('h1')).to_have_text('TBS, CRC, LDPC and rate matching')
    expect(page.locator('#chapter-footer .reading-next')).to_have_attribute('href', '#topic-radio-link')
    page.locator('#search').fill('rate matching')
    assert 0 < page.locator('#navigation .nav-reading').count() < len(chapters)
    expect(page.locator('#nav-status')).to_contain_text('matching readings')
    page.locator('#search').fill('unfindable-navigation-example-763291')
    expect(page.locator('#navigation')).to_contain_text('No topic or subsection matches')
    page.locator('#search').fill('')
    expect(page.locator('#navigation > .nav-topic[open]')).to_have_count(1)
    # Native summary keyboard behavior and one-open-topic accordion.
    summary = page.locator('#navigation [data-topic="downlink-data"] > summary')
    summary.focus()
    page.keyboard.press('Enter')
    expect(page.locator('#navigation [data-topic="downlink-data"]')).to_have_attribute('open', '')
    expect(page.locator('#navigation > .nav-topic[open]')).to_have_count(1)
    page.locator('#navigation [data-topic="downlink-data"] .topic-overview').click()
    expect(page.locator('h1')).to_have_text('PDSCH & DL-SCH')

    # Retained source/filter/calculator behaviors, without snapshot regeneration.
    page.goto(base + '/#tx', wait_until='networkidle')
    page.locator('#chapter-body [data-source]').first.click()
    expect(page.locator('#source-dialog')).to_be_visible()
    expect(page.locator('#source-meta')).to_contain_text('SHA-256')
    page.locator('#source-find').fill('function')
    expect(page.locator('.source-line.highlight')).to_contain_text('function')
    page.locator('#close-source').click()
    page.goto(base + '/#channel-playbooks', wait_until='networkidle')
    page.locator('#playbook-search').fill('RAPID')
    expect(page.locator('[data-playbook="prach"]')).to_be_visible()
    expect(page.locator('[data-playbook="trs"]')).to_be_hidden()
    page.goto(base + '/#receiver-algorithm-lab', wait_until='networkidle')
    expect(page.locator('#eng-resource-result')).to_contain_text('7,344 gross REs')
    page.locator('#eng-reserved').fill('8000')
    expect(page.locator('#eng-resource-result')).to_contain_text('cannot exceed')
    page.goto(base + '/#grid', wait_until='networkidle')
    page.locator('#slot-select').select_option('3')
    expect(page.locator('#grid-lab')).to_contain_text('10 DL, 2 guard and 2 UL')
    page.locator('#theme').click()
    expect(page.locator('body')).to_have_class('dark')
    page.locator('#theme').click()
    if screenshots:
        screenshots.mkdir(parents=True, exist_ok=True)
        page.goto(base + '/#topic-spatial-feedback', wait_until='networkidle')
        page.screenshot(path=str(screenshots / 'ordered-topics-desktop.png'), full_page=True)
    page.set_viewport_size({'width':390, 'height':844})
    for target in ('topic-orientation', 'topic-spatial-feedback', 'receiver-algorithm-lab',
                   'channel-playbooks?section=playbook-pdsch'):
        page.goto(base + '/#' + target, wait_until='networkidle')
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 1'), target
    page.locator('#menu').click()
    expect(page.locator('#menu')).to_have_attribute('aria-expanded', 'true')
    expect(page.locator('#sidebar')).to_have_css('transform', 'none')
    assert page.locator('#sidebar').bounding_box()['y'] == 0
    expect(page.locator('#navigation [data-topic="downlink-data"] > summary')).to_be_visible()
    if screenshots:
        page.screenshot(path=str(screenshots / 'ordered-topics-mobile.png'), animations='disabled')
    page.locator('#close-menu').click()
    expect(page.locator('#menu')).to_have_attribute('aria-expanded', 'false')
    page.locator('#menu').click()
    expect(page.locator('#menu')).to_have_attribute('aria-expanded', 'true')
    page.keyboard.press('Escape')
    expect(page.locator('#menu')).to_have_attribute('aria-expanded', 'false')
    page.set_viewport_size({'width':1440, 'height':1000})
    return {'status':'PASS', 'ordered_topics':len(topics), 'preserved_chapter_routes':len(chapters),
            'targeted_procedure_links':sum(bool(e['section']) for t in topics for e in t['entries']),
            'source_filter_calculator_mobile_checks':True,
            'scope':'navigation_and_documentation_UI_only_no_PHY_or_prose_deduplication_claim'}


def verify_implementation_chapters(page, base):
    chapters = ('port-layer-measurement-flow', 'n40-reference-sweep', 'measurement-operator-maths')
    sources = set()
    for chapter in chapters:
        page.goto(base + '/#' + chapter, wait_until='networkidle')
        assert page.locator('.method-basis .badge').count() >= 3
        assert page.locator('#content details').count() >= 3
        for path in page.locator('#content [data-source]').evaluate_all(
                '(nodes) => nodes.map(n=>n.dataset.source)'):
            sources.add(path)
    from urllib.parse import quote
    for path in sources:
        response = page.request.get(base + '/api/source?path=' + quote(path, safe=''))
        assert response.ok, (path, response.status)
        assert response.json()['path'] == path
    page.goto(base + '/#port-layer-measurement-flow', wait_until='networkidle')
    page.locator('nav[aria-label="Implementation chapter navigation"] a').filter(
        has_text='CDM mathematics').click()
    expect(page).to_have_url(base + '/#port-layer-measurement-flow?section=walk-cdm')
    expect(page.locator('#walk-cdm')).to_have_attribute('open', '')
    expect(page.locator('#walk-cdm .eq')).to_be_visible()
    page.locator('#walk-cdm [data-source]').first.click()
    expect(page.locator('#source-dialog')).to_be_visible()
    expect(page.locator('#source-code')).to_contain_text('function')
    page.locator('#close-source').click()
    page.goto(base + '/#n40-reference-sweep?section=sweep-reference-math', wait_until='networkidle')
    expect(page.locator('#sweep-reference-math')).to_have_attribute('open', '')
    expect(page.locator('#sweep-reference-math')).to_contain_text('N0')
    for viewport in ({'width':390, 'height':844}, {'width':1440, 'height':1000}):
        page.set_viewport_size(viewport)
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1')
    page.goto(base + '/issues.html', wait_until='networkidle')
    expect(page.locator('#documentation-location')).to_contain_text('Issue ledger only')
    assert page.locator('#walk-ports').count() == 0
    page.locator('#repair-category-filter').select_option('fixed')
    assert page.locator('tr[data-source-line][hidden]').count() > 0
    expect(page.locator('#repair-filter-count')).to_contain_text('Showing')
    return {'implementation_chapters':len(chapters), 'current_source_links':len(sources),
            'section_navigation':True, 'source_viewer':True, 'ledger_filter':True}


def verify_engineering_handbook(page, base, screenshots=None):
    """Teaching UI/source contracts only, not MATLAB/PHY acceptance."""
    from urllib.parse import quote
    chapters = ('engineering-handbook', 'receiver-algorithm-lab', 'channel-model-lab', 'rf-port-lab')
    sources = set()
    ids = set(page.evaluate('window.H4Guide.CHAPTERS.map(c=>c.id).concat(window.H4Guide.topics.map(t=>"topic-"+t.id))'))
    for chapter in chapters:
        page.goto(base + '/#' + chapter, wait_until='networkidle')
        assert page.locator('#content .eng-pipeline li').count() >= 5
        assert page.locator('#content .eng-equation').count() >= 1
        assert page.locator('.method-basis .badge').count() >= 3
        sources.update(page.locator('#content [data-source]').evaluate_all(
            '(nodes)=>nodes.map(n=>n.dataset.source)'))
        anchors = page.locator('#content a[href^="#"]').evaluate_all(
            '(nodes)=>nodes.map(n=>n.getAttribute("href").slice(1).split("?")[0])')
        assert set(anchors) <= ids, (chapter, set(anchors) - ids)
        for viewport in ({'width':390,'height':844}, {'width':1440,'height':1000}):
            page.set_viewport_size(viewport)
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 1'), chapter
        if screenshots:
            screenshots.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(screenshots / (chapter + '.png')), full_page=True)
    for path in sources:
        response = page.request.get(base+'/api/source?path='+quote(path, safe=''))
        assert response.ok, (path, response.status)
        assert response.json()['path'] == path
    page.goto(base+'/#engineering-handbook', wait_until='networkidle')
    assert page.locator('.eng-contract').count() == 10
    page.locator('#channel-contract-4 summary').click()
    expect(page.locator('#channel-contract-4')).to_have_attribute('open','')
    page.locator('#channel-contract-4 [data-source]').first.click()
    expect(page.locator('#source-dialog')).to_be_visible()
    expect(page.locator('#source-meta')).to_contain_text('SHA-256')
    page.locator('#close-source').click()
    page.goto(base+'/#receiver-algorithm-lab', wait_until='networkidle')
    page.locator('#one-re-mimo-example summary').click()
    expect(page.locator('#one-re-mimo-example')).to_have_attribute('open', '')
    expect(page.locator('#one-re-mimo-example')).to_contain_text('Teaching example, not a retained run')
    expect(page.locator('#one-re-mimo-example')).to_contain_text('Heffective = Hphysical W')
    expect(page.locator('#pusch-independent-outcomes')).to_have_attribute('open', '')
    expect(page.locator('#pusch-independent-outcomes .eng-branches section')).to_have_count(2)
    expect(page.locator('#pusch-independent-outcomes')).to_contain_text('UL-SCH resolved')
    expect(page.locator('#eng-resource-result')).to_contain_text('7,344 gross REs')
    expect(page.locator('#eng-resource-result')).to_contain_text('26,928 bits')
    page.locator('#eng-reserved').fill('8000')
    expect(page.locator('#eng-resource-result')).to_contain_text('cannot exceed')
    page.locator('#eng-reserved').fill('0')
    page.locator('#eng-qm').select_option('4')
    expect(page.locator('#eng-resource-result')).to_contain_text('58,752 bits')
    page.locator('#eng-reserved').fill('')
    expect(page.locator('#eng-resource-result')).to_contain_text('Enter integer')
    page.goto(base+'/#rf-port-lab', wait_until='networkidle')
    expect(page.locator('#eng-power-result')).to_contain_text('11.938 dBm')
    page.locator('#eng-chains').fill('4')
    expect(page.locator('#eng-power-result')).to_contain_text('23.979 dBm')
    page.locator('#eng-chains').fill('0')
    expect(page.locator('#eng-power-result')).to_contain_text('positive integer')
    page.locator('#eng-chains').fill('64')
    page.locator('#eng-power').fill('')
    expect(page.locator('#eng-power-result')).to_contain_text('Enter a finite budget')
    page.locator('#theme').click()
    assert page.locator('body.dark').count() == 1
    page.locator('#theme').click()
    return {'engineering_chapters':4, 'channel_contracts':10, 'source_links':len(sources),
            'mimo_worked_example_and_independent_uci_flow':True,
            'calculator_arithmetic_and_invalid_inputs':True,'mobile_layout':True,
            'authority':'documentation_only_not_PHY_qualification'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://127.0.0.1:62907')
    parser.add_argument('--screenshots', type=Path)
    parser.add_argument('--implementation-only', action='store_true',
                        help='Verify only the relocated chapters, source links and ledger; no snapshot refresh.')
    parser.add_argument('--handbook-only', action='store_true',
                        help='Verify the engineering notebooks and calculators only; no MATLAB execution.')
    parser.add_argument('--navigation-only', action='store_true',
                        help='Verify compact topic navigation, old routes and retained UI tools only.')
    args = parser.parse_args()
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={'width':1440,'height':1000})
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('console', lambda e: errors.append(e.text) if e.type == 'error' else None)
        page.goto(args.url, wait_until='networkidle')
        assert page.locator('h1').inner_text().startswith('Follow one bit')
        if args.navigation_only:
            navigation = verify_topic_navigation(page, args.url.rstrip('/'), args.screenshots)
            assert not errors, errors
            print(json.dumps(navigation, indent=2))
            browser.close()
            return
        if args.handbook_only:
            handbook = verify_engineering_handbook(page, args.url.rstrip('/'), args.screenshots)
            assert not errors, errors
            print(json.dumps(handbook, indent=2))
            browser.close()
            return
        implementation = verify_implementation_chapters(page, args.url.rstrip('/'))
        if args.implementation_only:
            assert not errors, errors
            print(json.dumps(implementation, indent=2))
            browser.close()
            return
        page.goto(args.url, wait_until='networkidle')
        chapters = page.evaluate('window.H4Guide.CHAPTERS.map(c=>({id:c.id,title:c.title}))')
        word_count = page.evaluate("window.H4Guide.CHAPTERS.map(c=>{const d=document.createElement('div');d.innerHTML=c.body();return d.textContent;}).join(' ').split(/\\s+/).length")
        if args.screenshots:
            args.screenshots.mkdir(parents=True, exist_ok=True)
            page.screenshot(path=str(args.screenshots/'home.png'), full_page=True)
        for chapter in chapters:
            page.goto(args.url+'/#'+chapter['id'], wait_until='networkidle')
            assert page.locator('h1').inner_text() == chapter['title']
            assert page.locator('.method-basis').first.locator('.badge').count() > 0
        # Authority labels and links must be complete, not a silent default.
        audit = page.evaluate("""() => {
            const g=window.H4Guide, ids=new Set(g.CHAPTERS.map(c=>c.id));
            return {
                missing:g.CHAPTERS.filter(c=>!g.chapterBasis[c.id]?.length).map(c=>c.id),
                methods:g.methods.length,
                playbooks:g.playbooks.length,
                broken:g.methods.filter(m=>!ids.has(m.chapter)||!m.owners.length||
                    m.owners.some(k=>!g.FILES[k])||m.basis.some(k=>!g.basis[k])||
                    m.refs.some(k=>!g.REFS[k])).map(m=>m.id),
                unique:new Set(g.methods.map(m=>m.id)).size===g.methods.length
            };
        }""")
        assert not audit['missing'] and not audit['broken'] and audit['unique'], audit
        assert audit['methods'] >= 40 and audit['playbooks'] >= 14
        evidence = page.evaluate("""() => {
            const g=window.H4Guide;
            return {families:g.evidenceFamilies.length, standards:g.standardComparisons.length,
                missing:Object.keys(g.evidenceCoverage).filter(id=>{
                    const c=g.CHAPTERS.find(c=>c.id===id);
                    return !c || !c.body().includes('chapter-evidence');
                }),
                invalid:g.standardComparisons.filter(r=>r[3].some(k=>!g.FILES[k])||
                    r[2].some(([k])=>!g.REFS[k])).map(r=>r[0])};
        }""")
        assert evidence['families'] >= 18 and evidence['standards'] >= 18
        assert not evidence['missing'] and not evidence['invalid'], evidence
        page.goto(args.url+'/#resource-efficiency', wait_until='networkidle')
        backlog = page.evaluate("""window.H4Guide.resourceEfficiencyFixes.map(
            f=>({id:f.id,status:f.status}))""")
        assert [f['id'] for f in backlog] == ['H4-196', 'H4-197', 'H4-198']
        assert all(f['status'].startswith('OPEN') for f in backlog)
        expect(page.locator('#content')).to_contain_text('standards-permitted, resource-conservative')
        expect(page.locator('#content')).to_contain_text('changes no active YAML, MATLAB code')
        opportunity = page.locator('details').filter(
            has=page.get_by_text('Educational resource-opportunity calculation', exact=False))
        opportunity.locator('summary').click()
        expect(opportunity.locator('.equation')).to_be_visible()
        expect(opportunity).to_contain_text('not 5,400 proven recoverable data REs')
        if args.screenshots:
            page.screenshot(path=str(args.screenshots/'resource-efficiency.png'))
        page.goto(args.url+'/#comparison', wait_until='networkidle')
        page.locator('a[href="#resource-efficiency"]').last.click()
        expect(page.locator('h1')).to_contain_text('fix-later list')
        page.goto(args.url+'/#dashboard-reading', wait_until='networkidle')
        page.locator('#evidence-family-search').fill('false ACK')
        assert page.locator('[data-evidence-family="uci"]').is_visible()
        assert page.locator('[data-evidence-family="channel"]').is_hidden()
        page.goto(args.url+'/#standards-crosswalk', wait_until='networkidle')
        page.locator('#standard-search').fill('nrTBS')
        assert page.locator('[data-standard-topic="pdsch"]').is_visible()
        assert page.locator('[data-standard-topic="pusch"]').is_visible()
        assert page.locator('[data-standard-topic="ssb"]').is_hidden()
        page.goto(args.url+'/#output-atlas?kind=live_chart&q=TRS', wait_until='networkidle')
        expect(page.locator('#evidence-inventory-summary')).to_contain_text('not run acceptance')
        expect(page.locator('#artifact-table')).to_contain_text('trs_received_pilot_evm.png')
        expect(page.locator('#artifact-table')).to_contain_text('reports/live_measurements/')
        page.locator('#artifact-kind').select_option('dashboard_panel')
        page.locator('#artifact-search').fill('ssb_sync_timing')
        expect(page.locator('#artifact-table')).to_contain_text('SSB measured timing')
        page.locator('#artifact-table details').first.click()
        expect(page.locator('#artifact-table')).to_contain_text('Residual CFO')
        page.locator('#artifact-kind').select_option('runtime_csv')
        page.locator('#artifact-search').fill('pdcch_trials')
        expect(page.locator('#artifact-table')).to_contain_text('air_interface/csv/pdcch_trials.csv')
        page.locator('#artifact-search').fill('no-such-output-987654321')
        expect(page.locator('#artifact-table')).to_contain_text('No matches. Nothing has been substituted.')
        parsed = page.evaluate("""window.H4Guide.parseEvidenceCSV('a,b\\r\\n"x,y","a""b\\nc"\\r\\n')""")
        assert parsed == [['a','b'],['x,y','a"b\nc']]
        if args.screenshots:
            page.goto(args.url+'/#dashboard-reading', wait_until='networkidle')
            page.screenshot(path=str(args.screenshots/'dashboard-reading.png'))
            page.goto(args.url+'/#standards-crosswalk', wait_until='networkidle')
            page.screenshot(path=str(args.screenshots/'standards-crosswalk.png'))
            page.goto(args.url+'/#output-atlas?kind=live_chart&q=TRS', wait_until='networkidle')
            page.screenshot(path=str(args.screenshots/'output-atlas.png'))
        source_paths = page.evaluate("""[...new Set(window.H4Guide.CHAPTERS.flatMap(c=>{
            const d=document.createElement('div');d.innerHTML=c.body();
            return [...d.querySelectorAll('[data-source]')].map(a=>a.dataset.source);
        }))]""")
        from urllib.parse import quote
        for path in source_paths:
            response = page.request.get(args.url+'/api/source?path='+quote(path))
            assert response.ok, (path, response.status)
        # All generated internal chapter links must resolve.
        broken_links = page.evaluate("""() => {
            const g=window.H4Guide, ids=new Set(g.CHAPTERS.map(c=>c.id));
            return g.CHAPTERS.flatMap(c=>{
                const d=document.createElement('div');d.innerHTML=c.body();
                return [...d.querySelectorAll('a[href^="#"]')]
                    .map(a=>a.getAttribute('href').slice(1).split('?')[0])
                    .filter(id=>!ids.has(id));
            });
        }""")
        assert not broken_links, broken_links
        page.goto(args.url+'/#algorithm-register', wait_until='networkidle')
        page.locator('#method-search').fill('checkpoint')
        assert 0 < page.locator('[data-method]:visible').count() < audit['methods']
        page.locator('#method-search').fill('')
        page.locator('#method-basis').select_option('model')
        assert page.locator('[data-method="cdl"]').is_visible()
        assert page.locator('[data-method="olla"]').is_hidden()
        page.goto(args.url+'/#channel-playbooks', wait_until='networkidle')
        page.locator('#playbook-search').fill('RAPID')
        assert page.locator('[data-playbook="prach"]').is_visible()
        assert page.locator('[data-playbook="trs"]').is_hidden()
        page.goto(args.url+'/#worked-calculations', wait_until='networkidle')
        expect(page.locator('#calc-result')).to_contain_text('5.0000000%')
        expect(page.locator('#calc-result')).to_contain_text('0.260416667')
        import math
        calc = page.evaluate('window.H4Guide.teachingMath.quality(.25,100,32,4)')
        assert math.isclose(calc['evm'], .05)
        assert math.isclose(calc['nmse'], 10*math.log10(.0025))
        assert math.isclose(calc['upper'], 1-.05**.25)
        page.locator('#calc-reference').fill('0')
        expect(page.locator('#calc-result')).to_contain_text('positive reference energy')
        page.locator('#calc-reference').fill('100')
        page.locator('#calc-error').fill('0')
        expect(page.locator('#calc-result')).to_contain_text('−∞')
        page.locator('#calc-trials').fill('1.5')
        expect(page.locator('#calc-result')).to_contain_text('positive integer')
        page.goto(args.url+'/#causal-flow', wait_until='networkidle')
        page.locator('[data-causal="3"]').click()
        expect(page.locator('#causal-detail')).to_contain_text('Same-sample batch reduced')
        expect(page.locator('[data-causal="3"]')).to_have_attribute('aria-pressed','true')
        page.goto(args.url+'/#restart-flow', wait_until='networkidle')
        expect(page.locator('#content')).to_contain_text('previous failure receipt')
        if args.screenshots:
            page.goto(args.url+'/#algorithm-register', wait_until='networkidle')
            page.screenshot(path=str(args.screenshots/'algorithm-register.png'))
        # Every parameter deep link opens the declared catalog search, not a
        # source fragment that silently falls back to the home chapter.
        page.goto(args.url+'/#configuration-map', wait_until='networkidle')
        page.locator('a[href="#parameters?q=frequency.bandwidth_hz"]').first.click()
        expect(page.locator('#parameter-search')).to_have_value('frequency.bandwidth_hz')
        expect(page.locator('#parameter-table')).to_contain_text('frequency.bandwidth_hz')
        page.locator('#parameter-search').fill('')
        page.locator('#parameter-section').select_option('channels')
        page.locator('#parameter-rule').select_option('enum')
        expect(page.locator('#parameter-table')).to_contain_text('channels.profile')
        assert 'channels.delay_spread_ns' not in page.locator('#parameter-table').inner_text()
        page.locator('#parameter-rule').select_option('boolean')
        expect(page.locator('#parameter-table')).to_contain_text('channels.pathloss_enabled')
        page.goto(args.url+'/#parameters?kind=core&q=phyBackend', wait_until='networkidle')
        expect(page.locator('#parameter-summary')).to_contain_text('current native core catalog')
        expect(page.locator('#parameter-table')).to_contain_text('calibrated_link_abstraction')
        page.goto(args.url+'/#scenarios?category=scenarios&q=sls_nr_tdd_21cell', wait_until='networkidle')
        # Hash navigation starts an asynchronous inventory of every YAML. Wait
        # for that inventory, as below, before asserting filtered contents.
        expect(page.locator('#scenario-summary')).to_contain_text('YAML files', timeout=30000)
        expect(page.locator('#scenario-table')).to_contain_text('sls_nr_tdd_21cell_connected.yaml')
        assert page.locator('#scenario-table tbody tr').count() == 1
        page.goto(args.url+'/#configuration', wait_until='networkidle')
        expect(page.locator('#config-summary')).to_contain_text('Snapshot matches')
        page.locator('#config-filter').fill('total_slots')
        assert '100' in page.locator('#config-values').inner_text()
        page.goto(args.url+'/#parameters', wait_until='networkidle')
        expect(page.locator('#parameter-summary')).to_contain_text('parameter rules')
        page.locator('#parameter-search').fill('max_doppler')
        assert page.locator('#parameter-table tbody tr').count() > 0
        page.locator('#catalog-kind').select_option('matrix')
        page.locator('#parameter-search').fill('')
        expect(page.locator('#parameter-summary')).to_contain_text('0 nested')
        page.goto(args.url+'/#scenarios', wait_until='networkidle')
        expect(page.locator('#scenario-summary')).to_contain_text('YAML files', timeout=30000)
        page.locator('#scenario-search').fill('h4_100_cdlc100_connected_impaired_40db_adaptation')
        page.locator('#scenario-table [data-source]').first.click()
        expect(page.locator('#source-meta')).to_contain_text('SHA-256')
        page.locator('#source-find').fill('total_slots')
        assert 'total_slots' in page.locator('.source-line.highlight').inner_text()
        page.locator('#close-source').click()
        page.goto(args.url+'/#architecture', wait_until='networkidle')
        page.locator('[data-stage="5"]').click()
        assert 'RX chain' in page.locator('.flow-detail').inner_text()
        page.goto(args.url+'/#grid', wait_until='networkidle')
        page.locator('#slot-select').select_option('3')
        assert '10 DL, 2 guard and 2 UL' in page.locator('#grid-lab').inner_text()
        page.goto(args.url+'/#mimo', wait_until='networkidle')
        before = page.locator('#rank-lab').inner_text()
        page.locator('#rank-snr').fill('0')
        assert page.locator('#rank-lab').inner_text() != before
        page.goto(args.url+'/#prach', wait_until='networkidle')
        expect(page.locator('#prach-threshold')).to_contain_text('0.00360843918243516')
        expect(page.locator('#prach-threshold')).to_contain_text('not a 3GPP-mandated formula')
        page.locator('#prach-rx').fill('4')
        expect(page.locator('#prach-threshold')).to_contain_text('0.0144337567297406')
        page.locator('#prach-lra').select_option('839')
        expect(page.locator('#prach-threshold')).to_contain_text('0.00288675134594813')
        page.locator('#prach-rx').fill('0')
        expect(page.locator('#prach-threshold')).to_contain_text('positive integer')
        page.goto(args.url+'/#beam', wait_until='networkidle')
        expect(page.locator('#content')).to_contain_text('21')
        expect(page.locator('#content')).to_contain_text('cannot be silently applied to checkpoint45')
        page.goto(args.url+'/#adaptation', wait_until='networkidle')
        expect(page.locator('#content')).to_contain_text('due59')
        expect(page.locator('#content')).to_contain_text('MCS25')
        page.goto(args.url+'/#recipe', wait_until='networkidle')
        expect(page.locator('#content')).to_contain_text('reports/csv/execution_stage_profile.csv')
        expect(page.locator('#content')).to_contain_text('live_csv_png_interval_slots: 5')
        page.goto(args.url+'/#parameters?q=output.execution_stage_profile_enabled', wait_until='networkidle')
        expect(page.locator('#parameter-table')).to_contain_text('output.execution_stage_profile_enabled')
        page.goto(args.url+'/#parameters?q=output.live_csv_png_interval_slots', wait_until='networkidle')
        expect(page.locator('#parameter-table')).to_contain_text('output.live_csv_png_interval_slots')
        page.goto(args.url+'/#harq', wait_until='networkidle')
        page.locator('#harq-nack').click()
        page.locator('#harq-ack').click()
        assert page.locator('#harq-nack').is_disabled()
        assert 'Unique delivered bits: 1000' in page.locator('#harq-lab').inner_text()
        page.goto(args.url+'/#rf', wait_until='networkidle')
        before = page.locator('#qam-readout').inner_text()
        page.locator('#qam-select').select_option('1024')
        page.locator('#qam-phase').fill('12')
        assert page.locator('#qam-readout').inner_text() != before
        if args.screenshots:
            page.locator('#qam-canvas').scroll_into_view_if_needed()
            page.screenshot(path=str(args.screenshots/'constellation.png'))
        page.locator('#search').fill('rate matching')
        assert 0 < page.locator('#navigation a').count() < len(chapters)
        page.locator('#search').fill('')
        page.locator('#theme').click()
        assert page.locator('body').evaluate("el=>el.classList.contains('dark')")
        page.locator('#theme').click()
        page.set_viewport_size({'width':390,'height':844})
        page.goto(args.url+'/#start', wait_until='networkidle')
        page.locator('#menu').click()
        assert page.locator('#menu').get_attribute('aria-expanded') == 'true'
        page.keyboard.press('Escape')
        assert page.locator('#menu').get_attribute('aria-expanded') == 'false'
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        page.goto(args.url+'/#parameters?kind=core&q=phyBackend', wait_until='networkidle')
        expect(page.locator('#parameter-table')).to_contain_text('calibrated_link_abstraction')
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        page.goto(args.url+'/#worked-calculations', wait_until='networkidle')
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        page.goto(args.url+'/#output-atlas?kind=live_chart&q=TRS', wait_until='networkidle')
        expect(page.locator('#artifact-table')).to_contain_text('TRS received-pilot EVM')
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        page.goto(args.url+'/#standards-crosswalk', wait_until='networkidle')
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        page.goto(args.url+'/#resource-efficiency', wait_until='networkidle')
        expect(page.locator('#content')).to_contain_text('H4-198')
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth')
        if args.screenshots:
            page.screenshot(path=str(args.screenshots/'mobile.png'))
        assert not errors, errors
        print(json.dumps({'status':'PASS','chapters':len(chapters),'authored_words':word_count,
                          'source_links_verified':len(source_paths),
                          'documented_methods':audit['methods'],'channel_playbooks':audit['playbooks'],
                          'dashboard_families':evidence['families'],
                          'standards_comparisons':evidence['standards'],
                          'browser_errors':errors,'scope':'documentation_only_no_simulation'}))
        browser.close()


if __name__ == '__main__':
    main()
