# voof.py
# VOOF (Vim Outliner Of Folds): two-pane outliner and related utilities
# plugin for Python-enabled Vim version 7.x
# Author: Vlad Irnov  (vlad.irnov AT gmail DOT com)
# License: this software is in the public domain
# Version: 1.1, 2009-05-26

'''This module is meant to be imported by voof.vim .'''
import vim
import sys, os, re
import traceback
Vim = sys.modules['__main__']

#---Constants and Settings---{{{1

# default fold marker regexp
FOLD_MARKER = re.compile(r'{{{(\d+)(x?)')    # }}}

voof_dir = vim.eval('g:voof_dir')
voof_script = vim.eval('g:voof_script_py')


class VoofData: #{{{1
    '''Container for global data.'''
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

#VOOF=VoofData()
# VOOF, an instance of VoofData, is created from voof.vim, not here.
# Thus, this module can be reloaded without destroying data.


#---Outline Construction-----{{{1

def init(body): #{{{2
    '''This is part of Voof_Init(), called from Body.'''
    VOOF.buffers[body] = vim.current.buffer
    VOOF.snLns[body] = 1
    VOOF.names[body] = vim.eval('firstLine')

def treeCreate(): #{{{2
    '''This is part of Voof_TreeCreate(), called from Tree.'''

    VOOF.buffers[int(vim.eval('tree'))] = vim.current.buffer

    body = int(vim.eval('a:body'))
    nodes = VOOF.nodes[body]
    Body = VOOF.buffers[body]
    # current Body lnum
    blnr = int(vim.eval('g:voof_bodies[a:body].blnr'))

    ### compute snLn

    # look for headline with .= after level number
    snLn = 0
    ln = 2
    for bln in nodes[1:]:
        line = Body[bln-1]
        end = FOLD_MARKER.search(line).end()
        if end==len(line):
            ln+=1
            continue
        elif line[end] == '=':
            snLn = ln
            break
        ln+=1

    if snLn:
        vim.command('let g:voof_bodies[%s].snLn=%s' %(body, snLn))
        VOOF.snLns[body] = snLn
        # set blnShow if it's different from current Body node
        # TODO: really check for current Body node?
        if len(nodes)>2 and (blnr==1 or blnr<nodes[1]):
            vim.command('let blnShow=%s' %nodes[snLn-1])
    else:
        # no Body headline is marked with =
        # select current Body node
        computeSnLn(body, blnr)

def voofOutline(lines): #{{{2
    '''Return (headlines, nodes, levels) for list of lines.'''
    headlines, nodes, levels = [], [], []
    lnum=0
    for line in lines:
        lnum+=1
        match = FOLD_MARKER.search(line)
        if not match:
            continue
        level = int(match.group(1))
        checkbox = match.group(2) or ' '
        # Strip the fold marker and possible line comment chars before it.
        line = line[:match.start()].strip().rstrip('"#/% \t')
        # Strip headline fillchars. They are useful in Body, but not in Tree.
        # Consider: strip headline fillchars after line comment chars.
        line = line.strip('-=~').strip()
        line = ' %s%s%s%s' %(checkbox, '. '*(level-1), '|', line)
        headlines.append(line)
        nodes.append(lnum)
        levels.append(level)
    return (headlines, nodes, levels)

def treeUpdate(body, draw_tree=True): #{{{2
    '''Construct outline for Body body.
    Compare it to the current outline.
    Draw it in the current buffer (Tree) if different.'''

    ##### Construct outline #####
    lines = VOOF.buffers[body][:]
    headlines, nodes, levels  = voofOutline(lines)
    headlines[0:0], nodes[0:0], levels[0:0] = [VOOF.names[body]], [1], [1]
    VOOF.nodes[body], VOOF.levels[body] = nodes, levels

    ##### Add the = mark #####
    snLn = VOOF.snLns[body]
    size = len(VOOF.nodes[body])
    # snLn got larger than the number of nodes because some nodes were
    # deleted while editing the Body
    if snLn > size:
        snLn = size
        vim.command('let g:voof_bodies[%s].snLn=%s' %(body, size))
        VOOF.snLns[body] = size
    headlines[snLn-1] = '=%s' %headlines[snLn-1][1:]

    if not draw_tree: return

    ##### Compare headlines, draw as needed ######
    # Drawing all buffer lines only when needed is an optimization
    # for large outlines, e.g. >1000 headlines. Drawing all lines is the
    # bottleneck. Scanning and comparing is fast.

    headlines_ = vim.current.buffer[:]
    if not len(headlines_)==len(headlines):
        vim.current.buffer[:] = headlines
        return

    # This causes complete redraw after editing a single headline.
    #if not headlines_==headlines:
        #vim.current.buffer[:] = headlines

    # If only one line is modified, draw that line only. This ensures that
    # editing (and inserting) a single headline in a large outline is fast.
    # If more than one line is modified, draw all lines from first changed line
    # to the end of buffer.
    draw_one = False
    draw_many = False
    idx=0
    for h in headlines:
        if not h==headlines_[idx]:
            if draw_one==False:
                draw_one = True
                diff_idx = idx
            else:
                draw_one = False
                draw_many = True
                break
        idx+=1
    if draw_many:
        vim.current.buffer[diff_idx:] = headlines[diff_idx:]
    elif draw_one:
        vim.current.buffer[diff_idx] = headlines[diff_idx]


