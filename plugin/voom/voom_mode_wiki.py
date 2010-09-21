"""
VOoM markup mode for MediaWiki headline markup. This is the most common Wiki
format. Should be suitable for Wikipedia, vim.wikia.com, etc.

= headline level 1 =
body text
== headline level 2 ==
body text
=== headline level 3 ===

First = must be at start of line.
Trailing whitespace is ok.
Closing = are required.

HTML comment tags are ok if they are after the headline:
==== headline level 4 ==== <!--{{{4-->  
===== headline level 5 ===== <!--comment--> <!--comment-->


DIFFERENCES FROM ACTUAL MEDIAWIKI FORMAT

1) Headlines are not ignored inside <pre>, <nowiki> and other special blocks.

2) Only trailing HTML comment tags are stripped.
This valid headline is not recognized:
<!-- comment -->=== missed me ===

This is ok, but comment is displayed in Tree buffer:
=== headline level 3 <!-- comment --> ===


REFERENCES
http://www.mediawiki.org/wiki/Help:Formatting
http://www.mediawiki.org/wiki/Markup_spec
http://meta.wikimedia.org/wiki/Help:Section
http://en.wikipedia.org/wiki/Help:Section
http://en.wikipedia.org/wiki/Wikipedia:Manual_of_Style#Section_headings

"""

# can access main module voom.py, including global outline data
#import sys
#if 'voom' in sys.modules:
    #voom = sys.modules['voom']
    #VOOMS = voom.VOOMS

import re
comment_tag_sub = re.compile('<!--.*?-->\s*$').sub
headline_match = re.compile(r'^(=+).*(\1)\s*$').match


def hook_makeOutline(body, blines):
    """Return (tlines, bnodes, levels) for list of Body lines.
    blines can also be Vim buffer object.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, nodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].startswith('='):
            continue
        bline = blines[i]
        if '<!--' in bline:
            bline = comment_tag_sub('',bline)
        bline = bline.strip()
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        head = bline[lev:-lev].strip()
        tline = '  %s|%s' %('. '*(lev-1), head)
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
    bodyLines = ['%sNewHeadline%s' %('='*level,'='*level), '']
    column = level+1
    return (tree_head, bodyLines, column)


def hook_changeLevBodyHead(body, h, delta):
    """Increase of decrease level number of Body headline by delta."""
    if delta==0: return h
    hs = h # need to strip trailing comment tags first
    if '<!--' in h:
        hs = comment_tag_sub('',hs)
    m = headline_match(hs)
    level = len(m.group(1))
    s = '='*(level+delta)
    return '%s%s%s%s' %(s, h[m.end(1):m.start(2)], s, h[m.end(2):])

