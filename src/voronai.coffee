# ---------------------------------------------------------------------------

###!
Copyright (C) 2010-2013 Raymond Hill: https://github.com/gorhill/Javascript-Voronoi
MIT License: See https://github.com/gorhill/Javascript-Voronoi/LICENSE.md
###

###
Author: Raymond Hill (rhill@raymondhill.net)
Contributor: Jesse Morgan (morgajel@gmail.com)
File: rhill-voronoi-core.js
Version: 0.98
Date: January 21, 2013
Description: This is my personal Javascript implementation of
Steven Fortune's algorithm to compute Voronoi diagrams.

License: See https://github.com/gorhill/Javascript-Voronoi/LICENSE.md
Credits: See https://github.com/gorhill/Javascript-Voronoi/CREDITS.md
History: See https://github.com/gorhill/Javascript-Voronoi/CHANGELOG.md

## Usage:

  var sites = [{x:300,y:300}, {x:100,y:100}, {x:200,y:500}, {x:250,y:450}, {x:600,y:150}];
  // xl, xr means x left, x right
  // yt, yb means y top, y bottom
  var bbox = {xl:0, xr:800, yt:0, yb:600};
  var voronoi = new Voronoi();
  // pass an object which exhibits xl, xr, yt, yb properties. The bounding
  // box will be used to connect unbound edges, and to close open cells
  result = voronoi.compute(sites, bbox);
  // render, further analyze, etc.

Return value:
  An object with the following properties:

  result.vertices = an array of unordered, unique Voronoi.Vertex objects making
    up the Voronoi diagram.
  result.edges = an array of unordered, unique Voronoi.Edge objects making up
    the Voronoi diagram.
  result.cells = an array of Voronoi.Cell object making up the Voronoi diagram.
    A Cell object might have an empty array of halfedges, meaning no Voronoi
    cell could be computed for a particular cell.
  result.execTime = the time it took to compute the Voronoi diagram, in
    milliseconds.

Voronoi.Vertex object:
  x: The x position of the vertex.
  y: The y position of the vertex.

Voronoi.Edge object:
  lSite: the Voronoi site object at the left of this Voronoi.Edge object.
  rSite: the Voronoi site object at the right of this Voronoi.Edge object (can
    be null).
  va: an object with an 'x' and a 'y' property defining the start point
    (relative to the Voronoi site on the left) of this Voronoi.Edge object.
  vb: an object with an 'x' and a 'y' property defining the end point
    (relative to Voronoi site on the left) of this Voronoi.Edge object.

  For edges which are used to close open cells (using the supplied bounding
  box), the rSite property will be null.

Voronoi.Cell object:
  site: the Voronoi site object associated with the Voronoi cell.
  halfedges: an array of Voronoi.Halfedge objects, ordered counterclockwise,
    defining the polygon for this Voronoi cell.

Voronoi.Halfedge object:
  site: the Voronoi site object owning this Voronoi.Halfedge object.
  edge: a reference to the unique Voronoi.Edge object underlying this
    Voronoi.Halfedge object.
  getStartpoint(): a method returning an object with an 'x' and a 'y' property
    for the start point of this halfedge. Keep in mind halfedges are always
    countercockwise.
  getEndpoint(): a method returning an object with an 'x' and a 'y' property
    for the end point of this halfedge. Keep in mind halfedges are always
    countercockwise.

TODO: Identify opportunities for performance improvement.

TODO: Let the user close the Voronoi cells, do not do it automatically. Not only let
      him close the cells, but also allow him to close more than once using a different
      bounding box for the same Voronoi diagram.
###

###global Math ###

# ---------------------------------------------------------------------------

Voronoi = ->
  @vertices = null
  @edges = null
  @cells = null
  @toRecycle = null
  @beachsectionJunkyard = []
  @circleEventJunkyard = []
  @vertexJunkyard = []
  @edgeJunkyard = []
  @cellJunkyard = []
  return

Voronoi::reset = ->
  if !@beachline
    @beachline = new (@RBTree)
  # Move leftover beachsections to the beachsection junkyard.
  if @beachline.root
    beachsection = @beachline.getFirst(@beachline.root)
    while beachsection
      @beachsectionJunkyard.push beachsection
      # mark for reuse
      beachsection = beachsection.rbNext
  @beachline.root = null
  if !@circleEvents
    @circleEvents = new (@RBTree)
  @circleEvents.root = @firstCircleEvent = null
  @vertices = []
  @edges = []
  @cells = []
  return

Voronoi::sqrt = Math.sqrt
Voronoi::abs = Math.abs
Voronoi::ε = Voronoi.ε = 1e-9
Voronoi::invε = Voronoi.invε = 1.0 / Voronoi.ε

Voronoi::equalWithEpsilon = (a, b) ->
  @abs(a - b) < 1e-9

Voronoi::greaterThanWithEpsilon = (a, b) ->
  a - b > 1e-9

Voronoi::greaterThanOrEqualWithEpsilon = (a, b) ->
  b - a < 1e-9

Voronoi::lessThanWithEpsilon = (a, b) ->
  b - a > 1e-9

Voronoi::lessThanOrEqualWithEpsilon = (a, b) ->
  a - b < 1e-9

# ---------------------------------------------------------------------------
# Red-Black tree code (based on C version of "rbtree" by Franck Bui-Huu
# https://github.com/fbuihuu/libtree/blob/master/rb.c

Voronoi::RBTree = ->
  @root = null
  return

