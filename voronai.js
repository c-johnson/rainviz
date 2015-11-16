
/*!
Copyright (C) 2010-2013 Raymond Hill: https://github.com/gorhill/Javascript-Voronoi
MIT License: See https://github.com/gorhill/Javascript-Voronoi/LICENSE.md
 */

/*
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
 */

/*global Math */
var Voronoi;

Voronoi = function() {
  this.vertices = null;
  this.edges = null;
  this.cells = null;
  this.toRecycle = null;
  this.beachsectionJunkyard = [];
  this.circleEventJunkyard = [];
  this.vertexJunkyard = [];
  this.edgeJunkyard = [];
  this.cellJunkyard = [];
};

Voronoi.prototype.reset = function() {
  var beachsection;
  if (!this.beachline) {
    this.beachline = new this.RBTree;
  }
  if (this.beachline.root) {
    beachsection = this.beachline.getFirst(this.beachline.root);
    while (beachsection) {
      this.beachsectionJunkyard.push(beachsection);
      beachsection = beachsection.rbNext;
    }
  }
  this.beachline.root = null;
  if (!this.circleEvents) {
    this.circleEvents = new this.RBTree;
  }
  this.circleEvents.root = this.firstCircleEvent = null;
  this.vertices = [];
  this.edges = [];
  this.cells = [];
};

Voronoi.prototype.sqrt = Math.sqrt;

Voronoi.prototype.abs = Math.abs;

Voronoi.prototype.ε = Voronoi.ε = 1e-9;

Voronoi.prototype.invε = Voronoi.invε = 1.0 / Voronoi.ε;

Voronoi.prototype.equalWithEpsilon = function(a, b) {
  return this.abs(a - b) < 1e-9;
};

Voronoi.prototype.greaterThanWithEpsilon = function(a, b) {
  return a - b > 1e-9;
};

Voronoi.prototype.greaterThanOrEqualWithEpsilon = function(a, b) {
  return b - a < 1e-9;
};

Voronoi.prototype.lessThanWithEpsilon = function(a, b) {
  return b - a > 1e-9;
};

Voronoi.prototype.lessThanOrEqualWithEpsilon = function(a, b) {
  return a - b < 1e-9;
};

Voronoi.prototype.RBTree = function() {
  this.root = null;
};

Voronoi.prototype.RBTree.prototype.rbInsertSuccessor = function(node, successor) {
  var grandpa, parent, uncle;
  parent = void 0;
  if (node) {
    successor.rbPrevious = node;
    successor.rbNext = node.rbNext;
    if (node.rbNext) {
      node.rbNext.rbPrevious = successor;
    }
    node.rbNext = successor;
    if (node.rbRight) {
      node = node.rbRight;
      while (node.rbLeft) {
        node = node.rbLeft;
      }
      node.rbLeft = successor;
    } else {
      node.rbRight = successor;
    }
    parent = node;
  } else if (this.root) {
    node = this.getFirst(this.root);
    successor.rbPrevious = null;
    successor.rbNext = node;
    node.rbPrevious = successor;
    node.rbLeft = successor;
    parent = node;
  } else {
    successor.rbPrevious = successor.rbNext = null;
    this.root = successor;
    parent = null;
  }
  successor.rbLeft = successor.rbRight = null;
  successor.rbParent = parent;
  successor.rbRed = true;
  grandpa = void 0;
  uncle = void 0;
  node = successor;
  while (parent && parent.rbRed) {
    grandpa = parent.rbParent;
    if (parent === grandpa.rbLeft) {
      uncle = grandpa.rbRight;
      if (uncle && uncle.rbRed) {
        parent.rbRed = uncle.rbRed = false;
        grandpa.rbRed = true;
        node = grandpa;
      } else {
        if (node === parent.rbRight) {
          this.rbRotateLeft(parent);
          node = parent;
          parent = node.rbParent;
        }
        parent.rbRed = false;
        grandpa.rbRed = true;
        this.rbRotateRight(grandpa);
      }
    } else {
      uncle = grandpa.rbLeft;
      if (uncle && uncle.rbRed) {
        parent.rbRed = uncle.rbRed = false;
        grandpa.rbRed = true;
        node = grandpa;
      } else {
        if (node === parent.rbLeft) {
          this.rbRotateRight(parent);
          node = parent;
          parent = node.rbParent;
        }
        parent.rbRed = false;
        grandpa.rbRed = true;
        this.rbRotateLeft(grandpa);
      }
    }
    parent = node.rbParent;
  }
  this.root.rbRed = false;
};

