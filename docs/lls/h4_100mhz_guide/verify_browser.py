"""Focused browser checks, optional screenshots. Requires installed Playwright/Chromium."""
import argparse
import json
from pathlib import Path
from playwright.sync_api import sync_playwright, expect


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://127.0.0.1:62907')
    parser.add_argument('--screenshots', type=Path)
    args = parser.parse_args()
    errors = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={'width':1440,'height':1000})
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('console', lambda e: errors.append(e.text) if e.type == 'error' else None)
        page.goto(args.url, wait_until='networkidle')
        assert page.locator('h1').inner_text().startswith('Follow one bit')
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
        if args.screenshots:
            page.screenshot(path=str(args.screenshots/'mobile.png'))
        assert not errors, errors
        print(json.dumps({'status':'PASS','chapters':len(chapters),'authored_words':word_count,
                          'source_links_verified':len(source_paths),
                          'documented_methods':audit['methods'],'channel_playbooks':audit['playbooks'],
                          'browser_errors':errors,'scope':'documentation_only_no_simulation'}))
        browser.close()


if __name__ == '__main__':
    main()