Voronoi::RBTree::rbInsertSuccessor = (node, successor) ->
  parent = undefined
  if node
    # >>> rhill 2011-05-27: Performance: cache previous/next nodes
    successor.rbPrevious = node
    successor.rbNext = node.rbNext
    if node.rbNext
      node.rbNext.rbPrevious = successor
    node.rbNext = successor
    # <<<
    if node.rbRight
      # in-place expansion of node.rbRight.getFirst();
      node = node.rbRight
      while node.rbLeft
        node = node.rbLeft
      node.rbLeft = successor
    else
      node.rbRight = successor
    parent = node
  else if @root
    node = @getFirst(@root)
    # >>> Performance: cache previous/next nodes
    successor.rbPrevious = null
    successor.rbNext = node
    node.rbPrevious = successor
    # <<<
    node.rbLeft = successor
    parent = node
  else
    # >>> Performance: cache previous/next nodes
    successor.rbPrevious = successor.rbNext = null
    # <<<
    @root = successor
    parent = null
  successor.rbLeft = successor.rbRight = null
  successor.rbParent = parent
  successor.rbRed = true
  # Fixup the modified tree by recoloring nodes and performing
  # rotations (2 at most) hence the red-black tree properties are
  # preserved.
  grandpa = undefined
  uncle = undefined
  node = successor
  while parent and parent.rbRed
    grandpa = parent.rbParent
    if parent == grandpa.rbLeft
      uncle = grandpa.rbRight
      if uncle and uncle.rbRed
        parent.rbRed = uncle.rbRed = false
        grandpa.rbRed = true
        node = grandpa
      else
        if node == parent.rbRight
          @rbRotateLeft parent
          node = parent
          parent = node.rbParent
        parent.rbRed = false
        grandpa.rbRed = true
        @rbRotateRight grandpa
    else
      uncle = grandpa.rbLeft
      if uncle and uncle.rbRed
        parent.rbRed = uncle.rbRed = false
        grandpa.rbRed = true
        node = grandpa
      else
        if node == parent.rbLeft
          @rbRotateRight parent
          node = parent
          parent = node.rbParent
        parent.rbRed = false
        grandpa.rbRed = true
        @rbRotateLeft grandpa
    parent = node.rbParent
  @root.rbRed = false
  return

Voronoi::RBTree::rbRemoveNode = (node) ->
  # >>> rhill 2011-05-27: Performance: cache previous/next nodes
  if node.rbNext
    node.rbNext.rbPrevious = node.rbPrevious
  if node.rbPrevious
    node.rbPrevious.rbNext = node.rbNext
  node.rbNext = node.rbPrevious = null
  # <<<
  parent = node.rbParent
  left = node.rbLeft
  right = node.rbRight
  next = undefined
  if !left
    next = right
  else if !right
    next = left
  else
    next = @getFirst(right)
  if parent
    if parent.rbLeft == node
      parent.rbLeft = next
    else
      parent.rbRight = next
  else
    @root = next
  # enforce red-black rules
  isRed = undefined
  if left and right
    isRed = next.rbRed
    next.rbRed = node.rbRed
    next.rbLeft = left
    left.rbParent = next
    if next != right
      parent = next.rbParent
      next.rbParent = node.rbParent
      node = next.rbRight
      parent.rbLeft = node
      next.rbRight = right
      right.rbParent = next
    else
      next.rbParent = parent
      parent = next
      node = next.rbRight
  else
    isRed = node.rbRed
    node = next
  # 'node' is now the sole successor's child and 'parent' its
  # new parent (since the successor can have been moved)
  if node
    node.rbParent = parent
  # the 'easy' cases
  if isRed
    return
  if node and node.rbRed
    node.rbRed = false
    return
  # the other cases
  sibling = undefined
  loop
    if node == @root
      break
    if node == parent.rbLeft
      sibling = parent.rbRight
      if sibling.rbRed
        sibling.rbRed = false
        parent.rbRed = true
        @rbRotateLeft parent
        sibling = parent.rbRight
      if sibling.rbLeft and sibling.rbLeft.rbRed or sibling.rbRight and sibling.rbRight.rbRed
        if !sibling.rbRight or !sibling.rbRight.rbRed
          sibling.rbLeft.rbRed = false
          sibling.rbRed = true
          @rbRotateRight sibling
          sibling = parent.rbRight
        sibling.rbRed = parent.rbRed
        parent.rbRed = sibling.rbRight.rbRed = false
        @rbRotateLeft parent
        node = @root
        break
    else
      sibling = parent.rbLeft
      if sibling.rbRed
        sibling.rbRed = false
        parent.rbRed = true
        @rbRotateRight parent
        sibling = parent.rbLeft
      if sibling.rbLeft and sibling.rbLeft.rbRed or sibling.rbRight and sibling.rbRight.rbRed
        if !sibling.rbLeft or !sibling.rbLeft.rbRed
          sibling.rbRight.rbRed = false
          sibling.rbRed = true
          @rbRotateLeft sibling
          sibling = parent.rbLeft
        sibling.rbRed = parent.rbRed
        parent.rbRed = sibling.rbLeft.rbRed = false
        @rbRotateRight parent
        node = @root
        break
    sibling.rbRed = true
    node = parent
    parent = parent.rbParent
    unless !node.rbRed
      break
  if node
    node.rbRed = false
  return

Voronoi::RBTree::rbRotateLeft = (node) ->
  p = node
  q = node.rbRight
  parent = p.rbParent
  if parent
    if parent.rbLeft == p
      parent.rbLeft = q
    else
      parent.rbRight = q
  else
    @root = q
  q.rbParent = parent
  p.rbParent = q
  p.rbRight = q.rbLeft
  if p.rbRight
    p.rbRight.rbParent = p
  q.rbLeft = p
  return

Voronoi::RBTree::rbRotateRight = (node) ->
  p = node
  q = node.rbLeft
  parent = p.rbParent
  if parent
    if parent.rbLeft == p
      parent.rbLeft = q
    else
      parent.rbRight = q
  else
    @root = q
  q.rbParent = parent
  p.rbParent = q
  p.rbLeft = q.rbRight
  if p.rbLeft
    p.rbLeft.rbParent = p
  q.rbRight = p
  return

Voronoi::RBTree::getFirst = (node) ->
  while node.rbLeft
    node = node.rbLeft
  node

Voronoi::RBTree::getLast = (node) ->
  while node.rbRight
    node = node.rbRight
  node

# ---------------------------------------------------------------------------
# Diagram methods

Voronoi::Diagram = (site) ->
  @site = site
  return

# ---------------------------------------------------------------------------
# Cell methods

Voronoi::Cell = (site) ->
  @site = site
  @halfedges = []
  @closeMe = false
  return

Voronoi::Cell::init = (site) ->
  @site = site
  @halfedges = []
  @closeMe = false
  this

Voronoi::createCell = (site) ->
  cell = @cellJunkyard.pop()
  if cell
    return cell.init(site)
  new (@Cell)(site)

Voronoi::Cell::prepareHalfedges = ->
  halfedges = @halfedges
  iHalfedge = halfedges.length
  edge = undefined
  # get rid of unused halfedges
  # rhill 2011-05-27: Keep it simple, no point here in trying
  # to be fancy: dangling edges are a typically a minority.
  while iHalfedge--
    edge = halfedges[iHalfedge].edge
    if !edge.vb or !edge.va
      halfedges.splice iHalfedge, 1
  # rhill 2011-05-26: I tried to use a binary search at insertion
  # time to keep the array sorted on-the-fly (in Cell.addHalfedge()).
  # There was no real benefits in doing so, performance on
  # Firefox 3.6 was improved marginally, while performance on
  # Opera 11 was penalized marginally.
  halfedges.sort (a, b) ->
    b.angle - (a.angle)
  halfedges.length

