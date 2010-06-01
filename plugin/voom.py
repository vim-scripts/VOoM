# voom.py
# VOoM (Vim Outliner of Markers): two-pane outliner and related utilities
# plugin for Python-enabled Vim version 7.x
# Website: http://www.vim.org/scripts/script.php?script_id=2657
# Author:  Vlad Irnov (vlad DOT irnov AT gmail DOT com)
# License: This program is free software. It comes without any warranty,
#          to the extent permitted by applicable law. You can redistribute it
#          and/or modify it under the terms of the Do What The Fuck You Want To
#          Public License, Version 2, as published by Sam Hocevar.
#          See http://sam.zoy.org/wtfpl/COPYING for more details.
# Version: 2.1, 2010-06-01

"""This module is meant to be imported by voom.vim ."""

import vim
import sys, os, re
import traceback
import bisect
#Vim = sys.modules['__main__']

# see voom.vim for conventions
# voom_WhatEver() means it's Python code for Voom_WhatEver() Vim function


#---Constants and Settings--------------------{{{1

# default start fold marker and regexp
MARKER = '{{{'                             # }}}
MARKER_RE = re.compile(r'{{{(\d+)(x?)')    # }}}

voom_dir = vim.eval('s:voom_dir')
voom_script = vim.eval('s:voom_script_py')

# {filetype: make_head_<filetype> function, ...}
MAKE_HEAD = {}


class VoomData: #{{{1
    """Container for global data."""
    def __init__(self):
        # Vim buffer objects, {bnr : vim.buffer, ...}
        self.buffers = {}
        # {body: [list of headline lnums], ...}
        self.nodes ={}
        # {body: [list of headline levels], ...}
        self.levels ={}
        # {body : snLn, ...}
        self.snLns = {}
        # {body : first Tree line, ...}
        self.names = {}
        # {body : &filetype, ...}
        self.filetypes = {}
        # {body : chars to strip from right side of Tree headlines, ...}
        self.rstrip_chars = {}
        # {body : start fold marker if not default, ...}
        self.markers = {}
        # {body : start fold marker regexp if not default, ...}
        self.markers_re = {}

#VOOM=VoomData()
# VOOM, an instance of VoomData, is created from voom.vim, not here.
# Thus, this module can be reloaded without destroying data.


#---Outline Construction----------------------{{{1


def makeOutline(body, blines): #{{{2=
    """Return (tlines, nodes, levels) for list of Body lines.
    Optimized for lists in which most items don't have fold markers.
    """
    marker = VOOM.markers.get(body, MARKER)
    marker_re_search = VOOM.markers_re.get(body, MARKER_RE).search
    tlines, nodes, levels = [], [], []
    tlines_add, nodes_add, levels_add = tlines.append, nodes.append, levels.append
    h = MAKE_HEAD.get(VOOM.filetypes[body], 0)
    if not h:
        c = VOOM.rstrip_chars[body]
        for i in xrange(len(blines)):
            if not marker in blines[i]: continue
            bline = blines[i]
            match = marker_re_search(bline)
            if not match: continue
            lev = int(match.group(1))
            head = bline[:match.start()].lstrip().rstrip(c).strip('-=~').strip()
            tline = ' %s%s%s%s' %(match.group(2) or ' ', '. '*(lev-1), '|', head)
            tlines_add(tline)
            nodes_add(i+1)
            levels_add(lev)
    else:
        for i in xrange(len(blines)):
            if not marker in blines[i]: continue
            bline = blines[i]
            match = marker_re_search(bline)
            if not match: continue
            lev = int(match.group(1))
            head = h(bline,match)
            tline = ' %s%s%s%s' %(match.group(2) or ' ', '. '*(lev-1), '|', head)
            tlines_add(tline)
            nodes_add(i+1)
            levels_add(lev)
    return (tlines, nodes, levels)


#--- make_head functions --- {{{2

def make_head_html(bline,match):
    s = bline[:match.start()].strip().strip('-=~').strip()
    if s.endswith('<!'):
        return s[:-2].strip()
    else:
        return s
MAKE_HEAD['html'] = make_head_html

#def make_head_vim(bline,match):
#    return bline[:match.start()].lstrip().rstrip('" \t').strip('-=~').strip()
#MAKE_HEAD['vim'] = make_head_vim

#def make_head_py(bline,match):
#    return bline[:match.start()].lstrip().rstrip('# \t').strip('-=~').strip()
#for ft in 'python ruby perl tcl'.split():
#    MAKE_HEAD[ft] = make_head_py


def updateTree(body): #{{{2
    """Construct outline for Body body.
    Update lines in Tree buffer if needed.
    This can be run from any buffer as long as Tree is set to ma.
    """
    ##### Construct outline #####
    blines = VOOM.buffers[body][:]
    tlines, nodes, levels  = makeOutline(body, blines)
    tlines[0:0], nodes[0:0], levels[0:0] = [VOOM.names[body]], [1], [1]
    VOOM.nodes[body], VOOM.levels[body] = nodes, levels

    ##### Add the = mark #####
    snLn = VOOM.snLns[body]
    size = len(VOOM.nodes[body])
    # snLn got larger than the number of nodes because some nodes were
    # deleted while editing the Body
    if snLn > size:
        snLn = size
        vim.command('let s:voom_bodies[%s].snLn=%s' %(body, size))
        VOOM.snLns[body] = size
    tlines[snLn-1] = '=%s' %tlines[snLn-1][1:]

    ##### Compare tree lines, draw as needed ######
    # Draw all tree lines only when needed. This is optimization for large
    # outlines, e.g. >1000 tree lines. Drawing all lines is slower than
    # comparing all lines and then drawing nothing or just one line.

    tree = int(vim.eval('s:voom_bodies[%s].tree' %body))
    Tree = VOOM.buffers[tree]
    tlines_ = Tree[:]
    if not len(tlines_)==len(tlines):
        Tree[:] = tlines
        return

    # If only one line is modified, draw that line only. This ensures that
    # editing (and inserting) a single headline in a large outline is fast.
    # If more than one line is modified, draw all lines from first changed line
    # to the end of buffer.
    draw_one = False
    for i in xrange(len(tlines)):
        if not tlines[i]==tlines_[i]:
            if draw_one==False:
                draw_one = True
                diff = i
            else:
                Tree[diff:] = tlines[diff:]
                return
    if draw_one:
        Tree[diff] = tlines[diff]