def computeSnLn(body, blnr): #{{{2
    '''Compute Tree lnum for node at line blnr in Body body.
    Assign Vim and Python snLn vars.'''

    # snLn should be 1 if blnr is before the first node, top of Body

    nodes = VOOF.nodes[body]
    treeLn=1
    for lnr in nodes:
        if lnr > blnr:
            snLn = treeLn-1
            break
        treeLn+=1
    snLn = treeLn-1
    vim.command('let g:voof_bodies[%s].snLn=%s' %(body, snLn))
    VOOF.snLns[body] = snLn


def voofVerify(body): #{{{2
    '''Verify Tree and VOOF data.'''
    tree = int(vim.eval('g:voof_bodies[%s].tree' %body))
    headlines_ = VOOF.buffers[tree][:]

    bodylines = VOOF.buffers[body][:]
    headlines, nodes, levels  = voofOutline(bodylines)
    headlines[0:0], nodes[0:0], levels[0:0] = [VOOF.names[body]], [1], [1]
    snLn = VOOF.snLns[body]
    headlines[snLn-1] = '=%s' %headlines[snLn-1][1:]

    if not headlines_ == headlines:
        print 'DIFFERENT headlines'
    if not VOOF.nodes[body] == nodes:
        print 'DIFFERENT nodes'
    if not VOOF.levels[body] == levels:
        print 'DIFFERENT levels'


#=============================================================================
#---Outline Operations-------{{{1
# oopOp() functions are called by Voof_Oop Vim functions.
# They use local Vim vars set by the caller.
# They are always called from a Tree.
# They can set lines in Tree and Body.

def nodeChildIdx(body, lnum): #{{{2
    '''Number of children for node at Tree line lnum.'''
    levels = VOOF.levels[body]
    if lnum==1: return 0
    levels.append(-1)
    level = levels[lnum-1]
    idx = 0
    for lev in levels[lnum:]:
        if lev<=level:
            levels.pop()
            return idx
        idx+=1

def oopSelEnd(): #{{{2
    '''This is part of  Voof_Oop() checks.
    Selection in Tree starts at line ln1 and ends at line ln2.
    Selection can have many root nodes: nodes with the same level as ln1 node.
    Return lnum of last node in the last root node's tree.
    Return 0 if selection is invalid.'''
    body, ln1, ln2 = int(vim.eval('body')), int(vim.eval('ln1')), int(vim.eval('ln2'))
    levels = VOOF.levels[body]
    if ln1==1: return 0
    # this takes care of various selection-includes-last-node problems
    levels.append(-1)
    rootLevel = levels[ln1-1]
    ln = ln1
    for lev in levels[ln1-1:]:
        # invalid selection: there is node with level higher than that of root nodes
        if ln<=ln2 and lev<rootLevel:
            levels.pop()
            return 0
        # end node of tree of the last root node
        elif ln>ln2 and lev<=rootLevel:
            levels.pop()
            return ln-1
        ln+=1

def changeLevTreeHead(h, delta): #{{{2
    '''Increase of decrese level of Tree headline by delta:
    insert or delete  delta*". "  string.'''
    if delta>0:
        h = '%s%s%s' %(h[:2], '. '*delta, h[2:])
    elif delta<0:
        h = '%s%s' %(h[:2], h[2-2*delta:])
    return h

def changeLevBodyHead(h, delta): #{{{2
    '''Increase of decrese level number of Body headline by delta.'''
    if delta==0: return h
    m = FOLD_MARKER.search(h)
    level = int(m.group(1))
    h = '%s%s%s' %(h[:m.start(1)], level+delta, h[m.end(1):])
    return h