# Return a list of the neighbor Ids

Voronoi::Cell::getNeighborIds = ->
  neighbors = []
  iHalfedge = @halfedges.length
  edge = undefined
  while iHalfedge--
    edge = @halfedges[iHalfedge].edge
    if edge.lSite != null and edge.lSite.voronoiId != @site.voronoiId
      neighbors.push edge.lSite.voronoiId
    else if edge.rSite != null and edge.rSite.voronoiId != @site.voronoiId
      neighbors.push edge.rSite.voronoiId
  neighbors

# Compute bounding box
#

Voronoi::Cell::getBbox = ->
  halfedges = @halfedges
  iHalfedge = halfedges.length
  xmin = Infinity
  ymin = Infinity
  xmax = -Infinity
  ymax = -Infinity
  v = undefined
  vx = undefined
  vy = undefined
  while iHalfedge--
    v = halfedges[iHalfedge].getStartpoint()
    vx = v.x
    vy = v.y
    if vx < xmin
      xmin = vx
    if vy < ymin
      ymin = vy
    if vx > xmax
      xmax = vx
    if vy > ymax
      ymax = vy
    # we dont need to take into account end point,
    # since each end point matches a start point
  {
    x: xmin
    y: ymin
    width: xmax - xmin
    height: ymax - ymin
  }

# Return whether a point is inside, on, or outside the cell:
#   -1: point is outside the perimeter of the cell
#    0: point is on the perimeter of the cell
#    1: point is inside the perimeter of the cell
#

Voronoi::Cell::pointIntersection = (x, y) ->
  # Check if point in polygon. Since all polygons of a Voronoi
  # diagram are convex, then:
  # http://paulbourke.net/geometry/polygonmesh/
  # Solution 3 (2D):
  #   "If the polygon is convex then one can consider the polygon
  #   "as a 'path' from the first vertex. A point is on the interior
  #   "of this polygons if it is always on the same side of all the
  #   "line segments making up the path. ...
  #   "(y - y0) (x1 - x0) - (x - x0) (y1 - y0)
  #   "if it is less than 0 then P is to the right of the line segment,
  #   "if greater than 0 it is to the left, if equal to 0 then it lies
  #   "on the line segment"
  halfedges = @halfedges
  iHalfedge = halfedges.length
  halfedge = undefined
  p0 = undefined
  p1 = undefined
  r = undefined
  while iHalfedge--
    halfedge = halfedges[iHalfedge]
    p0 = halfedge.getStartpoint()
    p1 = halfedge.getEndpoint()
    r = (y - (p0.y)) * (p1.x - (p0.x)) - ((x - (p0.x)) * (p1.y - (p0.y)))
    if !r
      return 0
    if r > 0
      return -1
  1

# ---------------------------------------------------------------------------
# Edge methods
#

Voronoi::Vertex = (x, y) ->
  @x = x
  @y = y
  return

Voronoi::Edge = (lSite, rSite) ->
  @lSite = lSite
  @rSite = rSite
  @va = @vb = null
  return

Voronoi::Halfedge = (edge, lSite, rSite) ->
  @site = lSite
  @edge = edge
  # 'angle' is a value to be used for properly sorting the
  # halfsegments counterclockwise. By convention, we will
  # use the angle of the line defined by the 'site to the left'
  # to the 'site to the right'.
  # However, border edges have no 'site to the right': thus we
  # use the angle of line perpendicular to the halfsegment (the
  # edge should have both end points defined in such case.)
  if rSite
    @angle = Math.atan2(rSite.y - (lSite.y), rSite.x - (lSite.x))
  else
    va = edge.va
    vb = edge.vb
    # rhill 2011-05-31: used to call getStartpoint()/getEndpoint(),
    # but for performance purpose, these are expanded in place here.
    @angle = if edge.lSite == lSite then Math.atan2(vb.x - (va.x), va.y - (vb.y)) else Math.atan2(va.x - (vb.x), vb.y - (va.y))
  return

Voronoi::createHalfedge = (edge, lSite, rSite) ->
  new (@Halfedge)(edge, lSite, rSite)

Voronoi::Halfedge::getStartpoint = ->
  if @edge.lSite == @site then @edge.va else @edge.vb

Voronoi::Halfedge::getEndpoint = ->
  if @edge.lSite == @site then @edge.vb else @edge.va

# this create and add a vertex to the internal collection

Voronoi::createVertex = (x, y) ->
  v = @vertexJunkyard.pop()
  if !v
    v = new (@Vertex)(x, y)
  else
    v.x = x
    v.y = y
  @vertices.push v
  v

# this create and add an edge to internal collection, and also create
# two halfedges which are added to each site's counterclockwise array
# of halfedges.

Voronoi::createEdge = (lSite, rSite, va, vb) ->
  edge = @edgeJunkyard.pop()
  if !edge
    edge = new (@Edge)(lSite, rSite)
  else
    edge.lSite = lSite
    edge.rSite = rSite
    edge.va = edge.vb = null
  @edges.push edge
  if va
    @setEdgeStartpoint edge, lSite, rSite, va
  if vb
    @setEdgeEndpoint edge, lSite, rSite, vb
  @cells[lSite.voronoiId].halfedges.push @createHalfedge(edge, lSite, rSite)
  @cells[rSite.voronoiId].halfedges.push @createHalfedge(edge, rSite, lSite)
  edge

Voronoi::createBorderEdge = (lSite, va, vb) ->
  edge = @edgeJunkyard.pop()
  if !edge
    edge = new (@Edge)(lSite, null)
  else
    edge.lSite = lSite
    edge.rSite = null
  edge.va = va
  edge.vb = vb
  @edges.push edge
  edge

Voronoi::setEdgeStartpoint = (edge, lSite, rSite, vertex) ->
  if !edge.va and !edge.vb
    edge.va = vertex
    edge.lSite = lSite
    edge.rSite = rSite
  else if edge.lSite == rSite
    edge.vb = vertex
  else
    edge.va = vertex
  return

Voronoi::setEdgeEndpoint = (edge, lSite, rSite, vertex) ->
  @setEdgeStartpoint edge, rSite, lSite, vertex
  return

