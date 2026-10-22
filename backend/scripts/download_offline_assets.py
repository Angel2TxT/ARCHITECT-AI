"""Download offline fonts and icons for ARCHITECT."""

import hashlib
import os
from pathlib import Path
import re
import urllib.request

fonts_dir = Path("c:/UNI/ARCHITECT/frontend/web/static/fonts")
fonts_dir.mkdir(parents=True, exist_ok=True)

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

font_configs = [
    {
        "family": "Inter",
        "css_url": "https://fonts.googleapis.com/css2?family=Inter:wght@100..900&display=swap",
        "output_css": "inter.css",
    },
    {
        "family": "Material Symbols Outlined",
        "css_url": "https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap",
        "output_css": "material-symbols.css",
    },
    {
        "family": "IBM Plex Sans",
        "css_url": "https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@300;400;500;600;700&display=swap",
        "output_css": "ibm-plex-sans.css",
    },
]

combined_css = []

for cfg in font_configs:
    family = cfg["family"]
    print(f"Fetching CSS for {family}...")
    req = urllib.request.Request(cfg["css_url"], headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        css_text = resp.read().decode("utf-8")

    urls = set(re.findall(r"url\((https://fonts\.gstatic\.com/[^\)]+)\)", css_text))
    print(f"Found {len(urls)} font files for {family}")

    replacements = {}
    for url in urls:
        ext = ".woff2" if ".woff2" in url else ".woff"
        h = hashlib.md5(url.encode()).hexdigest()[:8]
        slug = family.lower().replace(" ", "-")
        filename = f"{slug}-{h}{ext}"
        filepath = fonts_dir / filename
        if not filepath.exists():
            print(f"Downloading {filename}...")
            req_f = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req_f) as f_resp:
                filepath.write_bytes(f_resp.read())
        replacements[url] = f"/static/fonts/{filename}"

    for old_url, new_url in replacements.items():
        css_text = css_text.replace(old_url, new_url)

    (fonts_dir / cfg["output_css"]).write_text(css_text, encoding="utf-8")
    combined_css.append(f"/* === {family} === */\n" + css_text)

(fonts_dir / "fonts.css").write_text("\n\n".join(combined_css), encoding="utf-8")
print("Successfully generated all font files and fonts.css!")
