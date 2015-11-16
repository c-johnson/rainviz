var GeoPolygon, RainThing, thing,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

GeoPolygon = (function() {
  function GeoPolygon(coords) {
    this.updateCoords = bind(this.updateCoords, this);
    this.geoJson = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "bounds": [],
          "geometry": {
            "type": "Polygon",
            "coordinates": coords
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
    var bounds, feature, j, lat, len, long, newCoord, ref, ref1, results;
    if (feature = (ref = this.geoJson) != null ? ref.features[ind] : void 0) {
      if ((ref1 = feature.geometry) != null) {
        ref1.coordinates = newCoords;
      }
      feature.bounds = bounds = {};
      results = [];
      for (j = 0, len = newCoords.length; j < len; j++) {
        newCoord = newCoords[j];
        long = newCoord.long;
        lat = newCoord.lat;
        bounds.xMin = bounds.xMin < long ? bounds.xMin : long;
        bounds.xMax = bounds.xMax > long ? bounds.xMax : long;
        bounds.yMin = bounds.yMin < lat ? bounds.yMin : lat;
        results.push(bounds.yMax = bounds.yMax > lat ? bounds.yMax : lat);
      }
      return results;
    }
  };

  GeoPolygon.prototype.updateCoords = function(newCoords, index) {
    var i, j, ref, results;
    if (index) {
      return this.updateFeature(index, newCoords);
    } else {
      results = [];
      for (i = j = 0, ref = this.fLen(); 0 <= ref ? j <= ref : j >= ref; i = 0 <= ref ? ++j : --j) {
        results.push(this.updateFeature(i, newCoords));
      }
      return results;
    }
  };

  return GeoPolygon;

})();

RainThing = (function() {
  function RainThing() {
    this.californication();
  }

  RainThing.prototype.californication = function() {
    return d3.csv('data/cal-boundary.csv', function(data) {
      var div, geoCali, projection;
      geoCali = new GeoPolygon(_.map(data, function(dat) {
        return {
          lat: dat.lat,
          long: dat.long
        };
      }));
      window.Cali = geoCali;
      projection = d3.geo.albersUsa();
      return div = d3.select('#california').append('svg').append("circle").attr("r", 5).attr("transform", function() {
        return "translate(" + projection([-75, 43]) + ")";
      });
    });
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

thing = new RainThing;

//# sourceMappingURL=script.js.map