Voronoi.prototype.RBTree.prototype.rbRemoveNode = function(node) {
  var isRed, left, next, parent, right, sibling;
  if (node.rbNext) {
    node.rbNext.rbPrevious = node.rbPrevious;
  }
  if (node.rbPrevious) {
    node.rbPrevious.rbNext = node.rbNext;
  }
  node.rbNext = node.rbPrevious = null;
  parent = node.rbParent;
  left = node.rbLeft;
  right = node.rbRight;
  next = void 0;
  if (!left) {
    next = right;
  } else if (!right) {
    next = left;
  } else {
    next = this.getFirst(right);
  }
  if (parent) {
    if (parent.rbLeft === node) {
      parent.rbLeft = next;
    } else {
      parent.rbRight = next;
    }
  } else {
    this.root = next;
  }
  isRed = void 0;
  if (left && right) {
    isRed = next.rbRed;
    next.rbRed = node.rbRed;
    next.rbLeft = left;
    left.rbParent = next;
    if (next !== right) {
      parent = next.rbParent;
      next.rbParent = node.rbParent;
      node = next.rbRight;
      parent.rbLeft = node;
      next.rbRight = right;
      right.rbParent = next;
    } else {
      next.rbParent = parent;
      parent = next;
      node = next.rbRight;
    }
  } else {
    isRed = node.rbRed;
    node = next;
  }
  if (node) {
    node.rbParent = parent;
  }
  if (isRed) {
    return;
  }
  if (node && node.rbRed) {
    node.rbRed = false;
    return;
  }
  sibling = void 0;
  while (true) {
    if (node === this.root) {
      break;
    }
    if (node === parent.rbLeft) {
      sibling = parent.rbRight;
      if (sibling.rbRed) {
        sibling.rbRed = false;
        parent.rbRed = true;
        this.rbRotateLeft(parent);
        sibling = parent.rbRight;
      }
      if (sibling.rbLeft && sibling.rbLeft.rbRed || sibling.rbRight && sibling.rbRight.rbRed) {
        if (!sibling.rbRight || !sibling.rbRight.rbRed) {
          sibling.rbLeft.rbRed = false;
          sibling.rbRed = true;
          this.rbRotateRight(sibling);
          sibling = parent.rbRight;
        }
        sibling.rbRed = parent.rbRed;
        parent.rbRed = sibling.rbRight.rbRed = false;
        this.rbRotateLeft(parent);
        node = this.root;
        break;
      }
    } else {
      sibling = parent.rbLeft;
      if (sibling.rbRed) {
        sibling.rbRed = false;
        parent.rbRed = true;
        this.rbRotateRight(parent);
        sibling = parent.rbLeft;
      }
      if (sibling.rbLeft && sibling.rbLeft.rbRed || sibling.rbRight && sibling.rbRight.rbRed) {
        if (!sibling.rbLeft || !sibling.rbLeft.rbRed) {
          sibling.rbRight.rbRed = false;
          sibling.rbRed = true;
          this.rbRotateLeft(sibling);
          sibling = parent.rbLeft;
        }
        sibling.rbRed = parent.rbRed;
        parent.rbRed = sibling.rbLeft.rbRed = false;
        this.rbRotateRight(parent);
        node = this.root;
        break;
      }
    }
    sibling.rbRed = true;
    node = parent;
    parent = parent.rbParent;
    if (!!node.rbRed) {
      break;
    }
  }
  if (node) {
    node.rbRed = false;
  }
};

Voronoi.prototype.RBTree.prototype.rbRotateLeft = function(node) {
  var p, parent, q;
  p = node;
  q = node.rbRight;
  parent = p.rbParent;
  if (parent) {
    if (parent.rbLeft === p) {
      parent.rbLeft = q;
    } else {
      parent.rbRight = q;
    }
  } else {
    this.root = q;
  }
  q.rbParent = parent;
  p.rbParent = q;
  p.rbRight = q.rbLeft;
  if (p.rbRight) {
    p.rbRight.rbParent = p;
  }
  q.rbLeft = p;
};

Voronoi.prototype.RBTree.prototype.rbRotateRight = function(node) {
  var p, parent, q;
  p = node;
  q = node.rbLeft;
  parent = p.rbParent;
  if (parent) {
    if (parent.rbLeft === p) {
      parent.rbLeft = q;
    } else {
      parent.rbRight = q;
    }
  } else {
    this.root = q;
  }
  q.rbParent = parent;
  p.rbParent = q;
  p.rbLeft = q.rbRight;
  if (p.rbLeft) {
    p.rbLeft.rbParent = p;
  }
  q.rbRight = p;
};

Voronoi.prototype.RBTree.prototype.getFirst = function(node) {
  while (node.rbLeft) {
    node = node.rbLeft;
  }
  return node;
};

Voronoi.prototype.RBTree.prototype.getLast = function(node) {
  while (node.rbRight) {
    node = node.rbRight;
  }
  return node;
};

Voronoi.prototype.Diagram = function(site) {
  this.site = site;
};