def setClipboard(s): #{{{2
    '''Set Vim's + register (system clipboard) to string s.'''

    if not s: return
    # use '%s' for Vim string: all we need to do is double ' quotes
    s = s.replace("'", "''")
    #s = s.encode('utf8')
    vim.command("let @+='%s'" %s)

def oopInsert(as_child=False): #{{{2
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln, ln_status = int(vim.eval('ln')), vim.eval('ln_status')

    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    levels = VOOF.levels[body]

    # Compute where and to insert and at what level.
    # Insert new headline after node at ln.
    # If node is folded, insert after the end of node's tree.
    # default level
    level = levels[ln-1]
    # after first Tree line
    if ln==1: level=1
    # as_child always inserts as child after current node, even when it's folded
    elif as_child: level+=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif level < levels[ln]:
        # folded: insert after current node's tree, same level
        if ln_status=='folded':
            ln += nodeChildIdx(body,ln)
        # not folded, insert as child
        else:
            level+=1

    # remove = mark before modifying Tree
    snLn = VOOF.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    # insert headline in Tree and Body
    # bLnum is new headline ln in Body
    treeLine = '= %s%sNewHeadline' %('. '*(level-1), '|')
    bodyLine = '---NewHeadline--- {{{%s' %(level)    #}}}
    if ln==len(Tree[:]):
        Tree.append(treeLine)
        bLnum = len(Body[:])
        Body.append([bodyLine, ''])
    else:
        Tree[ln:ln] = [treeLine]
        bLnum = VOOF.nodes[body][ln]-1
        Body[bLnum:bLnum] = [bodyLine, '']

    vim.command('let bLnum=%s' %(bLnum+1))

    # write = mark and set snLn to new headline
    Tree[ln] = '=' + Tree[ln][1:]
    VOOF.snLns[body] = ln+1
    vim.command('let g:voof_bodies[%s].snLn=%s' %(body, ln+1))


def oopPaste(): #{{{2
    bText = vim.eval('@+')
    if not bText:
        vim.command('let l:invalid_clipboard=1')
        print 'VOOF: clipboard is empty'
        return
    bLines = bText.split('\n') # Body lines to paste
    pHeads, pNodes, pLevels = voofOutline(bLines)
    ### verify that clipboard is a valid Voof text
    if pNodes==[] or pNodes[0]!=1:
        vim.command('let l:invalid_clipboard=1')
        print 'VOOF: INVALID CLIPBOARD (no marker on first line)'
        return
    lev_ = pLevels[0]
    for lev in pLevels:
        # there is node with level higher than that of root nodes
        if lev < pLevels[0]:
            vim.command('let l:invalid_clipboard=1')
            print 'VOOF: INVALID CLIPBOARD (root level error)'
            return
        elif lev-lev_ > 1:
            vim.command('let l:invalid_clipboard=1')
            print 'VOOF: INVALID CLIPBOARD (level error)'
            return
        lev_ = lev

    ### local vars
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln, ln_status = int(vim.eval('ln')), vim.eval('ln_status')

    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    levels, nodes = VOOF.levels[body], VOOF.nodes[body]

    ### compute where and to insert and at what level
    # insert nodes after node at ln at level level
    # if node is folded, insert after the end of node's tree
    level = levels[ln-1] # default level
    # after first Tree line
    if ln==1: level=1
    # after last Tree line, same level
    elif ln==len(levels): pass
    # node has children, it can be folded
    elif level < levels[ln]:
        # folded: insert after current node's tree, same level
        if ln_status=='folded':
            ln += nodeChildIdx(body,ln)
        # not folded, insert as child
        else:
            level+=1

    ### adjust levels of nodes being inserted
    levDelta = level - pLevels[0]
    if levDelta:
        pHeads = [changeLevTreeHead(h, levDelta) for h in pHeads]
        pLevels = [(lev+levDelta) for lev in pLevels]
        for bl in pNodes:
            bLines[bl-1] = changeLevBodyHead(bLines[bl-1], levDelta)

    # remove = mark before modifying Tree
    snLn = VOOF.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### insert headlines in Tree; levels in levels
    Tree[ln:ln] = pHeads
    levels[ln:ln] = pLevels

    ### insert body lines in Body
    if ln==len(nodes):
        bln = len(Body[:])
    else:
        bln = nodes[ln]-1
    Body[bln:bln] = bLines
    vim.command('let blnShow=%s' %(bln+1))

    ### start and end lnums of inserted region
    ln1 = ln+1
    ln2 = ln+len(pNodes)
    vim.command('let l:ln1=%s' %ln1)
    vim.command('let l:ln2=%s' %ln2)
    # set snLn to first headline of inserted nodes
    Tree[ln1-1] = '=' + Tree[ln1-1][1:]
    VOOF.snLns[body] = ln1

    ### update nodes
    # increment nodes being pasted
    idx = 0
    for n in pNodes:
        pNodes[idx]+=bln
        idx+=1
    # increment nodes after pasted region
    delta = len(bLines)
    idx = ln
    for n in nodes[ln:]:
        nodes[idx]+=delta
        idx+=1
    # insert pNodes after ln
    nodes[ln:ln] = pNodes

