"""
VOoM markup mode for HTML headings.

<h1>headline level 1</h1>
some text
 <h2> headline level 2 </h2>
more text
 <H3  ALIGN="CENTER"> headline level 3 </H3>
 <  h4 >    headline level 4       </H4    >
  some text <h4> <font color=red> headline 5 </font> </H4> </td></div>
     etc.

Both tags must be on the same line.
Closing tag must start with </h or </H  --no whitespace after < or /
All html tags are deleted from Tree headlines.

WARNING: When outlining real web page, moving nodes around will very likely
screw up html.

"""

# can access main module voom.py, including global outline data
#import sys
#if 'voom' in sys.modules:
    #voom = sys.modules['voom']
    #VOOMS = voom.VOOMS

import re
headline_search = re.compile(r'<\s*h(\d+).*?>(.*?)</h(\1)\s*>', re.IGNORECASE).search
html_tag_sub = re.compile('<.*?>').sub


def hook_makeOutline(body, blines):
    """Return (tlines, bnodes, levels) for list of Body lines.
    blines can also be Vim buffer object.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, nodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        bline = blines[i]
        if not ('</h' in bline or '</H' in bline):
            continue
        m = headline_search(bline)
        if not m:
            continue
        lev = int(m.group(1))
        head = m.group(2)
        # delete all html tags
        head = html_tag_sub('',head)
        tline = '  %s|%s' %('. '*(lev-1), head.strip())
        tlines_add(tline)
        nodes_add(i+1)
        levels_add(lev)
    return (tlines, bnodes, levels)


def hook_newHeadline(body, level):
    """Return (tree_head, bodyLines, column).
    tree_head is new headline string in Tree buffer (text after |).
    bodyLines is list of lines to insert in Body buffer.
    column is cursor position in new headline in Body buffer.
    """
    tree_head = 'NewHeadline'
    bodyLines = ['<h%s>NewHeadline</h%s>' %(level,level), '']
    column = 5
    return (tree_head, bodyLines, column)


def hook_changeLevBodyHead(body, h, delta):
    """Increase of decrease level number of Body headline by delta."""
    if delta==0: return h
    m = headline_search(h)
    level = int(m.group(1))
    lev = level+delta
    return '%s%s%s%s%s' %(h[:m.start(1)], lev, h[m.end(1):m.start(3)], lev, h[m.end(3):])