Voronoi.prototype.Cell = function(site) {
  this.site = site;
  this.halfedges = [];
  this.closeMe = false;
};

Voronoi.prototype.Cell.prototype.init = function(site) {
  this.site = site;
  this.halfedges = [];
  this.closeMe = false;
  return this;
};

Voronoi.prototype.createCell = function(site) {
  var cell;
  cell = this.cellJunkyard.pop();
  if (cell) {
    return cell.init(site);
  }
  return new this.Cell(site);
};

Voronoi.prototype.Cell.prototype.prepareHalfedges = function() {
  var edge, halfedges, iHalfedge;
  halfedges = this.halfedges;
  iHalfedge = halfedges.length;
  edge = void 0;
  while (iHalfedge--) {
    edge = halfedges[iHalfedge].edge;
    if (!edge.vb || !edge.va) {
      halfedges.splice(iHalfedge, 1);
    }
  }
  halfedges.sort(function(a, b) {
    return b.angle - a.angle;
  });
  return halfedges.length;
};

Voronoi.prototype.Cell.prototype.getNeighborIds = function() {
  var edge, iHalfedge, neighbors;
  neighbors = [];
  iHalfedge = this.halfedges.length;
  edge = void 0;
  while (iHalfedge--) {
    edge = this.halfedges[iHalfedge].edge;
    if (edge.lSite !== null && edge.lSite.voronoiId !== this.site.voronoiId) {
      neighbors.push(edge.lSite.voronoiId);
    } else if (edge.rSite !== null && edge.rSite.voronoiId !== this.site.voronoiId) {
      neighbors.push(edge.rSite.voronoiId);
    }
  }
  return neighbors;
};

Voronoi.prototype.Cell.prototype.getBbox = function() {
  var halfedges, iHalfedge, v, vx, vy, xmax, xmin, ymax, ymin;
  halfedges = this.halfedges;
  iHalfedge = halfedges.length;
  xmin = Infinity;
  ymin = Infinity;
  xmax = -Infinity;
  ymax = -Infinity;
  v = void 0;
  vx = void 0;
  vy = void 0;
  while (iHalfedge--) {
    v = halfedges[iHalfedge].getStartpoint();
    vx = v.x;
    vy = v.y;
    if (vx < xmin) {
      xmin = vx;
    }
    if (vy < ymin) {
      ymin = vy;
    }
    if (vx > xmax) {
      xmax = vx;
    }
    if (vy > ymax) {
      ymax = vy;
    }
  }
  return {
    x: xmin,
    y: ymin,
    width: xmax - xmin,
    height: ymax - ymin
  };
};

Voronoi.prototype.Cell.prototype.pointIntersection = function(x, y) {
  var halfedge, halfedges, iHalfedge, p0, p1, r;
  halfedges = this.halfedges;
  iHalfedge = halfedges.length;
  halfedge = void 0;
  p0 = void 0;
  p1 = void 0;
  r = void 0;
  while (iHalfedge--) {
    halfedge = halfedges[iHalfedge];
    p0 = halfedge.getStartpoint();
    p1 = halfedge.getEndpoint();
    r = (y - p0.y) * (p1.x - p0.x) - ((x - p0.x) * (p1.y - p0.y));
    if (!r) {
      return 0;
    }
    if (r > 0) {
      return -1;
    }
  }
  return 1;
};

Voronoi.prototype.Vertex = function(x, y) {
  this.x = x;
  this.y = y;
};

Voronoi.prototype.Edge = function(lSite, rSite) {
  this.lSite = lSite;
  this.rSite = rSite;
  this.va = this.vb = null;
};

Voronoi.prototype.Halfedge = function(edge, lSite, rSite) {
  var va, vb;
  this.site = lSite;
  this.edge = edge;
  if (rSite) {
    this.angle = Math.atan2(rSite.y - lSite.y, rSite.x - lSite.x);
  } else {
    va = edge.va;
    vb = edge.vb;
    this.angle = edge.lSite === lSite ? Math.atan2(vb.x - va.x, va.y - vb.y) : Math.atan2(va.x - vb.x, vb.y - va.y);
  }
};

Voronoi.prototype.createHalfedge = function(edge, lSite, rSite) {
  return new this.Halfedge(edge, lSite, rSite);
};

Voronoi.prototype.Halfedge.prototype.getStartpoint = function() {
  if (this.edge.lSite === this.site) {
    return this.edge.va;
  } else {
    return this.edge.vb;
  }
};

Voronoi.prototype.Halfedge.prototype.getEndpoint = function() {
  if (this.edge.lSite === this.site) {
    return this.edge.vb;
  } else {
    return this.edge.va;
  }
};

Voronoi.prototype.createVertex = function(x, y) {
  var v;
  v = this.vertexJunkyard.pop();
  if (!v) {
    v = new this.Vertex(x, y);
  } else {
    v.x = x;
    v.y = y;
  }
  this.vertices.push(v);
  return v;
};

