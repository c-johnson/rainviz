# Station sniping code

# var endResult = "";
#
# $('#station_list tr').each(function(index, trdom) {
#
#   var items = [];
#   var firstChild = $(trdom).find('td:nth-child(3)').text();
#   stationNames.push(firstChild);
#   var lat = $(trdom).find('td:nth-child(4)').text();
#   var long = $(trdom).find('td:nth-child(5)').text();
#   items.push([firstChild, lat, long])
#   var result = items.join(",")
#   endResult += result + "\n"
# });
#
# console.log(endResult);
# copy(endResult);

window.noop = ->
window.polygon = (d) ->
  return "M" + d.join("L") + "Z"

class RainThing
  constructor: () ->
    @width = 960
    @height = 1160
    @californication()
    # @usaify()
    # @refugeeChart()
    # @derpyCal()

  # type:  "svg" or "canvas"
  makeDisplay: (type) ->
    display = d3.select("body").append(type)
      .attr("width", @width)
      .attr("height", @height)
      .attr("style", "border: 1px solid black;")

    return display

  makePoint: (id, coord) ->
    {
      "type": "Feature",
      "properties": {
        "GEO_ID": "0400000US06",
        "STATE": "06",
        "NAME": id,
        "LSAD": "",
        "CENSUSAREA": 155779.220000
      },
      "geometry": {
        "type": "Point", "coordinates": coord
      }
    }

  projectLineString: (feature, projection) ->
    line = []
    d3.geo.stream(feature, projection.stream({
      polygonStart: noop
      polygonEnd: noop
      lineStart: noop
      lineEnd: noop
      point: (x, y) -> line.push([x, y])
      sphere: noop
    }))
    return line

  randomizeArea: (d, double) ->
    num1 = Math.abs(d3.geom.polygon(d).area())
    num1 = if double then num1 * 2 else num1
    num2 = Math.random() * 10000
    return (num1 + num2) / 2

  californication: () ->
    svg = @makeDisplay("svg")

    d3.json 'data/USA-california.json', (geoCali) =>
      d3.csv 'data/station-coords.csv', (stationCoords) =>
        fillRed = d3.scale.linear()
          .domain([0, 10000])
          .range(["#fff", "#f00"])

        fillBlue = d3.scale.linear()
          .domain([0, 10000])
          .range(["#fff", "#00f"])

        projection = d3.geo.albersUsa()
          .scale(3500)
          .translate([1600, 400])

        stationCoordinates = stationCoords.map (d) -> return [+d.long, +d.lat]
        caliLineString = @projectLineString(geoCali, projection)
        voronoi = d3.geom.voronoi()

        geoStations = new GeoFeature

        _.each stationCoords, (station) =>
          stationId = "station-" + station.name
          coords = [parseFloat(parseFloat(station.long).toFixed(2)), parseFloat(parseFloat(station.lat).toFixed(2))]
          geoStations.features.push(@makePoint(stationId, coords))

        usaPath = d3.geo.path(geoCali)
          .projection(projection)

        svg.append("path")
            .datum(geoCali)
            .attr("d", usaPath)

        svg.selectAll(".subunit")
            .data(geoCali.features)
          .enter().append("path")
            .attr "class", (d) -> return "subunit-" + d.properties.NAME
            .attr("d", usaPath)

        self = @

        svg.append("g")
            .attr("class", "land")
          .selectAll(".voronoi")
            .data(voronoi(stationCoordinates.map(projection)).map( (d) ->
              # Each voronoi region is a convex polygon, therefore we can use
              # d3.geom.polygon.clip, treating each regino as a clip region, with the
              # projected “exterior” as a subject polygon.
              return d3.geom.polygon(d).clip(caliLineString.slice())
            ))
          .enter().append("path")
            .attr("class", "voronoi")
            .style "fill", (d) ->
              d.initialArea = self.randomizeArea(d,false)
              return fillBlue(d.initialArea)
            .attr("d", polygon)
            .on 'mouseenter', (d) ->
              this.style.fill = fillBlue(self.randomizeArea(d,true))
            .on 'mouseleave', (d) ->
              this.style.fill = fillBlue(d.initialArea)

  usaify: () ->
    svg = @makeDisplay("svg")

    d3.json 'data/USA-states.json', (geoUSA) =>

      projection = d3.geo.albersUsa()
        .scale(1000)
        .translate([@width / 2, @height / 2])

      usaPath = d3.geo.path(geoUSA)
        .projection(projection)

      svg.append("path")
          .datum(geoUSA)
          .attr("d", usaPath)

      svg.selectAll(".subunit")
          .data(geoUSA.features)
        .enter().append("path")
          .attr "class", (d) -> return "subunit-" + d.properties.NAME
          .attr("d", usaPath)
          .on 'mouseenter', (feature) ->
            this.style.fill = "blue"
          .on 'mouseleave', (feature) ->
            this.style.fill = ""

  derpyCal: () ->
    d3.csv 'data/cal-boundary.csv', (data) =>
      canvas = @makeDisplay("canvas")
      geoCali = new GeoPolygon(_.map data, (dat) -> [parseFloat(dat.lat), parseFloat(dat.long)])
      window.Cali = geoCali
      gJson = geoCali.geoJson

      projection = d3.geo.albersUsa()
        .scale(1000)

      context = canvas.node().getContext("2d")

      caliPath = d3.geo.path()
        .projection(projection)
        .context(context)

      gJson.bbox = gJson.features[0].bbox = gJson.bounds

      caliPath(topojson.feature(gJson, gJson.features[0]))

      drawer = new CanvasDrawer
      drawer.drawCanvasThing(960, 500, gJson.bbox, gJson, context)

  refugeeChart: () ->
    d3.csv 'data/chart.csv', (data) ->
      refugeeMax = data[data.length - 1].numRefugees
      refugeeMin = data[0].numRefugees
      div = d3.select('.the-data').append('div').attr('class', 'tooltip').style('opacity', 0)
      d3.select('.the-data').selectAll('div').data(data).enter().append('div').classed 'data-row', true
      d3.selectAll('.data-row').append('div').classed('bar', true).style('background-color', (d) ->
        if d.numRefugees <= 100000
          return 'green'
        else if d.numRefugees > 100000 and d.numRefugees <= 500000
          return 'yellow'
        else if d.numRefugees > 500000 and d.numRefugees <= 2000000
          return 'orange'
        else if d.numRefugees > 2000000
          return 'red'
        return
      ).style('height', (d) ->
        percent = d.numRefugees / refugeeMax
        barHeight = percent * 250
        barHeight + 10 + 'px'
      ).on('mouseover', (d) ->
        div.transition().duration(0).style 'opacity', .9
        div.html(d.numRefugees + '<br/>' + 'refugees').style('left', d3.event.pageX + 'px').style 'top', d3.event.pageY - 28 + 'px'
        return
      ).on 'mouseout', (d) ->
        div.transition().duration(0).style 'opacity', 0
        return
      d3.selectAll('.data-row').append('p').classed('label', true).text (data) ->
        data.date
      return
    console.log 'you are now rocking with d3', d3