def computeSnLn(body, blnr): #{{{2
    """Compute Tree lnum for node at line blnr in Body body.
    Assign Vim and Python snLn vars.
    """
    # snLn should be 1 if blnr is before the first node, top of Body
    snLn = bisect.bisect_right(VOOM.nodes[body], blnr)
    vim.command('let s:voom_bodies[%s].snLn=%s' %(body, snLn))
    VOOM.snLns[body] = snLn


def verifyTree(body): #{{{2
    """Verify Tree and VOOM data."""
    tree = int(vim.eval('s:voom_bodies[%s].tree' %body))
    tlines_ = VOOM.buffers[tree][:]

    blines = VOOM.buffers[body][:]
    tlines, nodes, levels  = makeOutline(body, blines)
    tlines[0:0], nodes[0:0], levels[0:0] = [VOOM.names[body]], [1], [1]
    snLn = VOOM.snLns[body]
    tlines[snLn-1] = '=%s' %tlines[snLn-1][1:]

    if not tlines_ == tlines:
        #print 'VOoM: DIFFERENT tree lines'
        vim.command("echoerr 'VOoM: DIFFERENT tree lines'")
    if not VOOM.nodes[body] == nodes:
        #print 'VOoM: DIFFERENT nodes'
        vim.command("echoerr 'VOoM: DIFFERENT nodes'")
    if not VOOM.levels[body] == levels:
        #print 'VOoM: DIFFERENT levels'
        vim.command("echoerr 'VOoM: DIFFERENT levels'")


def voom_Init(body): #{{{2
    """This is part of Voom_Init(), called from Body."""
    VOOM.buffers[body] = vim.current.buffer
    VOOM.snLns[body] = 1
    VOOM.names[body] = vim.eval('l:firstLine')

    marker = vim.eval('&foldmarker').split(',')[0]
    if not marker=='{{{': # }}}
        VOOM.markers[body] = marker
        VOOM.markers_re[body] = re.compile(re.escape(marker) + r'(\d+)(x?)')

    VOOM.filetypes[body] = vim.eval('&filetype')

    if vim.eval("has_key(g:voom_rstrip_chars,&ft)")=="1":
        rstrip_chars = vim.eval("g:voom_rstrip_chars[&ft]")
    else:
        rstrip_chars = vim.eval("&commentstring").split('%s')[0].strip() + " \t"
    VOOM.rstrip_chars[body] = rstrip_chars


def voom_TreeCreate(): #{{{2
    """This is part of Voom_TreeCreate(), called from Tree."""
    body = int(vim.eval('a:body'))
    nodes = VOOM.nodes[body]
    Body = VOOM.buffers[body]
    # current Body lnum
    blnr = int(vim.eval('s:voom_bodies[a:body].blnr'))
    z = len(nodes)

    ### compute snLn, create Tree folding

    # find node marked with '='
    # find nodes marked with 'o'
    snLn = 0
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    marker_re_search = marker_re.search
    oFolds = []
    for i in xrange(1,z):
        bline = Body[nodes[i]-1]
        # part of Body headline after marker+level+'x'
        bline2 = bline[marker_re_search(bline).end():]
        if not bline2: continue
        if bline2[0]=='=':
            snLn = i+1
        elif bline2[0]=='o':
            oFolds.append(i+1)
            if bline2[1:] and bline2[1]=='=':
                snLn = i+1

    # create Tree folding
    if oFolds:
        cFolds = foldingFlip(2,z,oFolds,body)
        foldingCreate(2,z,cFolds)

    if snLn:
        vim.command('let s:voom_bodies[%s].snLn=%s' %(body, snLn))
        VOOM.snLns[body] = snLn
        # set blnShow if it's different from current Body node
        # TODO: really check for current Body node?
        if z>2 and (blnr==1 or blnr<nodes[1]):
            vim.command('let blnShow=%s' %nodes[snLn-1])
    else:
        # no Body headline is marked with =
        # select current Body node
        computeSnLn(body, blnr)


def voom_UnVoom(): #{{{2
    body, tree = int(vim.eval('a:body')), int(vim.eval('a:tree'))
    if tree in VOOM.buffers: del VOOM.buffers[tree]
    if body in VOOM.buffers: del VOOM.buffers[body]
    if body in VOOM.nodes:   del VOOM.nodes[body]
    if body in VOOM.levels:  del VOOM.levels[body]
    if body in VOOM.snLns:   del VOOM.snLns[body]
    if body in VOOM.names:   del VOOM.names[body]
    if body in VOOM.filetypes: del VOOM.filetypes[body]
    if body in VOOM.rstrip_chars: del VOOM.rstrip_chars[body]
    if body in VOOM.markers:    del VOOM.markers[body]
    if body in VOOM.markers_re: del VOOM.markers_re[body]


#---parents, children, etc.-------------------{{{1
# helpers for outline traversal


def nodeHasChildren(body, lnum): #{{{2
    """Determine if node at Tree line lnum has children."""
    levels = VOOM.levels[body]
    if lnum==1 or lnum==len(levels): return False
    elif levels[lnum-1] < levels[lnum]: return True
    else: return False


def nodeSubnodes(body, lnum): #{{{2
    """Number of all subnodes for node at Tree line lnum."""
    levels = VOOM.levels[body]
    z = len(levels)
    if lnum==1 or lnum==z: return 0
    lev = levels[lnum-1]
    for i in xrange(lnum,z):
        if levels[i]<=lev:
            return i-lnum
    return z-lnum


def nodeParent(body, lnum): #{{{2
    """Return lnum of closest parent of node at Tree line lnum."""
    levels = VOOM.levels[body]
    lev = levels[lnum-1]
    if lev==1: return None
    for i in xrange(lnum-2,0,-1):
        if levels[i] < lev: return i+1