Voronoi.prototype.createEdge = function(lSite, rSite, va, vb) {
  var edge;
  edge = this.edgeJunkyard.pop();
  if (!edge) {
    edge = new this.Edge(lSite, rSite);
  } else {
    edge.lSite = lSite;
    edge.rSite = rSite;
    edge.va = edge.vb = null;
  }
  this.edges.push(edge);
  if (va) {
    this.setEdgeStartpoint(edge, lSite, rSite, va);
  }
  if (vb) {
    this.setEdgeEndpoint(edge, lSite, rSite, vb);
  }
  this.cells[lSite.voronoiId].halfedges.push(this.createHalfedge(edge, lSite, rSite));
  this.cells[rSite.voronoiId].halfedges.push(this.createHalfedge(edge, rSite, lSite));
  return edge;
};

Voronoi.prototype.createBorderEdge = function(lSite, va, vb) {
  var edge;
  edge = this.edgeJunkyard.pop();
  if (!edge) {
    edge = new this.Edge(lSite, null);
  } else {
    edge.lSite = lSite;
    edge.rSite = null;
  }
  edge.va = va;
  edge.vb = vb;
  this.edges.push(edge);
  return edge;
};

Voronoi.prototype.setEdgeStartpoint = function(edge, lSite, rSite, vertex) {
  if (!edge.va && !edge.vb) {
    edge.va = vertex;
    edge.lSite = lSite;
    edge.rSite = rSite;
  } else if (edge.lSite === rSite) {
    edge.vb = vertex;
  } else {
    edge.va = vertex;
  }
};

Voronoi.prototype.setEdgeEndpoint = function(edge, lSite, rSite, vertex) {
  this.setEdgeStartpoint(edge, rSite, lSite, vertex);
};

Voronoi.prototype.Beachsection = function() {};

Voronoi.prototype.createBeachsection = function(site) {
  var beachsection;
  beachsection = this.beachsectionJunkyard.pop();
  if (!beachsection) {
    beachsection = new this.Beachsection;
  }
  beachsection.site = site;
  return beachsection;
};

Voronoi.prototype.leftBreakPoint = function(arc, directrix) {
  var aby2, b, hl, lArc, lfocx, lfocy, pby2, plby2, rfocx, rfocy, site;
  site = arc.site;
  rfocx = site.x;
  rfocy = site.y;
  pby2 = rfocy - directrix;
  if (!pby2) {
    return rfocx;
  }
  lArc = arc.rbPrevious;
  if (!lArc) {
    return -Infinity;
  }
  site = lArc.site;
  lfocx = site.x;
  lfocy = site.y;
  plby2 = lfocy - directrix;
  if (!plby2) {
    return lfocx;
  }
  hl = lfocx - rfocx;
  aby2 = 1 / pby2 - (1 / plby2);
  b = hl / plby2;
  if (aby2) {
    return (-b + this.sqrt(b * b - (2 * aby2 * (hl * hl / (-2 * plby2) - lfocy + plby2 / 2 + rfocy - (pby2 / 2))))) / aby2 + rfocx;
  }
  return (rfocx + lfocx) / 2;
};

Voronoi.prototype.rightBreakPoint = function(arc, directrix) {
  var rArc, site;
  rArc = arc.rbNext;
  if (rArc) {
    return this.leftBreakPoint(rArc, directrix);
  }
  site = arc.site;
  if (site.y === directrix) {
    return site.x;
  } else {
    return Infinity;
  }
};

Voronoi.prototype.detachBeachsection = function(beachsection) {
  this.detachCircleEvent(beachsection);
  this.beachline.rbRemoveNode(beachsection);
  this.beachsectionJunkyard.push(beachsection);
};

