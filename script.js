var CanvasDrawer, GeoFeature, GeoPolygon, RainThing, thing,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

window.noop = function() {};

window.polygon = function(d) {
  return "M" + d.join("L") + "Z";
};

RainThing = (function() {
  function RainThing() {
    this.width = 960;
    this.height = 1160;
    this.californication();
  }

  RainThing.prototype.makeDisplay = function(type) {
    var display;
    display = d3.select("body").append(type).attr("width", this.width).attr("height", this.height).attr("style", "border: 1px solid black;");
    return display;
  };

  RainThing.prototype.makePoint = function(id, coord) {
    return {
      "type": "Feature",
      "properties": {
        "GEO_ID": "0400000US06",
        "STATE": "06",
        "NAME": id,
        "LSAD": "",
        "CENSUSAREA": 155779.220000
      },
      "geometry": {
        "type": "Point",
        "coordinates": coord
      }
    };
  };

  RainThing.prototype.projectLineString = function(feature, projection) {
    var line;
    line = [];
    d3.geo.stream(feature, projection.stream({
      polygonStart: noop,
      polygonEnd: noop,
      lineStart: noop,
      lineEnd: noop,
      point: function(x, y) {
        return line.push([x, y]);
      },
      sphere: noop
    }));
    return line;
  };

  RainThing.prototype.randomizeArea = function(d, double) {
    var num1, num2;
    num1 = Math.abs(d3.geom.polygon(d).area());
    num1 = double ? num1 * 2 : num1;
    num2 = Math.random() * 10000;
    return (num1 + num2) / 2;
  };

  RainThing.prototype.californication = function() {
    var svg;
    svg = this.makeDisplay("svg");
    return d3.json('data/USA-california.json', (function(_this) {
      return function(geoCali) {
        return d3.csv('data/station-coords.csv', function(stationCoords) {
          var caliLineString, fillBlue, fillRed, geoStations, projection, self, stationCoordinates, usaPath, voronoi;
          fillRed = d3.scale.linear().domain([0, 10000]).range(["#fff", "#f00"]);
          fillBlue = d3.scale.linear().domain([0, 10000]).range(["#fff", "#00f"]);
          projection = d3.geo.albersUsa().scale(3500).translate([1600, 400]);
          stationCoordinates = stationCoords.map(function(d) {
            return [+d.long, +d.lat];
          });
          caliLineString = _this.projectLineString(geoCali, projection);
          voronoi = d3.geom.voronoi();
          geoStations = new GeoFeature;
          _.each(stationCoords, function(station) {
            var coords, stationId;
            stationId = "station-" + station.name;
            coords = [parseFloat(parseFloat(station.long).toFixed(2)), parseFloat(parseFloat(station.lat).toFixed(2))];
            return geoStations.features.push(_this.makePoint(stationId, coords));
          });
          usaPath = d3.geo.path(geoCali).projection(projection);
          svg.append("path").datum(geoCali).attr("d", usaPath);
          svg.selectAll(".subunit").data(geoCali.features).enter().append("path").attr("class", function(d) {
            return "subunit-" + d.properties.NAME;
          }).attr("d", usaPath).on('mouseenter', function(feature) {
            if (feature.geometry.type === "Point") {
              return this.style.fill = "blue";
            }
          }).on('mouseleave', function(feature) {
            return this.style.fill = "";
          });
          self = _this;
          return svg.append("g").attr("class", "land").selectAll(".voronoi").data(voronoi(stationCoordinates.map(projection)).map(function(d) {
            return d3.geom.polygon(d).clip(caliLineString.slice());
          })).enter().append("path").attr("class", "voronoi").style("fill", function(d) {
            d.initialArea = self.randomizeArea(d, false);
            return fillBlue(d.initialArea);
          }).attr("d", polygon).on('mouseenter', function(d) {
            return this.style.fill = fillBlue(self.randomizeArea(d, true));
          }).on('mouseleave', function(d) {
            return this.style.fill = fillBlue(d.initialArea);
          });
        });
      };
    })(this));
  };

  RainThing.prototype.usaify = function() {
    var svg;
    svg = this.makeDisplay("svg");
    return d3.json('data/USA-states.json', (function(_this) {
      return function(geoUSA) {
        var projection, usaPath;
        projection = d3.geo.albersUsa().scale(1000).translate([_this.width / 2, _this.height / 2]);
        usaPath = d3.geo.path(geoUSA).projection(projection);
        svg.append("path").datum(geoUSA).attr("d", usaPath);
        return svg.selectAll(".subunit").data(geoUSA.features).enter().append("path").attr("class", function(d) {
          return "subunit-" + d.properties.NAME;
        }).attr("d", usaPath).on('mouseenter', function(feature) {
          return this.style.fill = "blue";
        }).on('mouseleave', function(feature) {
          return this.style.fill = "";
        });
      };
    })(this));
  };

  RainThing.prototype.derpyCal = function() {
    return d3.csv('data/cal-boundary.csv', (function(_this) {
      return function(data) {
        var caliPath, canvas, context, drawer, gJson, geoCali, projection;
        canvas = _this.makeDisplay("canvas");
        geoCali = new GeoPolygon(_.map(data, function(dat) {
          return [parseFloat(dat.lat), parseFloat(dat.long)];
        }));
        window.Cali = geoCali;
        gJson = geoCali.geoJson;
        projection = d3.geo.albersUsa().scale(1000);
        context = canvas.node().getContext("2d");
        caliPath = d3.geo.path().projection(projection).context(context);
        gJson.bbox = gJson.features[0].bbox = gJson.bounds;
        caliPath(topojson.feature(gJson, gJson.features[0]));
        drawer = new CanvasDrawer;
        return drawer.drawCanvasThing(960, 500, gJson.bbox, gJson, context);
      };
    })(this));
  };

  RainThing.prototype.refugeeChart = function() {
    d3.csv('data/chart.csv', function(data) {
      var div, refugeeMax, refugeeMin;
      refugeeMax = data[data.length - 1].numRefugees;
      refugeeMin = data[0].numRefugees;
      div = d3.select('.the-data').append('div').attr('class', 'tooltip').style('opacity', 0);
      d3.select('.the-data').selectAll('div').data(data).enter().append('div').classed('data-row', true);
      d3.selectAll('.data-row').append('div').classed('bar', true).style('background-color', function(d) {
        if (d.numRefugees <= 100000) {
          return 'green';
        } else if (d.numRefugees > 100000 && d.numRefugees <= 500000) {
          return 'yellow';
        } else if (d.numRefugees > 500000 && d.numRefugees <= 2000000) {
          return 'orange';
        } else if (d.numRefugees > 2000000) {
          return 'red';
        }
      }).style('height', function(d) {
        var barHeight, percent;
        percent = d.numRefugees / refugeeMax;
        barHeight = percent * 250;
        return barHeight + 10 + 'px';
      }).on('mouseover', function(d) {
        div.transition().duration(0).style('opacity', .9);
        div.html(d.numRefugees + '<br/>' + 'refugees').style('left', d3.event.pageX + 'px').style('top', d3.event.pageY - 28 + 'px');
      }).on('mouseout', function(d) {
        div.transition().duration(0).style('opacity', 0);
      });
      d3.selectAll('.data-row').append('p').classed('label', true).text(function(data) {
        return data.date;
      });
    });
    return console.log('you are now rocking with d3', d3);
  };

  return RainThing;

})();

