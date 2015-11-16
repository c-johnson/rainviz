class RainThing
  constructor: () ->
    @californication(new CanvasDrawer)
    # @refugeeChart()

  californication: (drawer) ->
    d3.csv 'data/cal-boundary.csv', (data) ->
      width = 960
      height = 500

      canvas = d3.select("body").append("canvas")
        .attr("width", width)
        .attr("height", height)

      geoCali = new GeoPolygon(_.map data, (dat) -> {lat: parseFloat(dat.lat), long: parseFloat(dat.long)})
      window.Cali = geoCali
      gJson = geoCali.geoJson

      projection = d3.geo.albers()
        .scale(1000)

      context = canvas.node().getContext("2d")

      caliPath = d3.geo.path(gJson.features[0])
        .projection(projection)
        .context(context)

      gJson.features[0].bbox = gJson.bounds
      caliPath(topojson.feature(gJson, gJson.features[0]))

      # caliPath(topojson.feature(us, us.objects.counties));
      context.stroke()

      # b_canvas = document.getElementById("calicanvas")
      # b_context = b_canvas.getContext("2d");
      # b_context.fillRect(50, 25, 150, 100);

      # caliPath.bounds(geoCali.geoJson.bounds);
      # caliPath.projection(d3.geo.albersUsa());
      # caliPath.context(b_context);

      # drawer.drawCanvasThing(500, 500, geoCali.geoJson.bounds, geoCali.geoJson)

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

class GeoPolygon
  constructor: (coords) ->
    @geoJson =
      "type": "FeatureCollection"
      "features": [{
        "type": "Feature"
        "bounds": []
        "geometry":
          "type": "Polygon"
          "coordinates": coords
    }]

    @updateCoords(coords)

  fLen: () ->
    return @geoJson?.features?.length

  updateFeature: (ind, newCoords) ->
    if feature = @geoJson?.features[ind]
      feature.geometry?.coordinates = newCoords
      @geoJson.bounds = bounds = [[], []]
                        #left, top, right, bottom
      # @geoJson.bounds = [[10, 10], [50, 80]]

      for newCoord in newCoords
        long = newCoord.long
        lat = newCoord.lat

        bounds[0][0] = bounds.xMin = if bounds.xMin < long then bounds.xMin else long
        bounds[1][0] = bounds.xMax = if bounds.xMax > long then bounds.xMax else long
        bounds[1][1] = bounds.yMin = if bounds.yMin < lat then bounds.yMin else lat
        bounds[0][1] = bounds.yMax = if bounds.yMax > lat then bounds.yMax else lat

  updateCoords: (newCoords, index) =>
    if index then @updateFeature(index, newCoords)
    else
      for i in [0..@fLen()]
        @updateFeature(i, newCoords)

class CanvasDrawer
  constructor: () ->
    @canvas = document.createElement('canvas')
    @context = @canvas.getContext("2d")

  drawCanvasThing: (width, height, bounds, data) ->
    canvas = @canvas
    context = undefined
    coords = undefined
    point = undefined
    latitude = undefined
    longitude = undefined
    xScale = undefined
    yScale = undefined
    scale = undefined
    # Get the drawing context from our <canvas> and
    # set the fill to determine what color our map will be.
    context = canvas.getContext('2d')
    context.fillStyle = '#333'
    # Determine how much to scale our coordinates by
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
          @context.beginPath()
          @context.moveTo point.x, point.y
          # Otherwise just keep drawing
        else
          @context.lineTo point.x, point.y
        j++
      # Fill the path we just finished drawing with color
      @context.fill()
      i++
    return

thing = new RainThing
