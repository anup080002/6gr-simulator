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
        source_paths = page.evaluate("""[...new Set(window.H4Guide.CHAPTERS.flatMap(c=>{
            const d=document.createElement('div');d.innerHTML=c.body();
            return [...d.querySelectorAll('[data-source]')].map(a=>a.dataset.source);
        }))]""")
        from urllib.parse import quote
        for path in source_paths:
            response = page.request.get(args.url+'/api/source?path='+quote(path))
            assert response.ok, (path, response.status)
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
        if args.screenshots:
            page.screenshot(path=str(args.screenshots/'mobile.png'))
        assert not errors, errors
        print(json.dumps({'status':'PASS','chapters':len(chapters),'authored_words':word_count,
                          'source_links_verified':len(source_paths),
                          'browser_errors':errors,'scope':'documentation_only_no_simulation'}))
        browser.close()


if __name__ == '__main__':
    main()