def nodeParents(body, lnum): #{{{2
    """Return lnums of parents of node at Tree line lnum."""
    levels = VOOM.levels[body]
    lev = levels[lnum-1]
    if lev==1: return []
    parents = []
    for i in xrange(lnum-2,0,-1):
        levi = levels[i]
        if levi < lev:
            lev = levi
            parents.append(i+1)
            if lev==1:
                parents.reverse()
                return parents


def nodeUNL(body, lnum): #{{{2
    """Compute UNL of node at Tree line lnum.
    Returns list of headlines.
    """
    tree = int(vim.eval('s:voom_bodies[%s].tree' %body))
    Tree = VOOM.buffers[tree]
    levels = VOOM.levels[body]
    if lnum==1: return ['top-of-file']
    parents = nodeParents(body,lnum)
    parents.append(lnum)
    heads = [Tree[ln-1].split('|',1)[1] for ln in parents]
    return heads


#---Outline Navigation------------------------{{{1


def voom_TreeSelect(): #{{{2
    # Get first and last lnums of Body node for Tree line lnum.
    # This is called from Body
    lnum = int(vim.eval('a:lnum'))
    body = int(vim.eval('l:body'))
    VOOM.snLns[body] = lnum

    nodeStart =  VOOM.nodes[body][lnum-1]
    vim.command('let l:nodeStart=%s' %nodeStart)

    if lnum==len(VOOM.nodes[body]):
        # last node
        vim.command("let l:nodeEnd=line('$')+1")
    else:
        # "or 1" takes care of situation when:
        # lnum is 1 (path info line);
        # first Body line is a headline.
        # In that case VOOM.nodes is [1, 1, ...]
        nodeEnd =  VOOM.nodes[body][lnum]-1 or 1
        vim.command('let l:nodeEnd=%s' %nodeEnd)


def voom_TreeToStartupNode(): #{{{2
    body = int(vim.eval('l:body'))
    nodes = VOOM.nodes[body]
    Body = VOOM.buffers[body]
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    z = len(nodes)
    # find Body headlines marked with '='
    lnums = []
    for i in xrange(1,z):
        bline = Body[nodes[i]-1]
        # part of Body headline after marker+level+'x'+'o'
        bline2 = bline[marker_re.search(bline).end():]
        if not bline2: continue
        if bline2[0]=='=':
            lnums.append(i+1)
        elif bline2[0]=='o':
            if bline2[1:] and bline2[1]=='=':
                lnums.append(i+1)
    vim.command('let l:lnums=%s' %repr(lnums))


def voom_GetUNL(): #{{{2
    buftype = vim.eval('l:buftype')
    body = int(vim.eval('l:body'))
    lnum = int(vim.eval('l:lnum'))

    if buftype=='body':
        lnum = bisect.bisect_right(VOOM.nodes[body], lnum)

    heads = nodeUNL(body,lnum)
    UNL = ' -> '.join(heads)
    vim.command("let @n='%s'" %UNL.replace("'", "''"))
    for h in heads[:-1]:
        h = h.replace("'", "''")
        vim.command("echohl ModeMsg")
        vim.command("echon '%s'" %h)
        vim.command("echohl Title")
        vim.command("echon ' -> '")
    h = heads[-1].replace("'", "''")
    vim.command("echohl ModeMsg")
    vim.command("echon '%s'" %h)
    vim.command("echohl None")


def voom_Grep(): #{{{2
    body = int(vim.eval('l:body'))
    nodes = VOOM.nodes[body]
    matchesAND, matchesNOT = vim.eval('l:matchesAND'), vim.eval('l:matchesNOT')

    # convert blnums of mathes into tlnums, that is node numbers
    tlnumsAND, tlnumsNOT = [], [] # lists of AND and NOT "tlnums" dicts
    counts = {} # {tlnum: count of all AND matches in this node, ...}
    blnums = {} # {tlnum: first AND match in this node, ...}
    for L in matchesAND:
        tlnums = {} # {tlnum of node with a match:0, ...}
        L.pop()
        for bln in L:
            bln = int(bln)
            tln = bisect.bisect_right(nodes, bln)
            if not tln in blnums:
                blnums[tln] = bln
            elif blnums[tln] > bln:
                blnums[tln] = bln
            if tln in counts:
                counts[tln]+=1
            else:
                counts[tln] = 1
            tlnums[tln] = 0
        tlnumsAND.append(tlnums)
    for L in matchesNOT:
        tlnums = {} # {tlnum of node with a match:0, ...}
        L.pop()
        for bln in L:
            bln = int(bln)
            tln = bisect.bisect_right(nodes, bln)
            tlnums[tln] = 0
        tlnumsNOT.append(tlnums)

    # if there are only NOT patterns
    if not matchesAND:
        tlnumsAND = [{}.fromkeys(range(1,len(nodes)+1))]

    # compute intersection
    results = intersectDicts(tlnumsAND, tlnumsNOT)
    results = results.keys()
    results.sort()
    #print results

    # need this to left-align UNLs in the qflist
    max_size = 0
    for t in results:
        if not matchesAND:
            blnums[t] = nodes[t-1]
            counts[t] = 0
        size = len('%s%s%s' %(t, counts[t], blnums[t]))
        if size > max_size:
            max_size = size

    # list of dictionaries for setloclist() or setqflist()
    loclist = []
    for t in results:
        size = len('%s%s%s' %(t, counts[t], blnums[t]))
        spaces = ' '*(max_size - size)
        UNL = ' -> '.join(nodeUNL(body, t)).replace("'", "''")
        text = 'n%s:%s%s|%s' %(t, counts[t], spaces, UNL)
        d = "{'text':'%s', 'lnum':%s, 'bufnr':%s}, " %(text, blnums[t], body)
        loclist .append(d)
    #print '\n'.join(loclist)

    vim.command("call setqflist([%s],'a')" %(''.join(loclist)) )