Voronoi.prototype.removeBeachsection = function(beachsection) {
  var abs_fn, circle, disappearingTransitions, iArc, lArc, nArcs, next, previous, rArc, vertex, x, y;
  circle = beachsection.circleEvent;
  x = circle.x;
  y = circle.ycenter;
  vertex = this.createVertex(x, y);
  previous = beachsection.rbPrevious;
  next = beachsection.rbNext;
  disappearingTransitions = [beachsection];
  abs_fn = Math.abs;
  this.detachBeachsection(beachsection);
  lArc = previous;
  while (lArc.circleEvent && abs_fn(x - lArc.circleEvent.x) < 1e-9 && abs_fn(y - lArc.circleEvent.ycenter) < 1e-9) {
    previous = lArc.rbPrevious;
    disappearingTransitions.unshift(lArc);
    this.detachBeachsection(lArc);
    lArc = previous;
  }
  disappearingTransitions.unshift(lArc);
  this.detachCircleEvent(lArc);
  rArc = next;
  while (rArc.circleEvent && abs_fn(x - rArc.circleEvent.x) < 1e-9 && abs_fn(y - rArc.circleEvent.ycenter) < 1e-9) {
    next = rArc.rbNext;
    disappearingTransitions.push(rArc);
    this.detachBeachsection(rArc);
    rArc = next;
  }
  disappearingTransitions.push(rArc);
  this.detachCircleEvent(rArc);
  nArcs = disappearingTransitions.length;
  iArc = void 0;
  iArc = 1;
  while (iArc < nArcs) {
    rArc = disappearingTransitions[iArc];
    lArc = disappearingTransitions[iArc - 1];
    this.setEdgeStartpoint(rArc.edge, lArc.site, rArc.site, vertex);
    iArc++;
  }
  lArc = disappearingTransitions[0];
  rArc = disappearingTransitions[nArcs - 1];
  rArc.edge = this.createEdge(lArc.site, rArc.site, void 0, vertex);
  this.attachCircleEvent(lArc);
  this.attachCircleEvent(rArc);
};

Voronoi.prototype.addBeachsection = function(site) {
  var _by, ax, ay, bx, cx, cy, d, directrix, dxl, dxr, hb, hc, lArc, lSite, newArc, node, rArc, rSite, vertex, x;
  x = site.x;
  directrix = site.y;
  lArc = void 0;
  rArc = void 0;
  dxl = void 0;
  dxr = void 0;
  node = this.beachline.root;
  while (node) {
    dxl = this.leftBreakPoint(node, directrix) - x;
    if (dxl > 1e-9) {
      node = node.rbLeft;
    } else {
      dxr = x - this.rightBreakPoint(node, directrix);
      if (dxr > 1e-9) {
        if (!node.rbRight) {
          lArc = node;
          break;
        }
        node = node.rbRight;
      } else {
        if (dxl > -1e-9) {
          lArc = node.rbPrevious;
          rArc = node;
        } else if (dxr > -1e-9) {
          lArc = node;
          rArc = node.rbNext;
        } else {
          lArc = rArc = node;
        }
        break;
      }
    }
  }
  newArc = this.createBeachsection(site);
  this.beachline.rbInsertSuccessor(lArc, newArc);
  if (!lArc && !rArc) {
    return;
  }
  if (lArc === rArc) {
    this.detachCircleEvent(lArc);
    rArc = this.createBeachsection(lArc.site);
    this.beachline.rbInsertSuccessor(newArc, rArc);
    newArc.edge = rArc.edge = this.createEdge(lArc.site, newArc.site);
    this.attachCircleEvent(lArc);
    this.attachCircleEvent(rArc);
    return;
  }
  if (lArc && !rArc) {
    newArc.edge = this.createEdge(lArc.site, newArc.site);
    return;
  }
  if (lArc !== rArc) {
    this.detachCircleEvent(lArc);
    this.detachCircleEvent(rArc);
    lSite = lArc.site;
    ax = lSite.x;
    ay = lSite.y;
    bx = site.x - ax;
    _by = site.y - ay;
    rSite = rArc.site;
    cx = rSite.x - ax;
    cy = rSite.y - ay;
    d = 2 * (bx * cy - (_by * cx));
    hb = bx * bx + _by * _by;
    hc = cx * cx + cy * cy;
    vertex = this.createVertex((cy * hb - (_by * hc)) / d + ax, (bx * hc - (cx * hb)) / d + ay);
    this.setEdgeStartpoint(rArc.edge, lSite, rSite, vertex);
    newArc.edge = this.createEdge(lSite, site, void 0, vertex);
    rArc.edge = this.createEdge(site, rSite, void 0, vertex);
    this.attachCircleEvent(lArc);
    this.attachCircleEvent(rArc);
    return;
  }
};

Voronoi.prototype.CircleEvent = function() {
  this.arc = null;
  this.rbLeft = null;
  this.rbNext = null;
  this.rbParent = null;
  this.rbPrevious = null;
  this.rbRed = false;
  this.rbRight = null;
  this.site = null;
  this.x = this.y = this.ycenter = 0;
};