GeoFeature = (function() {
  function GeoFeature() {
    this.type = "FeatureCollection";
    this.features = [];
  }

  return GeoFeature;

})();

GeoPolygon = (function() {
  function GeoPolygon(coords) {
    this.updateCoords = bind(this.updateCoords, this);
    this.geoJson = {
      "type": "FeatureCollection",
      "bbox": [],
      "features": [
        {
          "type": "Feature",
          "bbox": [],
          "geometry": {
            "type": "Polygon",
            "coordinates": [coords]
          }
        }
      ]
    };
    this.updateCoords(coords);
  }

  GeoPolygon.prototype.fLen = function() {
    var ref, ref1;
    return (ref = this.geoJson) != null ? (ref1 = ref.features) != null ? ref1.length : void 0 : void 0;
  };

  GeoPolygon.prototype.updateFeature = function(ind, newCoords) {
    var bounds, feature, k, lat, len, long, newCoord, ref, ref1, results;
    if (feature = (ref = this.geoJson) != null ? ref.features[ind] : void 0) {
      if ((ref1 = feature.geometry) != null) {
        ref1.coordinates = [newCoords];
      }
      this.geoJson.bounds = bounds = [[], []];
      results = [];
      for (k = 0, len = newCoords.length; k < len; k++) {
        newCoord = newCoords[k];
        long = newCoord[0];
        lat = newCoord[1];
        bounds[0][0] = bounds.xMin = bounds.xMin < long ? bounds.xMin : long;
        bounds[1][0] = bounds.xMax = bounds.xMax > long ? bounds.xMax : long;
        bounds[1][1] = bounds.yMin = bounds.yMin < lat ? bounds.yMin : lat;
        results.push(bounds[0][1] = bounds.yMax = bounds.yMax > lat ? bounds.yMax : lat);
      }
      return results;
    }
  };

  GeoPolygon.prototype.updateCoords = function(newCoords, index) {
    var i, k, ref, results;
    if (newCoords) {
      if (index) {
        return this.updateFeature(index, newCoords);
      } else {
        results = [];
        for (i = k = 0, ref = this.fLen(); 0 <= ref ? k <= ref : k >= ref; i = 0 <= ref ? ++k : --k) {
          results.push(this.updateFeature(i, newCoords));
        }
        return results;
      }
    }
  };

  return GeoPolygon;

})();

CanvasDrawer = (function() {
  function CanvasDrawer() {}

  CanvasDrawer.prototype.drawCanvasThing = function(width, height, bounds, data, context) {
    var coords, i, j, latitude, longitude, point, scale, xScale, yScale;
    context.fillStyle = '#FF0000';
    coords = void 0;
    point = void 0;
    latitude = void 0;
    longitude = void 0;
    xScale = void 0;
    yScale = void 0;
    scale = void 0;
    xScale = width / Math.abs(bounds.xMax - bounds.xMin);
    yScale = height / Math.abs(bounds.yMax - bounds.yMin);
    scale = xScale < yScale ? xScale : yScale;
    data = data.features;
    i = 0;
    while (i < data.length) {
      coords = data[i].geometry.coordinates[0];
      j = 0;
      while (j < coords.length) {
        longitude = coords[j][0];
        latitude = coords[j][1];
        point = {
          x: (longitude - bounds.xMin) * scale,
          y: (bounds.yMax - latitude) * scale
        };
        if (j === 0) {
          context.beginPath();
          context.moveTo(point.x, point.y);
        } else {
          context.lineTo(point.x, point.y);
        }
        j++;
      }
      context.stroke();
      i++;
    }
  };

  return CanvasDrawer;

})();

thing = new RainThing;

//# sourceMappingURL=script.js.map