def intersectDicts(dictsAND, dictsNOT): #{{{2
    """Arguments are two lists of dictionaries. Keys are Tree lnums.
    Return dict: intersection of all dicts in dictsAND and non-itersection with
    all dicts in dictsNOT.
    """
    if not dictsAND: return {}
    D1 = dictsAND[0]
    if len(dictsAND)==1:
        res = D1
    else:
        res = {}
    # get intersection with all other AND dicts
    for D in dictsAND[1:]:
        for item in D1:
            if item in D: res[item] = 0
    # get non-intersection with NOT dicts
    for D in dictsNOT:
        keys = res.keys()
        for key in keys:
            if key in D: del res[key]
    return res


#---Outline Operations------------------------{{{1
# oopOp() functions are called by Voom_Oop Vim functions.
# They use local Vim vars set by the caller and can create and change Vim vars.
# They set lines in Tree and Body via vim.buffer objects.


def changeLevTreeHead(h, delta): #{{{2
    """Increase of decrese level of Tree headline by delta:
    insert or delete  delta*". "  string.
    """
    if delta>0:
        return '%s%s%s' %(h[:2], '. '*delta, h[2:])
    elif delta<0:
        return '%s%s' %(h[:2], h[2-2*delta:])
    else:
        return h


def changeLevBodyHead(h, delta, body): #{{{2
    """Increase of decrese level number of Body headline by delta."""
    if delta==0: return h
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    m = marker_re.search(h)
    level = int(m.group(1))
    return '%s%s%s' %(h[:m.start(1)], level+delta, h[m.end(1):])


def setClipboard(s): #{{{2
    """Set Vim + register (system clipboard) to string s."""
    if not s: return
    # use '%s' for Vim string: all we need to do is double ' quotes
    s = s.replace("'", "''")
    vim.command("let @+='%s'" %s)


def oopSelEnd(): #{{{2
    """This is part of Voom_Oop() checks.
    Selection in Tree starts at line ln1 and ends at line ln2.
    Selection can have many sibling nodes: nodes with the same level as ln1 node.
    Return lnum of last node in the last sibling node's branch.
    Return 0 if selection is invalid.
    """
    body = int(vim.eval('l:body'))
    ln1, ln2  = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    if ln1==1: return 0
    levels = VOOM.levels[body]
    z, lev0 = len(levels), levels[ln1-1]
    for i in xrange(ln1,z):
        lev = levels[i]
        # invalid selection: there is node with level lower than that of ln1 node
        if i+1 <= ln2 and lev < lev0: return 0
        # node after the last sibling node's branch
        elif i+1 > ln2 and lev <= lev0: return i
    return z


def oopInsert(as_child=False): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln, ln_status = int(vim.eval('l:ln')), vim.eval('l:ln_status')
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    levels = VOOM.levels[body]

    # Compute where to insert and at what level.
    # Insert new headline after node at ln.
    # If node is folded, insert after the end of node's tree.
    # default level
    lev = levels[ln-1]
    # after first Tree line
    if ln==1: lev=1
    # as_child always inserts as first child of current node, even if it's folded
    elif as_child: lev+=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif lev < levels[ln]:
        # folded: insert after current node's branch, same level
        if ln_status=='folded': ln += nodeSubnodes(body,ln)
        # not folded, insert as child
        else: lev+=1

    # remove = mark before modifying Tree
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    # insert headline in Tree and Body
    # bLnum is new headline ln in Body
    marker = VOOM.markers.get(body, MARKER)
    treeLine = '= %s%sNewHeadline' %('. '*(lev-1), '|')
    bodyLine = '---NewHeadline--- %s%s' %(marker, lev)
    if ln==len(levels):
        Tree.append(treeLine)
        bLnum = len(Body[:])
        Body.append([bodyLine, ''])
    else:
        Tree[ln:ln] = [treeLine]
        bLnum = VOOM.nodes[body][ln]-1
        Body[bLnum:bLnum] = [bodyLine, '']

    vim.command('let bLnum=%s' %(bLnum+1))

    # write = mark and set snLn to new headline
    Tree[ln] = '=' + Tree[ln][1:]
    VOOM.snLns[body] = ln+1
    vim.command('let s:voom_bodies[%s].snLn=%s' %(body, ln+1))