Voronoi.prototype.attachCircleEvent = function(arc) {
  var _by, ax, ay, bx, cSite, circleEvent, cx, cy, d, ha, hc, lArc, lSite, node, predecessor, rArc, rSite, x, y, ycenter;
  lArc = arc.rbPrevious;
  rArc = arc.rbNext;
  if (!lArc || !rArc) {
    return;
  }
  lSite = lArc.site;
  cSite = arc.site;
  rSite = rArc.site;
  if (lSite === rSite) {
    return;
  }
  bx = cSite.x;
  _by = cSite.y;
  ax = lSite.x - bx;
  ay = lSite.y - _by;
  cx = rSite.x - bx;
  cy = rSite.y - _by;
  d = 2 * (ax * cy - (ay * cx));
  if (d >= -2e-12) {
    return;
  }
  ha = ax * ax + ay * ay;
  hc = cx * cx + cy * cy;
  x = (cy * ha - (ay * hc)) / d;
  y = (ax * hc - (cx * ha)) / d;
  ycenter = y + _by;
  circleEvent = this.circleEventJunkyard.pop();
  if (!circleEvent) {
    circleEvent = new this.CircleEvent;
  }
  circleEvent.arc = arc;
  circleEvent.site = cSite;
  circleEvent.x = x + bx;
  circleEvent.y = ycenter + this.sqrt(x * x + y * y);
  circleEvent.ycenter = ycenter;
  arc.circleEvent = circleEvent;
  predecessor = null;
  node = this.circleEvents.root;
  while (node) {
    if (circleEvent.y < node.y || circleEvent.y === node.y && circleEvent.x <= node.x) {
      if (node.rbLeft) {
        node = node.rbLeft;
      } else {
        predecessor = node.rbPrevious;
        break;
      }
    } else {
      if (node.rbRight) {
        node = node.rbRight;
      } else {
        predecessor = node;
        break;
      }
    }
  }
  this.circleEvents.rbInsertSuccessor(predecessor, circleEvent);
  if (!predecessor) {
    this.firstCircleEvent = circleEvent;
  }
};

Voronoi.prototype.detachCircleEvent = function(arc) {
  var circleEvent;
  circleEvent = arc.circleEvent;
  if (circleEvent) {
    if (!circleEvent.rbPrevious) {
      this.firstCircleEvent = circleEvent.rbNext;
    }
    this.circleEvents.rbRemoveNode(circleEvent);
    this.circleEventJunkyard.push(circleEvent);
    arc.circleEvent = null;
  }
};

Voronoi.prototype.connectEdge = function(edge, bbox) {
  var fb, fm, fx, fy, lSite, lx, ly, rSite, rx, ry, va, vb, xl, xr, yb, yt;
  vb = edge.vb;
  if (!!vb) {
    return true;
  }
  va = edge.va;
  xl = bbox.xl;
  xr = bbox.xr;
  yt = bbox.yt;
  yb = bbox.yb;
  lSite = edge.lSite;
  rSite = edge.rSite;
  lx = lSite.x;
  ly = lSite.y;
  rx = rSite.x;
  ry = rSite.y;
  fx = (lx + rx) / 2;
  fy = (ly + ry) / 2;
  fm = void 0;
  fb = void 0;
  this.cells[lSite.voronoiId].closeMe = true;
  this.cells[rSite.voronoiId].closeMe = true;
  if (ry !== ly) {
    fm = (lx - rx) / (ry - ly);
    fb = fy - (fm * fx);
  }
  if (fm === void 0) {
    if (fx < xl || fx >= xr) {
      return false;
    }
    if (lx > rx) {
      if (!va || va.y < yt) {
        va = this.createVertex(fx, yt);
      } else if (va.y >= yb) {
        return false;
      }
      vb = this.createVertex(fx, yb);
    } else {
      if (!va || va.y > yb) {
        va = this.createVertex(fx, yb);
      } else if (va.y < yt) {
        return false;
      }
      vb = this.createVertex(fx, yt);
    }
  } else if (fm < -1 || fm > 1) {
    if (lx > rx) {
      if (!va || va.y < yt) {
        va = this.createVertex((yt - fb) / fm, yt);
      } else if (va.y >= yb) {
        return false;
      }
      vb = this.createVertex((yb - fb) / fm, yb);
    } else {
      if (!va || va.y > yb) {
        va = this.createVertex((yb - fb) / fm, yb);
      } else if (va.y < yt) {
        return false;
      }
      vb = this.createVertex((yt - fb) / fm, yt);
    }
  } else {
    if (ly < ry) {
      if (!va || va.x < xl) {
        va = this.createVertex(xl, fm * xl + fb);
      } else if (va.x >= xr) {
        return false;
      }
      vb = this.createVertex(xr, fm * xr + fb);
    } else {
      if (!va || va.x > xr) {
        va = this.createVertex(xr, fm * xr + fb);
      } else if (va.x < xl) {
        return false;
      }
      vb = this.createVertex(xl, fm * xl + fb);
    }
  }
  edge.va = va;
  edge.vb = vb;
  return true;
};

