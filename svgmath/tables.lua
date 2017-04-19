-- Table-related formatting functions.
-- 
-- This module contains functions called from measurers.py to format tables.
local sys = require('sys')
local mathnode = require('mathnode')

getByIndexOrLast = function(lst, idx)
  if idx<#lst then
    return lst[idx]
  else
    return lst[0]
  end
end

CellDescriptor = PYLUA.class() {
  -- Descriptor of a single cell in a table

  __init__ = function(self, content, halign, valign, colspan, rowspan)
    self.content = content
    self.halign = halign
    self.valign = valign
    self.colspan = colspan
    self.rowspan = rowspan
  end
  ;
}


ColumnDescriptor = PYLUA.class() {
  -- Descriptor of a single column in a table

  __init__ = function(self)
    self.auto = true
    self.fit = false
    self.width = 0
    self.spaceAfter = 0
    self.lineAfter = nil
  end
  ;
}


RowDescriptor = PYLUA.class() {
  -- Descriptor of a single row in a table; contains cells

  __init__ = function(self, node, cells, rowalign, columnaligns, busycells)
    self.alignToAxis = rowalign=='axis'
    self.height = 0
    self.depth = 0
    self.spaceAfter = 0
    self.lineAfter = nil
    self.cells = {}
    for _, c in ipairs(cells) do
      while #busycells>#self.cells and busycells[#self.cells]>0 do
        table.insert(self.cells, nil)
      end
      local halign = getByIndexOrLast(columnaligns, #self.cells)
      local valign = rowalign
      local colspan = 1
      local rowspan = 1
      if c.elementName=='mtd' then
        halign = c.attributes['columnalign'] or halign
        valign = c.attributes['rowalign'] or valign
        colspan = node.parseInt(c.attributes['colspan'] or '1')
        rowspan = node.parseInt(c.attributes['rowspan'] or '1')
      end
      while #self.cells>=#node.columns do
        table.insert(node.columns, ColumnDescriptor())
      end
      table.insert(self.cells, CellDescriptor(c, halign, valign, colspan, rowspan))
      for _, i in ipairs(range(1, colspan)) do
        table.insert(self.cells, nil)
      end
      while #self.cells>#node.columns do
        table.insert(node.columns, ColumnDescriptor())
      end
    end
  end
  ;
}


arrangeCells = function(node)
  node.rows = {}
  node.columns = {}
  local busycells = {}
  local table_rowaligns = node.getListProperty('rowalign')
  local table_columnaligns = node.getListProperty('columnalign')
  for _, ch in ipairs(node.children) do
    local rowalign = getByIndexOrLast(table_rowaligns, #node.rows)
    local row_columnaligns = table_columnaligns
    if ch.elementName=='mtr' or ch.elementName=='mlabeledtr' then
      local cells = ch.children
      rowalign = ch.attributes['rowalign'] or rowalign
      if PYLUA.op_in('columnalign', PYLUA.keys(ch.attributes)) then
        local columnaligns = node.getListProperty('columnalign', ch.attributes['columnalign'])
      end
    else
      cells = {ch}
    end
    local row = RowDescriptor(node, cells, rowalign, row_columnaligns, busycells)
    table.insert(node.rows, row)
    busycells = PYLUA.COMPREHENSION()
    while #busycells<#row.cells do
      table.insert(busycells, 0)
    end
    for _, i in ipairs(range(#row.cells)) do
      local cell = row.cells[i]
      if cell == nil then
        goto continue
      end
      if cell.rowspan>1 then
        for _, j in ipairs(range(i, i+cell.colspan)) do
          busycells[j] = cell.rowspan-1
        end
      end
    end
  end
  while math.max(busycells)>0 do
    local rowalign = getByIndexOrLast(table_rowaligns, #node.rows)
    table.insert(node.rows, RowDescriptor(node, {}, rowalign, table_columnaligns, busycells))
    busycells = PYLUA.COMPREHENSION()
  end
end

arrangeLines = function(node)
  local spacings = PYLUA.map(node.parseLength, node.getListProperty('rowspacing'))
  local lines = node.getListProperty('rowlines')
  for _, i in ipairs(range(#node.rows-1)) do
    node.rows[i].spaceAfter = getByIndexOrLast(spacings, i)
    local line = getByIndexOrLast(lines, i)
    if line~='none' then
      node.rows[i].lineAfter = line
      node.rows[i].spaceAfter = node.rows[i].spaceAfter+node.lineWidth
    end
  end
  spacings = PYLUA.map(node.parseSpace, node.getListProperty('columnspacing'))
  lines = node.getListProperty('columnlines')
  for _, i in ipairs(range(#node.columns-1)) do
    node.columns[i].spaceAfter = getByIndexOrLast(spacings, i)
    local line = getByIndexOrLast(lines, i)
    if line~='none' then
      node.columns[i].lineAfter = line
      node.columns[i].spaceAfter = node.columns[i].spaceAfter+node.lineWidth
    end
  end
  node.framespacings = {0, 0}
  node.framelines = {nil, nil}
  spacings = PYLUA.map(node.parseSpace, node.getListProperty('framespacing'))
  lines = node.getListProperty('frame')
  for _, i in ipairs(range(2)) do
    local line = getByIndexOrLast(lines, i)
    if line~='none' then
      node.framespacings[i] = getByIndexOrLast(spacings, i)
      node.framelines[i] = line
    end
  end
end

calculateColumnWidths = function(node)
  local fullwidthattr = node.attributes['width'] or 'auto'
  if fullwidthattr=='auto' then
    local fullwidth = nil
  else
    fullwidth = node.parseLength(fullwidthattr)
    if fullwidth<=0 then
      fullwidth = nil
    end
  end
  local columnwidths = node.getListProperty('columnwidth')
  for _, i in ipairs(range(#node.columns)) do
    local column = node.columns[i]
    local attr = getByIndexOrLast(columnwidths, i)
    if PYLUA.op_in(attr, {'auto', 'fit'}) then
      column.fit = attr=='fit'
    elseif PYLUA.endswith(attr, '%') then
      if fullwidth == nil then
        node.error(string.format('Percents in column widths supported only in tables with explicit width; width of column %d treated as \'auto\'', i+1))
      else
        local value = node.parseFloat(PYLUA.slice(attr, nil, -1))
        if value and value>0 then
          column.width = fullwidth*value/100
          column.auto = false
        end
      end
    else
      column.width = node.parseSpace(attr)
      column.auto = false
    end
  end
  for _, r in ipairs(node.rows) do
    for _, i in ipairs(range(#r.cells)) do
      local c = r.cells[i]
      if c == nil or c.content == nil or c.colspan>1 then
        goto continue
      end
      local column = node.columns[i]
      if column.auto then
        column.width = math.max(column.width, c.content.width)
      end
    end
  end
  while true do
    local adjustedColumns = {}
    local adjustedWidth = 0
    for _, r in ipairs(node.rows) do
      for _, i in ipairs(range(#r.cells)) do
        local c = r.cells[i]
        if c == nil or c.content == nil or c.colspan==1 then
          goto continue
        end
        local columns = PYLUA.slice(node.columns, i, i+c.colspan)
        local autoColumns = PYLUA.COMPREHENSION()
        if #autoColumns==0 then
          goto continue
        end
        local fixedColumns = PYLUA.COMPREHENSION()
        local fixedWidth = sum(PYLUA.COMPREHENSION())
        if #fixedColumns>0 then
          fixedWidth = fixedWidth+sum(PYLUA.COMPREHENSION())
        end
        local autoWidth = sum(PYLUA.COMPREHENSION())
        if c.content.width<=fixedWidth+autoWidth then
          goto continue
        end
        local requiredWidth = c.content.width-fixedWidth
        local unitWidth = requiredWidth/#autoColumns
        while true do
          local oversizedColumns = PYLUA.COMPREHENSION()
          if #oversizedColumns==0 then
            break
          end
          autoColumns = PYLUA.COMPREHENSION()
          if #autoColumns==0 then
            break
          end
          requiredWidth = requiredWidth-sum(PYLUA.COMPREHENSION())
          unitWidth = requiredWidth/#autoColumns
        end
        if #autoColumns==0 then
          goto continue
        end
        if unitWidth>adjustedWidth then
          adjustedWidth = unitWidth
          adjustedColumns = autoColumns
        end
      end
    end
    if #adjustedColumns==0 then
      break
    end
    for _, col in ipairs(adjustedColumns) do
      col.width = adjustedWidth
    end
  end
  if node.getProperty('equalcolumns')=='true' then
    local globalWidth = math.max(PYLUA.COMPREHENSION())
    for _, col in ipairs(node.columns) do
      if col.auto then
        col.width = globalWidth
      end
    end
  end
  if fullwidth ~= nil then
    local delta = fullwidth
    delta = delta-sum(PYLUA.COMPREHENSION())
    delta = delta-sum(PYLUA.COMPREHENSION())
    delta = delta-2*node.framespacings[1]
    if delta~=0 then
      local sizableColumns = PYLUA.COMPREHENSION()
      if #sizableColumns==0 then
        sizableColumns = PYLUA.COMPREHENSION()
      end
      if #sizableColumns==0 then
        node.error('Overconstrained table layout: explicit table width specified, but no column has automatic width; table width attribute ignored')
      else
        delta = delta/#sizableColumns
        for _, col in ipairs(sizableColumns) do
          col.width = col.width+delta
        end
      end
    end
  end
end

calculateRowHeights = function(node)
  local commonAxis = node.axis()
  for _, r in ipairs(node.rows) do
    r.height = 0
    r.depth = 0
    for _, c in ipairs(r.cells) do
      if c == nil or c.content == nil or c.rowspan~=1 then
        goto continue
      end
      local cellAxis = c.content.axis()
      c.vshift = 0
      if c.valign=='baseline' then
        if r.alignToAxis then
          cell.vshift = cell.vshift-commonAxis
        end
        if c.content.alignToAxis then
          c.vshift = c.vshift+cellAxis
        end
      elseif c.valign=='axis' then
        if  not r.alignToAxis then
          c.vshift = c.vshift+commonAxis
        end
        if  not c.content.alignToAxis then
          c.vshift = c.vshift-cellAxis
        end
      else
        c.vshift = (r.height-r.depth-c.content.height+c.content.depth)/2
      end
      r.height = math.max(r.height, c.content.height+c.vshift)
      r.depth = math.max(r.depth, c.content.depth-c.vshift)
    end
  end
  while true do
    local adjustedRows = {}
    local adjustedSize = 0
    for _, i in ipairs(range(#node.rows)) do
      local r = node.rows[i]
      for _, c in ipairs(r.cells) do
        if c == nil or c.content == nil or c.rowspan==1 then
          goto continue
        end
        local rows = PYLUA.slice(node.rows, i, i+c.rowspan)
        local requiredSize = c.content.height+c.content.depth
        requiredSize = requiredSize-sum(PYLUA.COMPREHENSION())
        local fullSize = sum(PYLUA.COMPREHENSION())
        if fullSize>=requiredSize then
          goto continue
        end
        local unitSize = requiredSize/#rows
        while true do
          local oversizedRows = PYLUA.COMPREHENSION()
          if #oversizedRows==0 then
            break
          end
          rows = PYLUA.COMPREHENSION()
          if #rows==0 then
            break
          end
          requiredSize = requiredSize-sum(PYLUA.COMPREHENSION())
          unitSize = requiredSize/#rows
        end
        if #rows==0 then
          goto continue
        end
        if unitSize>adjustedSize then
          adjustedSize = unitSize
          adjustedRows = rows
        end
      end
    end
    if #adjustedRows==0 then
      break
    end
    for _, r in ipairs(adjustedRows) do
      local delta = (adjustedSize-r.height-r.depth)/2
      r.height = r.height+delta
      r.depth = r.depth+delta
    end
  end
  if node.getProperty('equalrows')=='true' then
    local maxvsize = math.max(PYLUA.COMPREHENSION())
    for _, r in ipairs(node.rows) do
      local delta = (maxvsize-r.height-r.depth)/2
      r.height = r.height+delta
      r.depth = r.depth+delta
    end
  end
end

getAlign = function(node)
  local alignattr = PYLUA.strip(node.getProperty('align'))
  if #alignattr==0 then
    alignattr = mathnode.globalDefaults['align']
  end
  local splitalign = PYLUA.split(alignattr)
  local alignType = splitalign[1]
  if #splitalign==1 then
    local alignRow = nil
  else
    alignRow = node.parseInt(splitalign[2])
    if alignrownumber==0 then
      node.error('Alignment row number cannot be zero')
      alignrownumber = nil
    elseif alignrownumber>#node.rows then
      node.error('Alignment row number cannot exceed row count')
      alignrownumber = #node.rows
    elseif alignrownumber<-#node.rows then
      node.error('Negative alignment row number cannot exceed row count')
      alignrownumber = 1
    elseif alignrownumber<0 then
      alignrownumber = #node.rows-alignrownumber+1
    end
  end
  return {alignType, alignRow}
end
