"""Validate local site links and accessibility basics using only the standard library."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote

ROOT = Path(__file__).resolve().parents[2] / 'docs'

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path, self.ids, self.refs, self.errors = path, set(), [], []
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attr = dict(attrs)
        if 'id' in attr:
            if attr['id'] in self.ids:
                self.errors.append(f'duplicate id: {attr["id"]}')
            self.ids.add(attr['id'])
        if tag == 'html' and not attr.get('lang'):
            self.errors.append('missing document language')
        if tag == 'img' and ('alt' not in attr or 'width' not in attr or 'height' not in attr):
            self.errors.append('image missing alternative text or dimensions')
        if tag in ('a', 'link') and attr.get('href'):
            self.refs.append(attr['href'])
        if tag in ('img', 'source', 'script') and attr.get('src'):
            self.refs.append(attr['src'])
        if tag == 'video' and attr.get('poster'):
            self.refs.append(attr['poster'])

pages = {p.resolve(): Page(p) for p in ROOT.glob('*.html')}
errors = []
for path, page in pages.items():
    errors.extend(f'{path.name}: {e}' for e in page.errors)
    for ref in page.refs:
        url = urlsplit(ref)
        if url.scheme or url.netloc:
            continue
        target = (path.parent / unquote(url.path)).resolve() if url.path else path
        if target.is_dir():
            target /= 'index.html'
        if not target.is_file():
            errors.append(f'{path.name}: missing {ref}')
        elif url.fragment and target in pages and url.fragment not in pages[target].ids:
            errors.append(f'{path.name}: missing anchor in {ref}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'PASS: {len(pages)} HTML pages, local links/assets/anchors, unique IDs, image alternatives and dimensions')