class GeoFeature
  constructor: () ->
    @type = "FeatureCollection"
    @features = []

class GeoPolygon
  constructor: (coords) ->
    @geoJson =
      "type": "FeatureCollection"
      "bbox": []
      "features": [{
        "type": "Feature"
        "bbox": []
        "geometry":
          "type": "Polygon"
          "coordinates": [coords]
    }]

    @updateCoords(coords)

  fLen: () ->
    return @geoJson?.features?.length

  updateFeature: (ind, newCoords) ->
    if feature = @geoJson?.features[ind]
      feature.geometry?.coordinates = [newCoords]
      @geoJson.bounds = bounds = [[], []]
                        #left, top, right, bottom
      # @geoJson.bounds = [[10, 10], [50, 80]]

      for newCoord in newCoords
        long = newCoord[0]
        lat = newCoord[1]

        bounds[0][0] = bounds.xMin = if bounds.xMin < long then bounds.xMin else long
        bounds[1][0] = bounds.xMax = if bounds.xMax > long then bounds.xMax else long
        bounds[1][1] = bounds.yMin = if bounds.yMin < lat then bounds.yMin else lat
        bounds[0][1] = bounds.yMax = if bounds.yMax > lat then bounds.yMax else lat

  updateCoords: (newCoords, index) =>
    if newCoords
      if index then @updateFeature(index, newCoords)
      else
        for i in [0..@fLen()]
          @updateFeature(i, newCoords)

class CanvasDrawer
  drawCanvasThing: (width, height, bounds, data, context) ->
    context.fillStyle = '#FF0000'
    coords = undefined
    point = undefined
    latitude = undefined
    longitude = undefined
    xScale = undefined
    yScale = undefined
    scale = undefined
    xScale = width / Math.abs(bounds.xMax - (bounds.xMin))
    yScale = height / Math.abs(bounds.yMax - (bounds.yMin))
    scale = if xScale < yScale then xScale else yScale
    # Again, we want to use the “features” key of
    # the FeatureCollection
    data = data.features
    # Loop over the features…
    i = 0
    while i < data.length
      # …pulling out the coordinates…
      coords = data[i].geometry.coordinates[0]
      # …and for each coordinate…
      j = 0
      while j < coords.length
        longitude = coords[j][0]
        latitude = coords[j][1]
        # Scale the points of the coordinate
        # to fit inside our bounding box
        point =
          x: (longitude - (bounds.xMin)) * scale
          y: (bounds.yMax - latitude) * scale
        # If this is the first coordinate in a shape, start a new path
        if j == 0
          context.beginPath()
          context.moveTo point.x, point.y
          # Otherwise just keep drawing
        else
          context.lineTo point.x, point.y
        j++
      # Fill the path we just finished drawing with color
      context.stroke()
      i++
    return

thing = new RainThing