# ---------------------------------------------------------------------------
# Beachline methods
# rhill 2011-06-07: For some reasons, performance suffers significantly
# when instanciating a literal object instead of an empty ctor

Voronoi::Beachsection = ->

# rhill 2011-06-02: A lot of Beachsection instanciations
# occur during the computation of the Voronoi diagram,
# somewhere between the number of sites and twice the
# number of sites, while the number of Beachsections on the
# beachline at any given time is comparatively low. For this
# reason, we reuse already created Beachsections, in order
# to avoid new memory allocation. This resulted in a measurable
# performance gain.

Voronoi::createBeachsection = (site) ->
  beachsection = @beachsectionJunkyard.pop()
  if !beachsection
    beachsection = new (@Beachsection)
  beachsection.site = site
  beachsection

# calculate the left break point of a particular beach section,
# given a particular sweep line

Voronoi::leftBreakPoint = (arc, directrix) ->
  # http://en.wikipedia.org/wiki/Parabola
  # http://en.wikipedia.org/wiki/Quadratic_equation
  # h1 = x1,
  # k1 = (y1+directrix)/2,
  # h2 = x2,
  # k2 = (y2+directrix)/2,
  # p1 = k1-directrix,
  # a1 = 1/(4*p1),
  # b1 = -h1/(2*p1),
  # c1 = h1*h1/(4*p1)+k1,
  # p2 = k2-directrix,
  # a2 = 1/(4*p2),
  # b2 = -h2/(2*p2),
  # c2 = h2*h2/(4*p2)+k2,
  # x = (-(b2-b1) + Math.sqrt((b2-b1)*(b2-b1) - 4*(a2-a1)*(c2-c1))) / (2*(a2-a1))
  # When x1 become the x-origin:
  # h1 = 0,
  # k1 = (y1+directrix)/2,
  # h2 = x2-x1,
  # k2 = (y2+directrix)/2,
  # p1 = k1-directrix,
  # a1 = 1/(4*p1),
  # b1 = 0,
  # c1 = k1,
  # p2 = k2-directrix,
  # a2 = 1/(4*p2),
  # b2 = -h2/(2*p2),
  # c2 = h2*h2/(4*p2)+k2,
  # x = (-b2 + Math.sqrt(b2*b2 - 4*(a2-a1)*(c2-k1))) / (2*(a2-a1)) + x1
  # change code below at your own risk: care has been taken to
  # reduce errors due to computers' finite arithmetic precision.
  # Maybe can still be improved, will see if any more of this
  # kind of errors pop up again.
  site = arc.site
  rfocx = site.x
  rfocy = site.y
  pby2 = rfocy - directrix
  # parabola in degenerate case where focus is on directrix
  if !pby2
    return rfocx
  lArc = arc.rbPrevious
  if !lArc
    return -Infinity
  site = lArc.site
  lfocx = site.x
  lfocy = site.y
  plby2 = lfocy - directrix
  # parabola in degenerate case where focus is on directrix
  if !plby2
    return lfocx
  hl = lfocx - rfocx
  aby2 = 1 / pby2 - (1 / plby2)
  b = hl / plby2
  if aby2
    return (-b + @sqrt(b * b - (2 * aby2 * (hl * hl / (-2 * plby2) - lfocy + plby2 / 2 + rfocy - (pby2 / 2))))) / aby2 + rfocx
  # both parabolas have same distance to directrix, thus break point is midway
  (rfocx + lfocx) / 2

# calculate the right break point of a particular beach section,
# given a particular directrix

Voronoi::rightBreakPoint = (arc, directrix) ->
  rArc = arc.rbNext
  if rArc
    return @leftBreakPoint(rArc, directrix)
  site = arc.site
  if site.y == directrix then site.x else Infinity

Voronoi::detachBeachsection = (beachsection) ->
  @detachCircleEvent beachsection
  # detach potentially attached circle event
  @beachline.rbRemoveNode beachsection
  # remove from RB-tree
  @beachsectionJunkyard.push beachsection
  # mark for reuse
  return

Voronoi::removeBeachsection = (beachsection) ->
  circle = beachsection.circleEvent
  x = circle.x
  y = circle.ycenter
  vertex = @createVertex(x, y)
  previous = beachsection.rbPrevious
  next = beachsection.rbNext
  disappearingTransitions = [ beachsection ]
  abs_fn = Math.abs
  # remove collapsed beachsection from beachline
  @detachBeachsection beachsection
  # there could be more than one empty arc at the deletion point, this
  # happens when more than two edges are linked by the same vertex,
  # so we will collect all those edges by looking up both sides of
  # the deletion point.
  # by the way, there is *always* a predecessor/successor to any collapsed
  # beach section, it's just impossible to have a collapsing first/last
  # beach sections on the beachline, since they obviously are unconstrained
  # on their left/right side.
  # look left
  lArc = previous
  while lArc.circleEvent and abs_fn(x - (lArc.circleEvent.x)) < 1e-9 and abs_fn(y - (lArc.circleEvent.ycenter)) < 1e-9
    previous = lArc.rbPrevious
    disappearingTransitions.unshift lArc
    @detachBeachsection lArc
    # mark for reuse
    lArc = previous
  # even though it is not disappearing, I will also add the beach section
  # immediately to the left of the left-most collapsed beach section, for
  # convenience, since we need to refer to it later as this beach section
  # is the 'left' site of an edge for which a start point is set.
  disappearingTransitions.unshift lArc
  @detachCircleEvent lArc
  # look right
  rArc = next
  while rArc.circleEvent and abs_fn(x - (rArc.circleEvent.x)) < 1e-9 and abs_fn(y - (rArc.circleEvent.ycenter)) < 1e-9
    next = rArc.rbNext
    disappearingTransitions.push rArc
    @detachBeachsection rArc
    # mark for reuse
    rArc = next
  # we also have to add the beach section immediately to the right of the
  # right-most collapsed beach section, since there is also a disappearing
  # transition representing an edge's start point on its left.
  disappearingTransitions.push rArc
  @detachCircleEvent rArc
  # walk through all the disappearing transitions between beach sections and
  # set the start point of their (implied) edge.
  nArcs = disappearingTransitions.length
  iArc = undefined
  iArc = 1
  while iArc < nArcs
    rArc = disappearingTransitions[iArc]
    lArc = disappearingTransitions[iArc - 1]
    @setEdgeStartpoint rArc.edge, lArc.site, rArc.site, vertex
    iArc++
  # create a new edge as we have now a new transition between
  # two beach sections which were previously not adjacent.
  # since this edge appears as a new vertex is defined, the vertex
  # actually define an end point of the edge (relative to the site
  # on the left)
  lArc = disappearingTransitions[0]
  rArc = disappearingTransitions[nArcs - 1]
  rArc.edge = @createEdge(lArc.site, rArc.site, undefined, vertex)
  # create circle events if any for beach sections left in the beachline
  # adjacent to collapsed sections
  @attachCircleEvent lArc
  @attachCircleEvent rArc
  return