Voronoi.prototype.clipEdge = function(edge, bbox) {
  var _by, ax, ay, bx, dx, dy, q, r, t0, t1;
  ax = edge.va.x;
  ay = edge.va.y;
  bx = edge.vb.x;
  _by = edge.vb.y;
  t0 = 0;
  t1 = 1;
  dx = bx - ax;
  dy = _by - ay;
  q = ax - bbox.xl;
  if (dx === 0 && q < 0) {
    return false;
  }
  r = -q / dx;
  if (dx < 0) {
    if (r < t0) {
      return false;
    }
    if (r < t1) {
      t1 = r;
    }
  } else if (dx > 0) {
    if (r > t1) {
      return false;
    }
    if (r > t0) {
      t0 = r;
    }
  }
  q = bbox.xr - ax;
  if (dx === 0 && q < 0) {
    return false;
  }
  r = q / dx;
  if (dx < 0) {
    if (r > t1) {
      return false;
    }
    if (r > t0) {
      t0 = r;
    }
  } else if (dx > 0) {
    if (r < t0) {
      return false;
    }
    if (r < t1) {
      t1 = r;
    }
  }
  q = ay - bbox.yt;
  if (dy === 0 && q < 0) {
    return false;
  }
  r = -q / dy;
  if (dy < 0) {
    if (r < t0) {
      return false;
    }
    if (r < t1) {
      t1 = r;
    }
  } else if (dy > 0) {
    if (r > t1) {
      return false;
    }
    if (r > t0) {
      t0 = r;
    }
  }
  q = bbox.yb - ay;
  if (dy === 0 && q < 0) {
    return false;
  }
  r = q / dy;
  if (dy < 0) {
    if (r > t1) {
      return false;
    }
    if (r > t0) {
      t0 = r;
    }
  } else if (dy > 0) {
    if (r < t0) {
      return false;
    }
    if (r < t1) {
      t1 = r;
    }
  }
  if (t0 > 0) {
    edge.va = this.createVertex(ax + t0 * dx, ay + t0 * dy);
  }
  if (t1 < 1) {
    edge.vb = this.createVertex(ax + t1 * dx, ay + t1 * dy);
  }
  if (t0 > 0 || t1 < 1) {
    this.cells[edge.lSite.voronoiId].closeMe = true;
    this.cells[edge.rSite.voronoiId].closeMe = true;
  }
  return true;
};

Voronoi.prototype.clipEdges = function(bbox) {
  var abs_fn, edge, edges, iEdge;
  edges = this.edges;
  iEdge = edges.length;
  edge = void 0;
  abs_fn = Math.abs;
  while (iEdge--) {
    edge = edges[iEdge];
    if (!this.connectEdge(edge, bbox) || !this.clipEdge(edge, bbox) || abs_fn(edge.va.x - edge.vb.x) < 1e-9 && abs_fn(edge.va.y - edge.vb.y) < 1e-9) {
      edge.va = edge.vb = null;
      edges.splice(iEdge, 1);
    }
  }
};

