#!/usr/bin/env python3
"""Add one release to a Sparkle appcast.xml (creating it if missing); newest item first.

Usage: update-appcast.py APPCAST VERSION BUILD URL LENGTH ED_SIGNATURE [--notes-file FILE]
Re-running for the same build replaces its item, so a release can be retried.
"""
import sys, re, email.utils, datetime
from xml.sax.saxutils import escape

TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>FlowMate</title>
    <link>https://github.com/as206em/FlowMate</link>
    <description>FlowMate updates</description>
    <language>en</language>
{items}  </channel>
</rss>
"""

def item(version, build, url, length, signature, notes):
    html = "<br>".join(escape(line) for line in notes.strip().splitlines()) or f"FlowMate {escape(version)}"
    return f"""    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))}</pubDate>
      <sparkle:version>{escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{html}]]></description>
      <enclosure url="{escape(url)}" length="{length}" type="application/octet-stream" sparkle:edSignature="{escape(signature)}"/>
    </item>
"""

def main(argv):
    if len(argv) < 7:
        sys.exit(__doc__)
    path, version, build, url, length, signature = argv[1:7]
    notes = ""
    if "--notes-file" in argv:
        notes = open(argv[argv.index("--notes-file") + 1], encoding="utf-8").read()
    try:
        existing = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        existing = ""
    # Keep earlier items, dropping any with this build number
    old = [m for m in re.findall(r"    <item>.*?</item>\n", existing, flags=re.S)
           if f"<sparkle:version>{escape(build)}</sparkle:version>" not in m]
    items = item(version, build, url, length, signature, notes) + "".join(old)
    open(path, "w", encoding="utf-8").write(TEMPLATE.format(items=items))

main(sys.argv)