Voronoi::addBeachsection = (site) ->
  x = site.x
  directrix = site.y
  # find the left and right beach sections which will surround the newly
  # created beach section.
  # rhill 2011-06-01: This loop is one of the most often executed,
  # hence we expand in-place the comparison-against-epsilon calls.
  lArc = undefined
  rArc = undefined
  dxl = undefined
  dxr = undefined
  node = @beachline.root
  while node
    dxl = @leftBreakPoint(node, directrix) - x
    # x lessThanWithEpsilon xl => falls somewhere before the left edge of the beachsection
    if dxl > 1e-9
      # this case should never happen
      # if (!node.rbLeft) {
      #    rArc = node.rbLeft;
      #    break;
      #    }
      node = node.rbLeft
    else
      dxr = x - @rightBreakPoint(node, directrix)
      # x greaterThanWithEpsilon xr => falls somewhere after the right edge of the beachsection
      if dxr > 1e-9
        if !node.rbRight
          lArc = node
          break
        node = node.rbRight
      else
        # x equalWithEpsilon xl => falls exactly on the left edge of the beachsection
        if dxl > -1e-9
          lArc = node.rbPrevious
          rArc = node
        else if dxr > -1e-9
          lArc = node
          rArc = node.rbNext
        else
          lArc = rArc = node
        break
  # at this point, keep in mind that lArc and/or rArc could be
  # undefined or null.
  # create a new beach section object for the site and add it to RB-tree
  newArc = @createBeachsection(site)
  @beachline.rbInsertSuccessor lArc, newArc
  # cases:
  #
  # [null,null]
  # least likely case: new beach section is the first beach section on the
  # beachline.
  # This case means:
  #   no new transition appears
  #   no collapsing beach section
  #   new beachsection become root of the RB-tree
  if !lArc and !rArc
    return
  # [lArc,rArc] where lArc == rArc
  # most likely case: new beach section split an existing beach
  # section.
  # This case means:
  #   one new transition appears
  #   the left and right beach section might be collapsing as a result
  #   two new nodes added to the RB-tree
  if lArc == rArc
    # invalidate circle event of split beach section
    @detachCircleEvent lArc
    # split the beach section into two separate beach sections
    rArc = @createBeachsection(lArc.site)
    @beachline.rbInsertSuccessor newArc, rArc
    # since we have a new transition between two beach sections,
    # a new edge is born
    newArc.edge = rArc.edge = @createEdge(lArc.site, newArc.site)
    # check whether the left and right beach sections are collapsing
    # and if so create circle events, to be notified when the point of
    # collapse is reached.
    @attachCircleEvent lArc
    @attachCircleEvent rArc
    return
  # [lArc,null]
  # even less likely case: new beach section is the *last* beach section
  # on the beachline -- this can happen *only* if *all* the previous beach
  # sections currently on the beachline share the same y value as
  # the new beach section.
  # This case means:
  #   one new transition appears
  #   no collapsing beach section as a result
  #   new beach section become right-most node of the RB-tree
  if lArc and !rArc
    newArc.edge = @createEdge(lArc.site, newArc.site)
    return
  # [null,rArc]
  # impossible case: because sites are strictly processed from top to bottom,
  # and left to right, which guarantees that there will always be a beach section
  # on the left -- except of course when there are no beach section at all on
  # the beach line, which case was handled above.
  # rhill 2011-06-02: No point testing in non-debug version
  #if (!lArc && rArc) {
  #    throw "Voronoi.addBeachsection(): What is this I don't even";
  #    }
  # [lArc,rArc] where lArc != rArc
  # somewhat less likely case: new beach section falls *exactly* in between two
  # existing beach sections
  # This case means:
  #   one transition disappears
  #   two new transitions appear
  #   the left and right beach section might be collapsing as a result
  #   only one new node added to the RB-tree
  if lArc != rArc
    # invalidate circle events of left and right sites
    @detachCircleEvent lArc
    @detachCircleEvent rArc
    # an existing transition disappears, meaning a vertex is defined at
    # the disappearance point.
    # since the disappearance is caused by the new beachsection, the
    # vertex is at the center of the circumscribed circle of the left,
    # new and right beachsections.
    # http://mathforum.org/library/drmath/view/55002.html
    # Except that I bring the origin at A to simplify
    # calculation
    lSite = lArc.site
    ax = lSite.x
    ay = lSite.y
    bx = site.x - ax
    _by = site.y - ay
    rSite = rArc.site
    cx = rSite.x - ax
    cy = rSite.y - ay
    d = 2 * (bx * cy - (_by * cx))
    hb = bx * bx + _by * _by
    hc = cx * cx + cy * cy
    vertex = @createVertex((cy * hb - (_by * hc)) / d + ax, (bx * hc - (cx * hb)) / d + ay)
    # one transition disappear
    @setEdgeStartpoint rArc.edge, lSite, rSite, vertex
    # two new transitions appear at the new vertex location
    newArc.edge = @createEdge(lSite, site, undefined, vertex)
    rArc.edge = @createEdge(site, rSite, undefined, vertex)
    # check whether the left and right beach sections are collapsing
    # and if so create circle events, to handle the point of collapse.
    @attachCircleEvent lArc
    @attachCircleEvent rArc
    return
  return

# ---------------------------------------------------------------------------
# Circle event methods
# rhill 2011-06-07: For some reasons, performance suffers significantly
# when instanciating a literal object instead of an empty ctor

Voronoi::CircleEvent = ->
  # rhill 2013-10-12: it helps to state exactly what we are at ctor time.
  @arc = null
  @rbLeft = null
  @rbNext = null
  @rbParent = null
  @rbPrevious = null
  @rbRed = false
  @rbRight = null
  @site = null
  @x = @y = @ycenter = 0
  return