def oopPaste(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln, ln_status = int(vim.eval('l:ln')), vim.eval('l:ln_status')
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    levels, nodes = VOOM.levels[body], VOOM.nodes[body]

    # default l:bnlShow is -1 -- pasting not possible
    vim.command('let l:blnShow=-1')
    ### clipboard
    bText = vim.eval('@+')
    if not bText:
        vim.command("call Voom_WarningMsg('VOoM: clipboard is empty')")
        return
    blines = bText.split('\n') # Body lines to paste
    pHeads, pNodes, pLevels = makeOutline(body, blines)

    ### verify that clipboard is a valid Voom text
    if pNodes==[] or pNodes[0]!=1:
        vim.command("call Voom_ErrorMsg('VOoM: INVALID CLIPBOARD (no marker on first line)')")
        return
    lev_ = pLevels[0]
    for lev in pLevels:
        # there is node with level higher than that of root nodes
        if lev < pLevels[0]:
            vim.command("call Voom_ErrorMsg('VOoM: INVALID CLIPBOARD (root level error)')")
            return
        # level incremented by 2 or more
        elif lev-lev_ > 1:
            vim.command("call Voom_WarningMsg('VOoM: WARNING, CLIPBOARD ERROR (level incremented by >2)', ' ')")
            #return
        lev_ = lev

    ### compute where to insert and at what level
    # insert nodes after node at ln at level lev
    # if node is folded, insert after the end of node's tree
    lev = levels[ln-1] # default level
    # after first Tree line
    if ln==1: lev=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif lev < levels[ln]:
        # folded: insert after current node's branch, same level
        if ln_status=='folded': ln += nodeSubnodes(body,ln)
        # not folded, insert as child
        else: lev+=1

    ### adjust levels of nodes being inserted
    levDelta = lev - pLevels[0]
    if levDelta:
        pHeads = [changeLevTreeHead(h, levDelta) for h in pHeads]
        pLevels = [(lev+levDelta) for lev in pLevels]
        for bl in pNodes:
            blines[bl-1] = changeLevBodyHead(blines[bl-1], levDelta, body)

    # remove = mark before modifying Tree
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### insert headlines in Tree; levels in levels
    Tree[ln:ln] = pHeads
    levels[ln:ln] = pLevels

    ### insert body lines in Body
    if ln==len(nodes): bln = len(Body[:])
    else             : bln = nodes[ln]-1
    Body[bln:bln] = blines
    vim.command('let blnShow=%s' %(bln+1))

    ### start and end lnums of inserted region
    ln1 = ln+1
    ln2 = ln+len(pNodes)
    vim.command('let l:ln1=%s' %ln1)
    vim.command('let l:ln2=%s' %ln2)
    # set snLn to first headline of inserted nodes
    Tree[ln1-1] = '=' + Tree[ln1-1][1:]
    VOOM.snLns[body] = ln1

    ### update nodes
    # increment nodes being pasted
    for i in xrange(0,len(pNodes)):
        pNodes[i]+=bln
    # increment nodes after pasted region
    delta = len(blines)
    for i in xrange(ln,len(nodes)):
        nodes[i]+=delta
    # insert pNodes after ln
    nodes[ln:ln] = pNodes


def oopUp(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnUp1, lnUp2 = int(vim.eval('l:lnUp1')), int(vim.eval('l:lnUp2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    ### compute change in level
    # current level of root nodes in selection
    levOld = levels[ln1-1]
    # new level of root nodes in selection
    # lnUp1 is fist child of lnUp2, insert also as first child
    if levels[lnUp2-1] + 1 == levels[lnUp1-1]:
        levNew = levels[lnUp1-1]
    # all other cases, includes insertion after folded node
    else:
        levNew = levels[lnUp2-1]
    levDelta = levNew-levOld

    ### remove snLn mark before doing anything with Tree lines
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### tree lines to move; levels in VOOM.levels to move
    tlines = Tree[ln1-1:ln2]
    nLevels = levels[ln1-1:ln2]
    if levDelta:
        tlines = [changeLevTreeHead(h, levDelta) for h in tlines]
        nLevels = [(lev+levDelta) for lev in nLevels]
    #print '-'*10; print '\n'.join(tlines)

    ### move tree lines; update VOOM.levels
    # cut, then insert
    Tree[ln1-1:ln2] = []
    Tree[lnUp1-1:lnUp1-1] = tlines
    levels[ln1-1:ln2] = []
    levels[lnUp1-1:lnUp1-1] = nLevels

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VOOM.snLns[body] = lnUp1

    ### body lines to move
    bln1 = nodes[ln1-1]
    if ln2==len(nodes): bln2 = len(Body[:])
    else              : bln2 = nodes[ln2]-1
    blines = Body[bln1-1:bln2]
    if levDelta:
        for bl in nodes[ln1-1:ln2]:
            blines[bl-bln1] = changeLevBodyHead(blines[bl-bln1], levDelta, body)
    #print '-'*10; print '\n'.join(blines); print '-'*10

    ### move body lines: cut, then insert
    blnUp1 = nodes[lnUp1-1] # insert before this line
    Body[bln1-1:bln2] = []
    Body[blnUp1-1:blnUp1-1] = blines

    ###update nodes
    # increment lnums in the range before which the move is made
    delta = bln2-bln1+1
    for i in xrange(lnUp1-1,ln1-1):
        nodes[i]+=delta
    # decrement lnums in the range which is being moved
    delta = bln1-blnUp1
    for i in xrange(ln1-1,ln2):
        nodes[i]-=delta
    # cut, insert
    nLines = nodes[ln1-1:ln2]
    nodes[ln1-1:ln2] = []
    nodes[lnUp1-1:lnUp1-1] = nLines

    # lnum of Body node to show
    blnShow = blnUp1
    vim.command('let blnShow=%s' %blnShow)

#  ..............
#  .............. blnUp1-1
#  ============== blnUp1=nodes[lnUp1-1]
#  range before
#  which to move
#  ..............
#  ============== bln1=nodes[ln1-1]
#  range being
#  moved
#  .............. bln2=nodes[ln2]-1, can be last line
#  ==============
#  ..............


def oopDown(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnDn1, lnDn1_status = int(vim.eval('l:lnDn1')), vim.eval('l:lnDn1_status')
    # note: lnDn1 == ln2+1
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    ### compute change in level, and line after which to insert
    # current level
    levOld = levels[ln1-1]
    # new level is either that of lnDn1 or +1
    levNew = levels[lnDn1-1]
    # line afer which to insert
    lnIns = lnDn1
    if lnDn1==len(levels): # end of Tree
        pass
    # lnDn1 has children; insert as child unless it's folded
    elif levels[lnDn1-1] < levels[lnDn1]:
        if lnDn1_status=='folded':
            lnIns += nodeSubnodes(body,lnDn1)
        else:
            levNew+=1
    levDelta = levNew-levOld

    ### remove snLn mark before doing anything with Tree lines
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### tree lines to move; levels to move
    tlines = Tree[ln1-1:ln2]
    if levDelta:
        tlines = [changeLevTreeHead(h, levDelta) for h in tlines]
    nLevels = levels[ln1-1:ln2]
    if levDelta:
        nLevels = [(lev+levDelta) for lev in nLevels]

    ### move tree lines; update VOOM.levels
    # insert, then cut
    Tree[lnIns:lnIns] = tlines
    Tree[ln1-1:ln2] = []
    levels[lnIns:lnIns] = nLevels
    levels[ln1-1:ln2] = []

    ### compute and add snLn mark
    snLn = lnIns+1-(ln2-ln1+1)
    Tree[snLn-1] = '=' + Tree[snLn-1][1:]
    VOOM.snLns[body] = snLn
    vim.command('let snLn=%s' %snLn)

    ### body lines to move
    bln1 = nodes[ln1-1]
    bln2 = nodes[ln2]-1
    blines = Body[bln1-1:bln2]
    if levDelta:
        for bl in nodes[ln1-1:ln2]:
            blines[bl-bln1] = changeLevBodyHead(blines[bl-bln1], levDelta, body)

    ### move body lines: insert, then cut
    if lnIns==len(nodes): blnIns = len(Body)
    else                : blnIns = nodes[lnIns]-1
    Body[blnIns:blnIns] = blines
    Body[bln1-1:bln2] = []

    ###update nodes
    # increment lnums in the range which is being moved
    delta = blnIns-bln2
    for i in xrange(ln1-1,ln2):
        nodes[i]+=delta
    # decrement lnums in the range after which the move is made
    delta = bln2-bln1+1
    for i in xrange(ln2,lnIns):
        nodes[i]-=delta
    # insert, cut
    nLines = nodes[ln1-1:ln2]
    nodes[lnIns:lnIns] = nLines
    nodes[ln1-1:ln2] = []

    # lnum of Body node to show
    blnShow = nodes[snLn-1]
    vim.command('let blnShow=%s' %blnShow)

#  ..............
#  ============== bln1=nodes[ln1-1]
#  range being
#  moved
#  .............. bln2=nodes[ln2]-1
#  ============== blnDn1=nodes[lnDn1-1]
#  range after
#  which to move
#  .............. blnIns=nodes[lnIns]-1 or last Body line
#  ==============


def oopRight(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    ### Move right means increment level by 1 for all nodes in the range.

    # can't move right if ln1 node is child of previous node
    if levels[ln1-1] > levels[ln1-2]:
        vim.command('let l:blnShow=-1')
        return

    ### change levels of Tree lines, VOOM.levels
    tlines = Tree[ln1-1:ln2]
    tlines = [changeLevTreeHead(h, 1) for h in tlines]
    nLevels = levels[ln1-1:ln2]
    nLevels = [(lev+1) for lev in nLevels]
    Tree[ln1-1:ln2] = tlines
    levels[ln1-1:ln2] = nLevels

    ### change level numbers in Body headlines
    for bln in nodes[ln1-1:ln2]:
        bline = Body[bln-1]
        Body[bln-1] = changeLevBodyHead(bline, 1, body)

    ### set snLn to ln1
    snLn = VOOM.snLns[body]
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VOOM.snLns[body] = snLn

    # lnum of Body node to show
    blnShow = nodes[snLn-1]
    vim.command('let blnShow=%s' %blnShow)


def oopLeft(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    ### Move left means decrement level by 1 for all nodes in the range.

    # can't move left if at top level 1
    if levels[ln1-1]==1:
        vim.command('let l:blnShow=-1')
        return
    # can't move left if the range is not at the end of tree
    elif ln2!=len(levels) and levels[ln2]==levels[ln1-1]:
        vim.command('let l:blnShow=-1')
        return

    ### change levels of Tree lines, VOOM.levels
    tlines = Tree[ln1-1:ln2]
    tlines = [changeLevTreeHead(h, -1) for h in tlines]
    nLevels = levels[ln1-1:ln2]
    nLevels = [(lev-1) for lev in nLevels]
    Tree[ln1-1:ln2] = tlines
    levels[ln1-1:ln2] = nLevels

    ### change level numbers in Body headlines
    for bln in nodes[ln1-1:ln2]:
        bline = Body[bln-1]
        Body[bln-1] = changeLevBodyHead(bline, -1, body)

    ### set snLn to ln1
    snLn = VOOM.snLns[body]
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VOOM.snLns[body] = snLn

    # lnum of Body node to show
    blnShow = nodes[snLn-1]
    vim.command('let blnShow=%s' %blnShow)


def oopCopy(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    # body lines to copy
    bln1 = nodes[ln1-1]
    if ln2==len(nodes): bln2 = len(Body[:])
    else              : bln2 = nodes[ln2]-1
    blines = Body[bln1-1:bln2]

    setClipboard('\n'.join(blines))


def oopCut(): #{{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    lnUp1 = int(vim.eval('l:lnUp1'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    ### remove snLn mark before doing anything with Tree lines
    snLn = VOOM.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### delet tree lines, levels
    Tree[ln1-1:ln2] = []
    levels[ln1-1:ln2] = []

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VOOM.snLns[body] = lnUp1

    ### copy and delete body lines
    bln1 = nodes[ln1-1]
    if ln2==len(nodes): bln2 = len(Body[:])
    else              : bln2 = nodes[ln2]-1
    blines = Body[bln1-1:bln2]

    setClipboard('\n'.join(blines))
    Body[bln1-1:bln2] = []

    ###update nodes
    # decrement lnums after deleted range
    delta = bln2-bln1+1
    for i in xrange(ln2,len(nodes)):
        nodes[i]-=delta
    # cut
    nodes[ln1-1:ln2] = []

    # lnum of Body node to show
    blnShow = nodes[lnUp1-1]
    vim.command('let blnShow=%s' %blnShow)

#  ..............
#  .............. blnUp1-1
#  ============== blnUp1=nodes[lnUp1-1]
#  ..............
#  ============== bln1=nodes[ln1-1]
#  range being
#  deleted
#  .............. bln2=nodes[ln2]-1, can be last line
#  ==============
#  ..............


def oopMark(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    marker_re = VOOM.markers_re.get(body, MARKER_RE)

    for i in xrange(ln1-1,ln2):
        # insert 'x' in Tree line
        tline = Tree[i]
        if tline[1]!='x':
            Tree[i] = '%sx%s' %(tline[0], tline[2:])
            # insert 'x' in Body headline
            bln = nodes[i]
            bline = Body[bln-1]
            end = marker_re.search(bline).end(1)
            Body[bln-1] = '%sx%s' %(bline[:end], bline[end:])


def oopUnmark(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln1, ln2 = int(vim.eval('l:ln1')), int(vim.eval('l:ln2'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    marker_re = VOOM.markers_re.get(body, MARKER_RE)

    for i in xrange(ln1-1,ln2):
        # remove 'x' from Tree line
        tline = Tree[i]
        if tline[1]=='x':
            Tree[i] = '%s %s' %(tline[0], tline[2:])
            # remove 'x' from Body headline
            bln = nodes[i]
            bline = Body[bln-1]
            end = marker_re.search(bline).end(1)
            # remove one 'x', not enough
            #Body[bln-1] = '%s%s' %(bline[:end], bline[end+1:])
            # remove all consecutive 'x' chars
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('x'))


def oopMarkSelected(): # {{{2
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    ln = int(vim.eval('l:ln'))
    Body, Tree = VOOM.buffers[body], VOOM.buffers[tree]
    nodes, levels = VOOM.nodes[body], VOOM.levels[body]

    marker_re = VOOM.markers_re.get(body, MARKER_RE)

    bln_selected = nodes[ln-1]
    # remove '=' from all other Body headlines
    # also, strip 'x' and 'o' after removed '='
    for bln in nodes[1:]:
        if bln==bln_selected: continue
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        bline2 = bline[end:]
        if not bline2: continue
        if bline2[0]=='=':
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('=xo'))
        elif bline2[0]=='o' and bline2[1:] and bline2[1]=='=':
            Body[bln-1] = '%s%s' %(bline[:end+1], bline[end+1:].lstrip('=xo'))

    # insert '=' in current Body headline, but only if it's not there already
    bline = Body[bln_selected-1]
    end = marker_re.search(bline).end()
    bline2 = bline[end:]
    if not bline2:
        Body[bln_selected-1] = '%s=' %bline
        return
    if bline2[0]=='=':
        return
    elif bline2[0]=='o' and bline2[1:] and bline2[1]=='=':
        return
    elif bline2[0]=='o':
        end+=1
    Body[bln_selected-1] = '%s=%s' %(bline[:end], bline[end:])


#---Tree Folding Operations-------------------{{{1
# Opened/Closed Tree buffer folds are equivalent to Expanded/Contracted nodes.
# By default, folds are closed.
# Opened folds are marked by 'o' in Body headlines (after 'x', before '=').
#
# To determine which folds are currently closed/opened, we open all closed
# folds one by one, from top to bottom, starting from top level visible folds.
# This produces list of closed folds.
#
# To restore folding according to a list of closed folds:
#   open all folds;
#   close folds from bottom to top.
#
# Conventions:
#   cFolds --lnums of closed folds
#   oFolds --lnums of opened folds
#   ln, ln1, ln2  --Tree line number
#
# NOTE: Cursor position and window view are not restored here.
#

def voom_OopFolding(action): #{{{2
    body = int(vim.eval('l:body'))
    # check and adjust range lnums
    # don't worry about invalid range lnums: Vim checks that
    if not action=='cleanup':
        ln1, ln2 = int(vim.eval('a:ln1')), int(vim.eval('a:ln2'))
        if ln2<ln1: ln1,ln2=ln2,ln1 # probably redundant
        if ln2==1: return
        #if ln1==1: ln1=2
        if ln1==ln2:
            ln2 = ln2 + nodeSubnodes(body, ln2)
            if ln1==ln2: return

    if action=='save':
        cFolds = foldingGet(ln1, ln2)
        foldingWrite(ln1, ln2, cFolds, body)
    elif action=='restore':
        cFolds = foldingRead(ln1, ln2, body)
        foldingCreate(ln1, ln2, cFolds)
    elif action=='cleanup':
        foldingCleanup(body)


def foldingGet(ln1, ln2): #{{{2
    """Get all closed folds in line range ln1-ln2, including subfolds.
    If line ln2 is visible and is folded, its subfolds are included.
    """
    cFolds = []
    lnum = ln1
    # go through top level folded lines (visible closed folds)
    while lnum < ln2+1:
        # line lnum is first line of a closed fold
        if int(vim.eval('foldclosed(%s)' %lnum))==lnum:
            cFolds.append(lnum)
            # line after this fold and subfolds
            foldend = int(vim.eval('foldclosedend(%s)' %lnum))+1
            lnum0 = lnum
            lnum = foldend
            vim.command('keepj normal! %sGzo' %lnum0)
            # open every folded line in this fold
            for ln in xrange(lnum0+1, foldend):
                # line ln is first line of a closed fold
                if int(vim.eval('foldclosed(%s)' %ln))==ln:
                    cFolds.append(ln)
                    vim.command('keepj normal! %sGzo' %ln)
        else:
            lnum+=1

    cFolds.reverse()
    # close back opened folds
    for ln in cFolds:
        vim.command('keepj normal! %sGzc' %ln)
    return cFolds


def foldingFlip(ln1, ln2, folds, body): #{{{2
    """Convert list of opened/closed folds in range ln1-ln2 into list of
    closed/opened folds.
    """
    # This also eliminates lnums of nodes without children.
    folds = {}.fromkeys(folds)
    folds_flipped = []
    for ln in xrange(ln1,ln2+1):
        if nodeHasChildren(body, ln) and not ln in folds:
            folds_flipped.append(ln)
    folds_flipped.reverse()
    return folds_flipped


def foldingCreate(ln1, ln2, cFolds): #{{{2
    """Create folds in range ln1-ln2 from a list of closed folds in that range.
    The list must be reverse sorted.
    """
    #cFolds.sort()
    #cFolds.reverse()
    #vim.command('keepj normal! zR')
    vim.command('%s,%sfoldopen!' %(ln1,ln2))
    for ln in cFolds:
        vim.command('keepj normal! %sGzc' %ln)


def foldingRead(ln1, ln2, body): #{{{2
    """Read "o" marks in Body headlines."""
    cFolds = []
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    nodes = VOOM.nodes[body]
    Body = VOOM.buffers[body]

    for ln in xrange(ln1,ln2+1):
        if not nodeHasChildren(body, ln):
            continue
        bline = Body[nodes[ln-1]-1]
        end = marker_re.search(bline).end()
        if end<len(bline) and bline[end]=='o':
            continue
        else:
            cFolds.append(ln)

    cFolds.reverse()
    return cFolds


def foldingWrite(ln1, ln2, cFolds, body): #{{{2
    """Write "o" marks in Body headlines."""
    cFolds = {}.fromkeys(cFolds)
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    nodes = VOOM.nodes[body]
    Body = VOOM.buffers[body]

    for ln in xrange(ln1,ln2+1):
        if not nodeHasChildren(body, ln):
            continue
        bln = nodes[ln-1]
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        isClosed = ln in cFolds
        # headline is marked with 'o'
        if end<len(bline) and bline[end]=='o':
            # remove 'o' mark
            if isClosed:
                Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('ox'))
        # headline is not marked with 'o'
        else:
            # add 'o' mark
            if not isClosed:
                if end==len(bline):
                    Body[bln-1] = '%so' %bline
                elif bline[end] != 'o':
                    Body[bln-1] = '%so%s' %(bline[:end], bline[end:])


def foldingCleanup(body): #{{{2
    """Remove "o" marks from  from nodes without children."""
    marker_re = VOOM.markers_re.get(body, MARKER_RE)
    nodes = VOOM.nodes[body]
    Body = VOOM.buffers[body]

    for ln in xrange(2,len(nodes)+1):
        if nodeHasChildren(body, ln): continue
        bln = nodes[ln-1]
        bline = Body[bln-1]
        end = marker_re.search(bline).end()
        if end<len(bline) and bline[end]=='o':
            Body[bln-1] = '%s%s' %(bline[:end], bline[end:].lstrip('ox'))


#---EXECUTE SCRIPT----------------------------{{{1
#

def voom_GetLines(): #{{{2
    body = int(vim.eval('l:body'))
    ln1 = int(vim.eval('a:lnum'))

    vim.command('let nodeStart=%s' %(VOOM.nodes[body][ln1-1]) )

    ln2 = ln1 + nodeSubnodes(body, ln1)
    if ln2==len(VOOM.nodes[body]): # last line
        vim.command('let nodeEnd="$"')
    else:
        nodeEnd = VOOM.nodes[body][ln2]-1
        vim.command('let nodeEnd=%s' %nodeEnd )
    # (nodeStart,nodeEnd) can be (1,0), see voom_TreeSelect()
    # it doesn't matter here


def voom_GetLines1(): #{{{2

    buftype = vim.eval('l:buftype')
    body = int(vim.eval('l:body'))
    lnum = int(vim.eval('l:lnum'))
    if buftype=='body':
        lnum = bisect.bisect_right(VOOM.nodes[body], lnum)

    bln1 =  VOOM.nodes[body][lnum-1]
    vim.command("let l:bln1=%s" %bln1)

    if lnum==len(VOOM.nodes[body]):
        # last node
        vim.command("let l:bln2='$'")
    else:
        bln2 =  VOOM.nodes[body][lnum]-1 or 1
        vim.command("let l:bln2=%s" %bln2)


def execScript(): #{{{2
    """Execute script file."""
    #sys.path.insert(0, voom_dir)
    try:
        #d = {'vim':vim, 'VOOM':VOOM, 'voom':sys.modules[__name__]}
        d = { 'vim':vim, 'VOOM':VOOM, 'voom':sys.modules['voom'] }
        execfile(voom_script, d)
        print '---end of Python script---'
    except Exception:
        typ,val,tb = sys.exc_info()
        lines = traceback.format_exception(typ,val,tb)
        print ''.join(lines)
    #del sys.path[0]


#---LOG BUFFER--------------------------------{{{1
#
class LogBufferClass: #{{{2
    """A file-like object for replacing sys.stdout and sys.stdin with a Vim buffer."""
    def __init__(self): #{{{3
        self.buffer = vim.current.buffer
        self.logbnr = vim.eval('bufnr("")')
        self.buffer[0] = 'Python Log buffer ...'
        self.encoding = vim.eval('&enc')
        self.join = False

    def write(self,s): #{{{3
        """Append string to buffer, scroll Log windows in all tabs."""
        # Messages are terminated by sending '\n' (null string? ^@).
        # Thus "print '\n'" sends '\n' twice.
        # The message itself can contain '\n's.
        # One line can be sent in many strings which don't always end with \n.
        # This is certainly true for Python errors and for 'print a, b, ...' .

        # Can't append unicode strings. This produces an error:
        #  :py vim.current.buffer.append(u'test')

        # Can't have '\n' in appended list items, so always use splitlines().
        # A trailing \n is lost after splitlines(), but not for '\n\n' etc.
        #print self.buffer.name

        if not s: return
        # Nasty things happen when printing to unloaded PyLog buffer.
        # This also catches printing to noexisting buffer, as in pydoc help() glitch.
        if vim.eval("bufloaded(%s)" %self.logbnr)=='0':
            vim.command("echoerr 'VOoM (PyLog): PyLog buffer %s is unloaded or doesn''t exist'" %self.logbnr)
            vim.command("echoerr 'VOoM (PyLog): unable to write string:'")
            vim.command("echom '%s'" %(repr(s).replace("'", "''")) )
            vim.command("echoerr 'VOoM (PyLog): please try executing command Voomlog to fix'")
            return

        try:
            if type(s) == type(u" "):
                s = s.encode(self.encoding)

            # Join with previous message if it had no ending newline.
            if self.join==True:
                s = self.buffer[-1] + s
                del self.buffer[-1]

            if s[-1]=='\n':
                self.join = False
            else:
                self.join = True

            self.buffer.append(s.splitlines())
        except:
            typ,val,tb = sys.exc_info()
            lines1 = traceback.format_exception(typ,val,tb) # items can contain newlines
            lines2 = []
            for line in lines1:
                lines2+=line.splitlines()
            self.buffer.append('')
            self.buffer.append('VOoM: exception writing to PyLog buffer:')
            self.buffer.append(repr(s))
            self.buffer.append(lines2)
            self.buffer.append('')

        vim.command('call Voom_LogScroll()')


# modelines {{{1
# vim:fdm=marker:fdl=0:
# vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart):