Voronoi.prototype.closeCells = function(bbox) {
  var abs_fn, cell, cells, edge, halfedges, iCell, iLeft, lastBorderSegment, nHalfedges, va, vb, vz, xl, xr, yb, yt;
  xl = bbox.xl;
  xr = bbox.xr;
  yt = bbox.yt;
  yb = bbox.yb;
  cells = this.cells;
  iCell = cells.length;
  cell = void 0;
  iLeft = void 0;
  halfedges = void 0;
  nHalfedges = void 0;
  edge = void 0;
  va = void 0;
  vb = void 0;
  vz = void 0;
  lastBorderSegment = void 0;
  abs_fn = Math.abs;
  while (iCell--) {
    cell = cells[iCell];
    if (!cell.prepareHalfedges()) {
      iArc++;
      continue;
    }
    if (!cell.closeMe) {
      iArc++;
      continue;
    }
    halfedges = cell.halfedges;
    nHalfedges = halfedges.length;
    iLeft = 0;
    while (iLeft < nHalfedges) {
      va = halfedges[iLeft].getEndpoint();
      vz = halfedges[(iLeft + 1) % nHalfedges].getStartpoint();
      if (abs_fn(va.x - vz.x) >= 1e-9 || abs_fn(va.y - vz.y) >= 1e-9) {
        switch (true) {
          case this.equalWithEpsilon(va.x, xl) && this.lessThanWithEpsilon(va.y, yb):
            lastBorderSegment = this.equalWithEpsilon(vz.x, xl);
            vb = this.createVertex(xl, lastBorderSegment ? vz.y : yb);
            edge = this.createBorderEdge(cell.site, va, vb);
            iLeft++;
            halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
            nHalfedges++;
            if (lastBorderSegment) {
              break;
            }
            va = vb;
            break;
          case this.equalWithEpsilon(va.y, yb) && this.lessThanWithEpsilon(va.x, xr):
            lastBorderSegment = this.equalWithEpsilon(vz.y, yb);
            vb = this.createVertex((lastBorderSegment ? vz.x : xr), yb);
            edge = this.createBorderEdge(cell.site, va, vb);
            iLeft++;
            halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
            nHalfedges++;
            if (lastBorderSegment) {
              break;
            }
            va = vb;
            break;
          case this.equalWithEpsilon(va.x, xr) && this.greaterThanWithEpsilon(va.y, yt):
            lastBorderSegment = this.equalWithEpsilon(vz.x, xr);
            vb = this.createVertex(xr, lastBorderSegment ? vz.y : yt);
            edge = this.createBorderEdge(cell.site, va, vb);
            iLeft++;
            halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
            nHalfedges++;
            if (lastBorderSegment) {
              break;
            }
            va = vb;
            break;
          case this.equalWithEpsilon(va.y, yt) && this.greaterThanWithEpsilon(va.x, xl):
            lastBorderSegment = this.equalWithEpsilon(vz.y, yt);
            vb = this.createVertex((lastBorderSegment ? vz.x : xl), yt);
            edge = this.createBorderEdge(cell.site, va, vb);
            iLeft++;
            halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
            nHalfedges++;
            if (lastBorderSegment) {
              break;
            }
            va = vb;
            break;
            lastBorderSegment = this.equalWithEpsilon(vz.x, xl);
            vb = this.createVertex(xl, lastBorderSegment ? vz.y : yb);
            edge = this.createBorderEdge(cell.site, va, vb);
            iLeft++;
            halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
            nHalfedges++;
            if (lastBorderSegment) {
              break;
            }
            va = vb;
            break;
            lastBorderSegment = this.equalWithEpsilon(vz.y, yb);
            vb = this.createVertex((lastBorderSegment ? vz.x : xr), yb);
            edge = this.createBorderEdge(cell.site, va, vb);
            iLeft++;
            halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
            nHalfedges++;
            if (lastBorderSegment) {
              break;
            }
            va = vb;
            break;
            lastBorderSegment = this.equalWithEpsilon(vz.x, xr);
            vb = this.createVertex(xr, lastBorderSegment ? vz.y : yt);
            edge = this.createBorderEdge(cell.site, va, vb);
            iLeft++;
            halfedges.splice(iLeft, 0, this.createHalfedge(edge, cell.site, null));
            nHalfedges++;
            if (lastBorderSegment) {
              break;
            }
            break;
          default:
            throw 'Voronoi.closeCells() > this makes no sense!';
        }
      }
      iLeft++;
    }
    cell.closeMe = false;
  }
};


/*
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
 */

Voronoi.prototype.quantizeSites = function(sites) {
  var n, site, ε;
  ε = this.ε;
  n = sites.length;
  site = void 0;
  while (n--) {
    site = sites[n];
    site.x = Math.floor(site.x / ε) * ε;
    site.y = Math.floor(site.y / ε) * ε;
  }
};

Voronoi.prototype.recycle = function(diagram) {
  if (diagram) {
    if (diagram instanceof this.Diagram) {
      this.toRecycle = diagram;
    } else {
      throw 'Voronoi.recycleDiagram() > Need a Diagram object.';
    }
  }
};

Voronoi.prototype.compute = function(sites, bbox) {
  var cells, circle, diagram, site, siteEvents, siteid, startTime, stopTime, xsitex, xsitey;
  startTime = new Date;
  this.reset();
  if (this.toRecycle) {
    this.vertexJunkyard = this.vertexJunkyard.concat(this.toRecycle.vertices);
    this.edgeJunkyard = this.edgeJunkyard.concat(this.toRecycle.edges);
    this.cellJunkyard = this.cellJunkyard.concat(this.toRecycle.cells);
    this.toRecycle = null;
  }
  siteEvents = sites.slice(0);
  siteEvents.sort(function(a, b) {
    var r;
    r = b.y - a.y;
    if (r) {
      return r;
    }
    return b.x - a.x;
  });
  site = siteEvents.pop();
  siteid = 0;
  xsitex = void 0;
  xsitey = void 0;
  cells = this.cells;
  circle = void 0;
  while (true) {
    circle = this.firstCircleEvent;
    if (site && (!circle || site.y < circle.y || site.y === circle.y && site.x < circle.x)) {
      if (site.x !== xsitex || site.y !== xsitey) {
        cells[siteid] = this.createCell(site);
        site.voronoiId = siteid++;
        this.addBeachsection(site);
        xsitey = site.y;
        xsitex = site.x;
      }
      site = siteEvents.pop();
    } else if (circle) {
      this.removeBeachsection(circle.arc);
    } else {
      break;
    }
  }
  this.clipEdges(bbox);
  this.closeCells(bbox);
  stopTime = new Date;
  diagram = new this.Diagram;
  diagram.cells = this.cells;
  diagram.edges = this.edges;
  diagram.vertices = this.vertices;
  diagram.execTime = stopTime.getTime() - startTime.getTime();
  this.reset();
  return diagram;
};

//# sourceMappingURL=voronai.js.map