Voronoi::attachCircleEvent = (arc) ->
  lArc = arc.rbPrevious
  rArc = arc.rbNext
  if !lArc or !rArc
    return
  # does that ever happen?
  lSite = lArc.site
  cSite = arc.site
  rSite = rArc.site
  # If site of left beachsection is same as site of
  # right beachsection, there can't be convergence
  if lSite == rSite
    return
  # Find the circumscribed circle for the three sites associated
  # with the beachsection triplet.
  # rhill 2011-05-26: It is more efficient to calculate in-place
  # rather than getting the resulting circumscribed circle from an
  # object returned by calling Voronoi.circumcircle()
  # http://mathforum.org/library/drmath/view/55002.html
  # Except that I bring the origin at cSite to simplify calculations.
  # The bottom-most part of the circumcircle is our Fortune 'circle
  # event', and its center is a vertex potentially part of the final
  # Voronoi diagram.
  bx = cSite.x
  _by = cSite.y
  ax = lSite.x - bx
  ay = lSite.y - _by
  cx = rSite.x - bx
  cy = rSite.y - _by
  # If points l->c->r are clockwise, then center beach section does not
  # collapse, hence it can't end up as a vertex (we reuse 'd' here, which
  # sign is reverse of the orientation, hence we reverse the test.
  # http://en.wikipedia.org/wiki/Curve_orientation#Orientation_of_a_simple_polygon
  # rhill 2011-05-21: Nasty finite precision error which caused circumcircle() to
  # return infinites: 1e-12 seems to fix the problem.
  d = 2 * (ax * cy - (ay * cx))
  if d >= -2e-12
    return
  ha = ax * ax + ay * ay
  hc = cx * cx + cy * cy
  x = (cy * ha - (ay * hc)) / d
  y = (ax * hc - (cx * ha)) / d
  ycenter = y + _by
  # Important: ybottom should always be under or at sweep, so no need
  # to waste CPU cycles by checking
  # recycle circle event object if possible
  circleEvent = @circleEventJunkyard.pop()
  if !circleEvent
    circleEvent = new (@CircleEvent)
  circleEvent.arc = arc
  circleEvent.site = cSite
  circleEvent.x = x + bx
  circleEvent.y = ycenter + @sqrt(x * x + y * y)
  # y bottom
  circleEvent.ycenter = ycenter
  arc.circleEvent = circleEvent
  # find insertion point in RB-tree: circle events are ordered from
  # smallest to largest
  predecessor = null
  node = @circleEvents.root
  while node
    if circleEvent.y < node.y or circleEvent.y == node.y and circleEvent.x <= node.x
      if node.rbLeft
        node = node.rbLeft
      else
        predecessor = node.rbPrevious
        break
    else
      if node.rbRight
        node = node.rbRight
      else
        predecessor = node
        break
  @circleEvents.rbInsertSuccessor predecessor, circleEvent
  if !predecessor
    @firstCircleEvent = circleEvent
  return

Voronoi::detachCircleEvent = (arc) ->
  circleEvent = arc.circleEvent
  if circleEvent
    if !circleEvent.rbPrevious
      @firstCircleEvent = circleEvent.rbNext
    @circleEvents.rbRemoveNode circleEvent
    # remove from RB-tree
    @circleEventJunkyard.push circleEvent
    arc.circleEvent = null
  return

# ---------------------------------------------------------------------------
# Diagram completion methods
# connect dangling edges (not if a cursory test tells us
# it is not going to be visible.
# return value:
#   false: the dangling endpoint couldn't be connected
#   true: the dangling endpoint could be connected

Voronoi::connectEdge = (edge, bbox) ->
  # skip if end point already connected
  vb = edge.vb
  if ! !vb
    return true
  # make local copy for performance purpose
  va = edge.va
  xl = bbox.xl
  xr = bbox.xr
  yt = bbox.yt
  yb = bbox.yb
  lSite = edge.lSite
  rSite = edge.rSite
  lx = lSite.x
  ly = lSite.y
  rx = rSite.x
  ry = rSite.y
  fx = (lx + rx) / 2
  fy = (ly + ry) / 2
  fm = undefined
  fb = undefined
  # if we reach here, this means cells which use this edge will need
  # to be closed, whether because the edge was removed, or because it
  # was connected to the bounding box.
  @cells[lSite.voronoiId].closeMe = true
  @cells[rSite.voronoiId].closeMe = true
  # get the line equation of the bisector if line is not vertical
  if ry != ly
    fm = (lx - rx) / (ry - ly)
    fb = fy - (fm * fx)
  # remember, direction of line (relative to left site):
  # upward: left.x < right.x
  # downward: left.x > right.x
  # horizontal: left.x == right.x
  # upward: left.x < right.x
  # rightward: left.y < right.y
  # leftward: left.y > right.y
  # vertical: left.y == right.y
  # depending on the direction, find the best side of the
  # bounding box to use to determine a reasonable start point
  # rhill 2013-12-02:
  # While at it, since we have the values which define the line,
  # clip the end of va if it is outside the bbox.
  # https://github.com/gorhill/Javascript-Voronoi/issues/15
  # TODO: Do all the clipping here rather than rely on Liang-Barsky
  # which does not do well sometimes due to loss of arithmetic
  # precision. The code here doesn't degrade if one of the vertex is
  # at a huge distance.
  # special case: vertical line
  if fm == undefined
    # doesn't intersect with viewport
    if fx < xl or fx >= xr
      return false
    # downward
    if lx > rx
      if !va or va.y < yt
        va = @createVertex(fx, yt)
      else if va.y >= yb
        return false
      vb = @createVertex(fx, yb)
    else
      if !va or va.y > yb
        va = @createVertex(fx, yb)
      else if va.y < yt
        return false
      vb = @createVertex(fx, yt)
  else if fm < -1 or fm > 1
    # downward
    if lx > rx
      if !va or va.y < yt
        va = @createVertex((yt - fb) / fm, yt)
      else if va.y >= yb
        return false
      vb = @createVertex((yb - fb) / fm, yb)
    else
      if !va or va.y > yb
        va = @createVertex((yb - fb) / fm, yb)
      else if va.y < yt
        return false
      vb = @createVertex((yt - fb) / fm, yt)
  else
    # rightward
    if ly < ry
      if !va or va.x < xl
        va = @createVertex(xl, fm * xl + fb)
      else if va.x >= xr
        return false
      vb = @createVertex(xr, fm * xr + fb)
    else
      if !va or va.x > xr
        va = @createVertex(xr, fm * xr + fb)
      else if va.x < xl
        return false
      vb = @createVertex(xl, fm * xl + fb)
  edge.va = va
  edge.vb = vb
  true

