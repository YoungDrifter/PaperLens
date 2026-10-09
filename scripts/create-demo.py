"""Create the original example PDFs used in the README screenshots (reportlab)."""
from pathlib import Path
import argparse
import re
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.utils import simpleSplit
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('version', help='Target semantic version, e.g. 1.0.0')
args = parser.parse_args()
if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
    parser.error('version must be MAJOR.MINOR.PATCH')
OUT = ROOT / 'docs/versions' / args.version / 'demo'
try:
    OUT.mkdir(parents=True, exist_ok=False)
except FileExistsError:
    parser.error(f'refusing to overwrite existing demo: {OUT}')
INK, MUTED, BLUE = map(HexColor, ['#202b3b','#6b7789','#376be6'])

def text(c,x,y,s,size=12,font='Helvetica',color=INK):
    c.setFillColor(color); c.setFont(font,size); c.drawString(x,y,s)
def lines(c,y,s,width=800):
    for line in simpleSplit(s,'Helvetica',13,width):
        text(c,80,y,line,13); y-=21
    return y

def page(c,n,label,title,sub):
    c.setFillColor(HexColor('#fdfdfc'));c.rect(0,0,960,620,fill=1,stroke=0)
    text(c,80,579,'PAPERLENS  /  SAMPLE DOCUMENT',10,'Helvetica-Bold',MUTED)
    text(c,800,579,label,10,'Helvetica-Bold',BLUE)
    text(c,80,510,title,36,'Helvetica-Bold')
    text(c,80,475,sub,14,'Helvetica',MUTED)
    c.setStrokeColor(HexColor('#dce3ee'));c.line(80,447,880,447)
    text(c,80,30,'Original demo content for PaperLens',10,'Helvetica',MUTED)
    text(c,850,30,f'{n:02}',10,'Helvetica',MUTED)

def cards(c,entries):
    for i,(title,description) in enumerate(entries):
        x=80+i*274
        c.setFillColor(HexColor('#eef3ff')); c.roundRect(x,85,252,152,12,fill=1,stroke=0)
        text(c,x+22,199,f'0{i+1}',11,'Helvetica-Bold',BLUE)
        text(c,x+22,167,title,19,'Helvetica-Bold')
        y=137
        for line in simpleSplit(description,'Helvetica',12,208):
            text(c,x+22,y,line,12,'Helvetica',MUTED);y-=19

c=canvas.Canvas(str(OUT/'PaperLens Guide.pdf'), pagesize=(960,620))
c.setTitle('PaperLens Guide');c.setAuthor('PaperLens')
for n,(anchor,title,sub,paragraph,entries) in enumerate([
    ('focus','A little room to think.','Read closely. Keep your ideas beside the page.',
     'A quiet reading space helps you stay with the ideas in front of you. Open a document, explore its structure and keep useful passages close at hand.',
     [('Open','Bring a PDF into your workspace.'),('Explore','Follow outlines, bookmarks and search.'),('Remember','Keep highlights and comments with the document.')]),
    ('navigate','Keep the thread.','Move between pages without losing your place.',
     'Research rarely happens in a straight line. Compare a source, revisit a definition and return to the argument. Each tab remembers where you left off.',
     [('Outline','Jump to a section or chapter.'),('Bookmarks','Keep important pages close at hand.'),('Search','Find a phrase inside the current PDF.')]),
    ('annotate','Turn reading into ideas.','Highlights and comments, right where they belong.',
     'Mark a useful passage and capture why it matters. Return to the original context whenever you revisit your notes.',
     [('Highlight','Mark the passages that matter.'),('Comment','Place a card, write a note, and resize it.'),('Revisit','Keep your notes next to the source.')])],1):
    page(c,n,f'0{n} / READING',title,sub);c.bookmarkPage(anchor);c.addOutlineEntry(title,anchor)
    text(c,80,405,'Less interface. More understanding.',19,'Helvetica-Bold')
    lines(c,371,paragraph);cards(c,entries);c.showPage()
c.save()

c=canvas.Canvas(str(OUT/'Getting Started.pdf'), pagesize=(960,620));c.setTitle('Getting Started');c.setAuthor('PaperLens')
page(c,1,'QUICK START','From file to focus.','Start reading with PaperLens in a few simple steps.')
text(c,80,405,'Your document is the starting point.',20,'Helvetica-Bold')
lines(c,369,'Open a PDF or drag it into PaperLens. Explore its pages, mark the passages that matter and keep a few notes beside the original context.')
cards(c,[('Open a PDF','Choose a file or drop it into the reading window.'),('Find your place','Follow the outline, use bookmarks or search for a phrase.'),('Keep an idea','Add a highlight, a comment or a bookmark for later.')])
c.showPage();c.save()

c=canvas.Canvas(str(OUT/'Features.pdf'), pagesize=(960,620));c.setTitle('Features');c.setAuthor('PaperLens')
page(c,1,'FEATURES','Everything close at hand.','A native macOS PDF reader built around the document.')
text(c,80,405,'Read. Explore. Remember.',20,'Helvetica-Bold')
lines(c,369,'Move between related documents without losing your place. Familiar window controls, a compact toolbar and a shared sidebar keep your reading space simple.')
for i,(color,title,desc) in enumerate([('#e8eefb','Tabs & windows','Read several PDFs and keep each document in its own context.'),('#dcebe5','Highlights & notes','Capture useful passages and comments next to the page.'),('#f3e5d1','Pages & navigation','Follow outlines and bookmarks, or rearrange pages.')]):
    x=80+i*274;c.setFillColor(HexColor(color));c.roundRect(x,85,252,152,12,fill=1,stroke=0)
    text(c,x+22,180,title,17,'Helvetica-Bold');y=143
    for line in simpleSplit(desc,'Helvetica',12,208):text(c,x+22,y,line,12,'Helvetica',MUTED);y-=19
c.showPage();c.save()
for filename, title, subtitle, paragraph, entries in [
    ('Reading Notes', 'Keep a useful idea.', 'Small notes make close reading easier.',
     'Capture the reason a passage matters. A short comment beside the page keeps your thought connected to the original text.',
     [('Notice', 'Read slowly and find a useful passage.'), ('Write', 'Keep one clear idea in each comment.'), ('Return', 'Revisit the source when you need the context.')]),
    ('Research Notes', 'Follow the argument.', 'Bring related sources into one reading space.',
     'Compare documents in separate tabs. Keep your place in each source, then follow outlines and bookmarks to the next useful section.',
     [('Compare', 'Keep related documents open in tabs.'), ('Connect', 'Follow the ideas across your sources.'), ('Remember', 'Leave a bookmark for the next reading session.')]),
]:
    c = canvas.Canvas(str(OUT / f'{filename}.pdf'), pagesize=(960,620))
    c.setTitle(filename); c.setAuthor('PaperLens')
    page(c, 1, 'READING NOTES', title, subtitle)
    text(c,80,405,'Read with a little room to think.',20,'Helvetica-Bold')
    lines(c,369,paragraph); cards(c,entries)
    c.showPage(); c.save()
print('Created five original PaperLens product demo PDFs.')