def oopUp(): #{{{2
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    lnUp1, lnUp2 = int(vim.eval('lnUp1')), int(vim.eval('lnUp2'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

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
    snLn = VOOF.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### tree lines to move; levels in VOOF.levels to move
    tLines = Tree[ln1-1:ln2]
    if levDelta:
        tLines = [changeLevTreeHead(h, levDelta) for h in tLines]
    #print '-------------'
    #print '\n'.join(tLines)
    nLevels = levels[ln1-1:ln2]
    if levDelta:
        nLevels = [(lev+levDelta) for lev in nLevels]

    ### move tree lines; update VOOF.levels
    # cut, then insert
    Tree[ln1-1:ln2] = []
    Tree[lnUp1-1:lnUp1-1] = tLines
    levels[ln1-1:ln2] = []
    levels[lnUp1-1:lnUp1-1] = nLevels

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VOOF.snLns[body] = lnUp1

    ### body lines to move
    bln1 = nodes[ln1-1]
    if ln2==len(nodes):
        bln2 = len(Body[:])
    else:
        bln2 = nodes[ln2]-1
    bLines = Body[bln1-1:bln2]
    if levDelta:
        for bl in nodes[ln1-1:ln2]:
            bLines[bl-bln1] = changeLevBodyHead(bLines[bl-bln1], levDelta)
    #print '-------------'
    #print '\n'.join(bLines)
    #print '-------------'

    ### move body lines: cut, then insert
    blnUp1 = nodes[lnUp1-1] # insert before this line
    Body[bln1-1:bln2] = []
    Body[blnUp1-1:blnUp1-1] = bLines

    ###update nodes
    # increment lnums in the range before which the move is made
    delta = bln2-bln1+1
    idx = lnUp1-1
    for n in nodes[lnUp1-1:ln1-1]:
        nodes[idx]+=delta
        idx+=1
    # decrement lnums in the range which is being moved
    delta = bln1-blnUp1
    idx = ln1-1
    for n in nodes[ln1-1:ln2]:
        nodes[idx]-=delta
        idx+=1
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
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    lnDn1, lnDn1_status = int(vim.eval('lnDn1')), vim.eval('lnDn1_status')
    # note: lnDn1 == ln2+1
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

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
            lnIns += nodeChildIdx(body,lnDn1)
        else:
            levNew+=1
    levDelta = levNew-levOld

    ### remove snLn mark before doing anything with Tree lines
    snLn = VOOF.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### tree lines to move; levels in VOOF.levels to move
    tLines = Tree[ln1-1:ln2]
    if levDelta:
        tLines = [changeLevTreeHead(h, levDelta) for h in tLines]
    nLevels = VOOF.levels[body][ln1-1:ln2]
    if levDelta:
        nLevels = [(lev+levDelta) for lev in nLevels]

    ### move tree lines; update VOOF.levels
    # insert, then cut
    Tree[lnIns:lnIns] = tLines
    Tree[ln1-1:ln2] = []
    levels[lnIns:lnIns] = nLevels
    levels[ln1-1:ln2] = []

    ### compute and add snLn mark
    snLn = lnIns+1-(ln2-ln1+1)
    Tree[snLn-1] = '=' + Tree[snLn-1][1:]
    VOOF.snLns[body] = snLn
    vim.command('let snLn=%s' %snLn)

    ### body lines to move
    bln1 = nodes[ln1-1]
    bln2 = nodes[ln2]-1
    bLines = Body[bln1-1:bln2]
    if levDelta:
        for bl in nodes[ln1-1:ln2]:
            bLines[bl-bln1] = changeLevBodyHead(bLines[bl-bln1], levDelta)

    ### move body lines: insert, then cut
    if lnIns==len(nodes): # insert after the end of file
        blnIns = len(Body)
    else:
        blnIns = nodes[lnIns]-1 # insert after this line
    Body[blnIns:blnIns] = bLines
    Body[bln1-1:bln2] = []

    ###update nodes
    # increment lnums in the range which is being moved
    delta = blnIns-bln2
    idx = ln1-1
    for n in nodes[ln1-1:ln2]:
        nodes[idx]+=delta
        idx+=1
    # decrement lnums in the range after which the move is made
    delta = bln2-bln1+1
    idx = ln2
    for n in nodes[ln2:lnIns]:
        nodes[idx]-=delta
        idx+=1
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
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

    ### Move right means increment level by 1 for all nodes in the range.

    # can't move right if ln1 node is child of previous node
    if levels[ln1-1] == levels[ln1-2]+1:
        vim.command('let cannot_move_right=1')
        return

    ### change levels of Tree lines, VOOF.levels
    tLines = Tree[ln1-1:ln2]
    tLines = [changeLevTreeHead(h, 1) for h in tLines]
    nLevels = VOOF.levels[body][ln1-1:ln2]
    nLevels = [(lev+1) for lev in nLevels]
    Tree[ln1-1:ln2] = tLines
    levels[ln1-1:ln2] = nLevels

    ### change level numbers in Body headlines
    for bln in nodes[ln1-1:ln2]:
        bLine = Body[bln-1]
        Body[bln-1] = changeLevBodyHead(bLine, 1)

    ### set snLn to ln1
    snLn = VOOF.snLns[body]
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VOOF.snLns[body] = snLn

    # lnum of Body node to show
    blnShow = nodes[snLn-1]
    vim.command('let blnShow=%s' %blnShow)


def oopLeft(): #{{{2
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

    ### Move left means decrement level by 1 for all nodes in the range.

    # can't move left if at top level 1
    if levels[ln1-1]==1:
        vim.command('let cannot_move_left=1')
        return
    # can't move left if the range is not at the end of tree
    elif ln2!=len(levels) and levels[ln2]==levels[ln1-1]:
        vim.command('let cannot_move_left=1')
        return

    ### change levels of Tree lines, VOOF.levels
    tLines = Tree[ln1-1:ln2]
    tLines = [changeLevTreeHead(h, -1) for h in tLines]
    nLevels = VOOF.levels[body][ln1-1:ln2]
    nLevels = [(lev-1) for lev in nLevels]
    Tree[ln1-1:ln2] = tLines
    levels[ln1-1:ln2] = nLevels

    ### change level numbers in Body headlines
    for bln in nodes[ln1-1:ln2]:
        bLine = Body[bln-1]
        Body[bln-1] = changeLevBodyHead(bLine, -1)

    ### set snLn to ln1
    snLn = VOOF.snLns[body]
    if not snLn==ln1:
        Tree[snLn-1] = ' ' + Tree[snLn-1][1:]
        snLn = ln1
        Tree[snLn-1] = '=' + Tree[snLn-1][1:]
        VOOF.snLns[body] = snLn

    # lnum of Body node to show
    blnShow = nodes[snLn-1]
    vim.command('let blnShow=%s' %blnShow)


def oopCopy(): #{{{2
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

    # body lines to copy
    bln1 = nodes[ln1-1]
    if ln2==len(nodes):
        bln2 = len(Body[:])
    else:
        bln2 = nodes[ln2]-1
    bLines = Body[bln1-1:bln2]

    setClipboard('\n'.join(bLines))

def oopCut(): #{{{2
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    lnUp1 = int(vim.eval('lnUp1'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

    ### remove snLn mark before doing anything with Tree lines
    snLn = VOOF.snLns[body]
    Tree[snLn-1] = ' ' + Tree[snLn-1][1:]

    ### delet tree lines, levels
    Tree[ln1-1:ln2] = []
    levels[ln1-1:ln2] = []

    ### add snLn mark
    Tree[lnUp1-1] = '=' + Tree[lnUp1-1][1:]
    VOOF.snLns[body] = lnUp1

    ### copy and delete body lines
    bln1 = nodes[ln1-1]
    if ln2==len(nodes):
        bln2 = len(Body[:])
    else:
        bln2 = nodes[ln2]-1
    bLines = Body[bln1-1:bln2]

    setClipboard('\n'.join(bLines))
    Body[bln1-1:bln2] = []

    ###update nodes
    # decrement lnums after deleted range
    delta = bln2-bln1+1
    idx = ln2
    for n in nodes[ln2:]:
        nodes[idx]-=delta
        idx+=1
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
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

    for idx in range(ln1-1,ln2):
        # mark Tree line
        line = Tree[idx]
        if line[1]!='x':
            Tree[idx] = '%sx%s' %(line[0], line[2:])
            # mark Body line
            bln = nodes[idx]
            line = Body[bln-1]
            end = FOLD_MARKER.search(line).end(1)
            Body[bln-1] = '%sx%s' %(line[:end], line[end:])

def oopUnmark(): # {{{2
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln1, ln2 = int(vim.eval('ln1')), int(vim.eval('ln2'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

    for idx in range(ln1-1,ln2):
        # unmark Tree line
        line = Tree[idx]
        if line[1]=='x':
            Tree[idx] = '%s %s' %(line[0], line[2:])
            # unmark Body line
            bln = nodes[idx]
            line = Body[bln-1]
            end = FOLD_MARKER.search(line).end(1)
            Body[bln-1] = '%s%s' %(line[:end], line[end+1:])


def oopMarkSelected(): # {{{2
    tree, body = int(vim.eval('tree')), int(vim.eval('body'))
    ln = int(vim.eval('ln'))
    Tree, Body = VOOF.buffers[tree], VOOF.buffers[body]
    nodes, levels = VOOF.nodes[body], VOOF.levels[body]

    bln_selected = nodes[ln-1]
    # remove = marks from all other Body headlines
    for bln in nodes[1:]:
        if bln==bln_selected: continue
        line = Body[bln-1]
        end = FOLD_MARKER.search(line).end()
        if end==len(line):
            continue
        elif line[end] == '=':
            Body[bln-1] = '%s%s' %(line[:end], line[end+1:])

    # put = mark on current Body headline
    line = Body[bln_selected-1]
    end = FOLD_MARKER.search(line).end()
    if end==len(line):
        Body[bln_selected-1] = '%s=' %line
    elif line[end] != '=':
        Body[bln_selected-1] = '%s=%s' %(line[:end], line[end:])


#---RUN SCRIPT---------------{{{1
#
def runScript(): #{{{2
    '''Run script file.'''
    #sys.path.insert(0, voof_dir)
    try:
        d = {'vim':vim, 'VOOF':VOOF, 'voof':sys.modules[__name__]}
        #d['__name__'] = 'voof'
        execfile(voof_script, d)
        print '---end of Python script---'
    except Exception:
        typ,val,tb = sys.exc_info()
        lines = traceback.format_exception(typ,val,tb)
        print ''.join(lines)
    #del sys.path[0]



#---LOG BUFFER---------------{{{1
#
class LogBufferClass: #{{{2
    '''A file-like object for replacing sys.stdout and sys.stdin with a Vim
    buffer.'''

    def __init__(self): #{{{3
        self.buffer = vim.current.buffer
        self.logbnr = vim.eval('bufnr("")')
        self.buffer[0] = 'Python Log buffer ...'
        self.encoding = vim.eval('&enc')
        self.join = False

    def write(self,s): #{{{3
        '''Append string to buffer, scroll Log windows in all tabs.'''
        # Messages are terminated by sending '\n' (null string? ^@).
        # Thus "print '\n'" sends '\n' twice.
        # The message itself can contain '\n's.
        # One line can be sent in many strings which don't always end with \n.
        # This is certainly true for Python errors and for 'print a, b, ...' .

        # Can't append unicode strings. This produces an error:
        #  :py vim.current.buffer.append(u'test')

        # Can't have '\n' in appended list items, so always use splitlines().
        # A trailing \n is lost after splitlines(), but not for '\n\n' etc.

        if not s: return
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
            if int(vim.eval('bufexists(%s)' %self.logbnr)):
                self.buffer.append('^^^^exception writing to log buffer^^^^')
                self.buffer.append(repr(s))
                self.buffer.append(lines2)
                self.buffer.append('^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^')
            else:
                vim.command('call Voof_ErrorMsg("exception, trying to write to non-existing log buffer:")')
                vim.command('call Voof_ErrorMsg("%s")' %repr(s))
                return

        vim.command('call Voof_LogScroll()')


# modelines {{{1
# vim:fdm=marker:fdl=0
# vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart)