# line-clipping code taken from:
#   Liang-Barsky function by Daniel White
#   http://www.skytopia.com/project/articles/compsci/clipping.html
# Thanks!
# A bit modified to minimize code paths

Voronoi::clipEdge = (edge, bbox) ->
  ax = edge.va.x
  ay = edge.va.y
  bx = edge.vb.x
  _by = edge.vb.y
  t0 = 0
  t1 = 1
  dx = bx - ax
  dy = _by - ay
  # left
  q = ax - (bbox.xl)
  if dx == 0 and q < 0
    return false
  r = -q / dx
  if dx < 0
    if r < t0
      return false
    if r < t1
      t1 = r
  else if dx > 0
    if r > t1
      return false
    if r > t0
      t0 = r
  # right
  q = bbox.xr - ax
  if dx == 0 and q < 0
    return false
  r = q / dx
  if dx < 0
    if r > t1
      return false
    if r > t0
      t0 = r
  else if dx > 0
    if r < t0
      return false
    if r < t1
      t1 = r
  # top
  q = ay - (bbox.yt)
  if dy == 0 and q < 0
    return false
  r = -q / dy
  if dy < 0
    if r < t0
      return false
    if r < t1
      t1 = r
  else if dy > 0
    if r > t1
      return false
    if r > t0
      t0 = r
  # bottom
  q = bbox.yb - ay
  if dy == 0 and q < 0
    return false
  r = q / dy
  if dy < 0
    if r > t1
      return false
    if r > t0
      t0 = r
  else if dy > 0
    if r < t0
      return false
    if r < t1
      t1 = r
  # if we reach this point, Voronoi edge is within bbox
  # if t0 > 0, va needs to change
  # rhill 2011-06-03: we need to create a new vertex rather
  # than modifying the existing one, since the existing
  # one is likely shared with at least another edge
  if t0 > 0
    edge.va = @createVertex(ax + t0 * dx, ay + t0 * dy)
  # if t1 < 1, vb needs to change
  # rhill 2011-06-03: we need to create a new vertex rather
  # than modifying the existing one, since the existing
  # one is likely shared with at least another edge
  if t1 < 1
    edge.vb = @createVertex(ax + t1 * dx, ay + t1 * dy)
  # va and/or vb were clipped, thus we will need to close
  # cells which use this edge.
  if t0 > 0 or t1 < 1
    @cells[edge.lSite.voronoiId].closeMe = true
    @cells[edge.rSite.voronoiId].closeMe = true
  true

# Connect/cut edges at bounding box

Voronoi::clipEdges = (bbox) ->
  # connect all dangling edges to bounding box
  # or get rid of them if it can't be done
  edges = @edges
  iEdge = edges.length
  edge = undefined
  abs_fn = Math.abs
  # iterate backward so we can splice safely
  while iEdge--
    edge = edges[iEdge]
    # edge is removed if:
    #   it is wholly outside the bounding box
    #   it is looking more like a point than a line
    if !@connectEdge(edge, bbox) or !@clipEdge(edge, bbox) or abs_fn(edge.va.x - (edge.vb.x)) < 1e-9 and abs_fn(edge.va.y - (edge.vb.y)) < 1e-9
      edge.va = edge.vb = null
      edges.splice iEdge, 1
  return

# Close the cells.
# The cells are bound by the supplied bounding box.
# Each cell refers to its associated site, and a list
# of halfedges ordered counterclockwise.

Voronoi::closeCells = (bbox) ->
  xl = bbox.xl
  xr = bbox.xr
  yt = bbox.yt
  yb = bbox.yb
  cells = @cells
  iCell = cells.length
  cell = undefined
  iLeft = undefined
  halfedges = undefined
  nHalfedges = undefined
  edge = undefined
  va = undefined
  vb = undefined
  vz = undefined
  lastBorderSegment = undefined
  abs_fn = Math.abs
  while iCell--
    cell = cells[iCell]
    # prune, order halfedges counterclockwise, then add missing ones
    # required to close cells
    if !cell.prepareHalfedges()
      iArc++
      continue
    if !cell.closeMe
      iArc++
      continue
    # find first 'unclosed' point.
    # an 'unclosed' point will be the end point of a halfedge which
    # does not match the start point of the following halfedge
    halfedges = cell.halfedges
    nHalfedges = halfedges.length
    # special case: only one site, in which case, the viewport is the cell
    # ...
    # all other cases
    iLeft = 0
    while iLeft < nHalfedges
      va = halfedges[iLeft].getEndpoint()
      vz = halfedges[(iLeft + 1) % nHalfedges].getStartpoint()
      # if end point is not equal to start point, we need to add the missing
      # halfedge(s) up to vz
      if abs_fn(va.x - (vz.x)) >= 1e-9 or abs_fn(va.y - (vz.y)) >= 1e-9
        # rhill 2013-12-02:
        # "Holes" in the halfedges are not necessarily always adjacent.
        # https://github.com/gorhill/Javascript-Voronoi/issues/16
        # find entry point:
        switch true
          # walk downward along left side
          when this.equalWithEpsilon(va.x, xl) and this.lessThanWithEpsilon(va.y, yb)
            lastBorderSegment = @equalWithEpsilon(vz.x, xl)
            vb = @createVertex(xl, if lastBorderSegment then vz.y else yb)
            edge = @createBorderEdge(cell.site, va, vb)
            iLeft++
            halfedges.splice iLeft, 0, @createHalfedge(edge, cell.site, null)
            nHalfedges++
            if lastBorderSegment
              break
            va = vb
          # fall through
          # walk rightward along bottom side
          when this.equalWithEpsilon(va.y, yb) and this.lessThanWithEpsilon(va.x, xr)
            lastBorderSegment = @equalWithEpsilon(vz.y, yb)
            vb = @createVertex((if lastBorderSegment then vz.x else xr), yb)
            edge = @createBorderEdge(cell.site, va, vb)
            iLeft++
            halfedges.splice iLeft, 0, @createHalfedge(edge, cell.site, null)
            nHalfedges++
            if lastBorderSegment
              break
            va = vb
          # fall through
          # walk upward along right side
          when this.equalWithEpsilon(va.x, xr) and this.greaterThanWithEpsilon(va.y, yt)
            lastBorderSegment = @equalWithEpsilon(vz.x, xr)
            vb = @createVertex(xr, if lastBorderSegment then vz.y else yt)
            edge = @createBorderEdge(cell.site, va, vb)
            iLeft++
            halfedges.splice iLeft, 0, @createHalfedge(edge, cell.site, null)
            nHalfedges++
            if lastBorderSegment
              break
            va = vb
          # fall through
          # walk leftward along top side
          when this.equalWithEpsilon(va.y, yt) and this.greaterThanWithEpsilon(va.x, xl)
            lastBorderSegment = @equalWithEpsilon(vz.y, yt)
            vb = @createVertex((if lastBorderSegment then vz.x else xl), yt)
            edge = @createBorderEdge(cell.site, va, vb)
            iLeft++
            halfedges.splice iLeft, 0, @createHalfedge(edge, cell.site, null)
            nHalfedges++
            if lastBorderSegment
              break
            va = vb
            break
            # fall through
            # walk downward along left side
            lastBorderSegment = @equalWithEpsilon(vz.x, xl)
            vb = @createVertex(xl, if lastBorderSegment then vz.y else yb)
            edge = @createBorderEdge(cell.site, va, vb)
            iLeft++
            halfedges.splice iLeft, 0, @createHalfedge(edge, cell.site, null)
            nHalfedges++
            if lastBorderSegment
              break
            va = vb
            break
            # fall through
            # walk rightward along bottom side
            lastBorderSegment = @equalWithEpsilon(vz.y, yb)
            vb = @createVertex((if lastBorderSegment then vz.x else xr), yb)
            edge = @createBorderEdge(cell.site, va, vb)
            iLeft++
            halfedges.splice iLeft, 0, @createHalfedge(edge, cell.site, null)
            nHalfedges++
            if lastBorderSegment
              break
            va = vb
            break
            # fall through
            # walk upward along right side
            lastBorderSegment = @equalWithEpsilon(vz.x, xr)
            vb = @createVertex(xr, if lastBorderSegment then vz.y else yt)
            edge = @createBorderEdge(cell.site, va, vb)
            iLeft++
            halfedges.splice iLeft, 0, @createHalfedge(edge, cell.site, null)
            nHalfedges++
            if lastBorderSegment
              break
          # fall through
          else
            throw 'Voronoi.closeCells() > this makes no sense!'
      iLeft++
    cell.closeMe = false
  return

