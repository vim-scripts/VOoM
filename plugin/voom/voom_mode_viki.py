"""
VOoM markup mode for headline markup used by Vim Viki/Deplate plugin
    http://www.vim.org/scripts/script.php?script_id=861
    http://deplate.sourceforge.net/Markup.html#hd0010004
Also used in Emacs OrgMode
    http://orgmode.org/org.html#Headlines

* headline level 1
some text
** headline level 2
more text
*** headline level 3
**** headline level 4
etc.

First * must be at start of line.
There must be a space after last * .
"""

# can access main module voom.py, including global outline data
#import sys
#if 'voom' in sys.modules:
    #voom = sys.modules['voom']
    #VOOMS = voom.VOOMS

import re
headline_match = re.compile(r'^(\*+) ').match


def hook_makeOutline(body, blines):
    """Return (tlines, bnodes, levels) for list of Body lines.
    blines can also be Vim buffer object.
    """
    Z = len(blines)
    tlines, bnodes, levels = [], [], []
    tlines_add, nodes_add, levels_add = tlines.append, bnodes.append, levels.append
    for i in xrange(Z):
        if not blines[i].startswith('*'):
            continue
        bline = blines[i]
        m = headline_match(bline)
        if not m:
            continue
        lev = len(m.group(1))
        head = bline[lev:].strip()
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
    bodyLines = ['%s NewHeadline' %('*'*level), '']
    column = level+2
    return (tree_head, bodyLines, column)


def hook_changeLevBodyHead(body, h, delta):
    """Increase of decrease level number of Body headline by delta."""
    if delta==0: return h
    m = headline_match(h)
    level = len(m.group(1))
    s = '*'*(level+delta)
    return '%s %s' %(s, h[m.end(1)+1:])