# ---------------------------------------------------------------------------
# Debugging helper

###
Voronoi.prototype.dumpBeachline = function(y) {
    console.log('Voronoi.dumpBeachline(%f) > Beachsections, from left to right:', y);
    if ( !this.beachline ) {
        console.log('  None');
        }
    else {
        var bs = this.beachline.getFirst(this.beachline.root);
        while ( bs ) {
            console.log('  site %d: xl: %f, xr: %f', bs.site.voronoiId, this.leftBreakPoint(bs, y), this.rightBreakPoint(bs, y));
            bs = bs.rbNext;
            }
        }
    };
###

# ---------------------------------------------------------------------------
# Helper: Quantize sites
# rhill 2013-10-12:
# This is to solve https://github.com/gorhill/Javascript-Voronoi/issues/15
# Since not all users will end up using the kind of coord values which would
# cause the issue to arise, I chose to let the user decide whether or not
# he should sanitize his coord values through this helper. This way, for
# those users who uses coord values which are known to be fine, no overhead is
# added.

Voronoi::quantizeSites = (sites) ->
  ε = @ε
  n = sites.length
  site = undefined
  while n--
    site = sites[n]
    site.x = Math.floor(site.x / ε) * ε
    site.y = Math.floor(site.y / ε) * ε
  return

# ---------------------------------------------------------------------------
# Helper: Recycle diagram: all vertex, edge and cell objects are
# "surrendered" to the Voronoi object for reuse.
# TODO: rhill-voronoi-core v2: more performance to be gained
# when I change the semantic of what is returned.

Voronoi::recycle = (diagram) ->
  if diagram
    if diagram instanceof @Diagram
      @toRecycle = diagram
    else
      throw 'Voronoi.recycleDiagram() > Need a Diagram object.'
  return

# ---------------------------------------------------------------------------
# Top-level Fortune loop
# rhill 2011-05-19:
#   Voronoi sites are kept client-side now, to allow
#   user to freely modify content. At compute time,
#   *references* to sites are copied locally.

Voronoi::compute = (sites, bbox) ->
  # to measure execution time
  startTime = new Date
  # init internal state
  @reset()
  # any diagram data available for recycling?
  # I do that here so that this is included in execution time
  if @toRecycle
    @vertexJunkyard = @vertexJunkyard.concat(@toRecycle.vertices)
    @edgeJunkyard = @edgeJunkyard.concat(@toRecycle.edges)
    @cellJunkyard = @cellJunkyard.concat(@toRecycle.cells)
    @toRecycle = null
  # Initialize site event queue
  siteEvents = sites.slice(0)
  siteEvents.sort (a, b) ->
    r = b.y - (a.y)
    if r
      return r
    b.x - (a.x)
  # process queue
  site = siteEvents.pop()
  siteid = 0
  xsitex = undefined
  xsitey = undefined
  cells = @cells
  circle = undefined
  # main loop
  loop
    # we need to figure whether we handle a site or circle event
    # for this we find out if there is a site event and it is
    # 'earlier' than the circle event
    circle = @firstCircleEvent
    # add beach section
    if site and (!circle or site.y < circle.y or site.y == circle.y and site.x < circle.x)
      # only if site is not a duplicate
      if site.x != xsitex or site.y != xsitey
        # first create cell for new site
        cells[siteid] = @createCell(site)
        site.voronoiId = siteid++
        # then create a beachsection for that site
        @addBeachsection site
        # remember last site coords to detect duplicate
        xsitey = site.y
        xsitex = site.x
      site = siteEvents.pop()
    else if circle
      @removeBeachsection circle.arc
    else
      break
  # wrapping-up:
  #   connect dangling edges to bounding box
  #   cut edges as per bounding box
  #   discard edges completely outside bounding box
  #   discard edges which are point-like
  @clipEdges bbox
  #   add missing edges in order to close opened cells
  @closeCells bbox
  # to measure execution time
  stopTime = new Date
  # prepare return values
  diagram = new (@Diagram)
  diagram.cells = @cells
  diagram.edges = @edges
  diagram.vertices = @vertices
  diagram.execTime = stopTime.getTime() - startTime.getTime()
  # clean up
  @reset()
  diagram

# ---
# generated by js2coffee 2.1.0
