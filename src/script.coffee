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
      feature.bounds = bounds = {}

      for newCoord in newCoords
        long = newCoord.long
        lat = newCoord.lat

        bounds.xMin = if bounds.xMin < long then bounds.xMin else long
        bounds.xMax = if bounds.xMax > long then bounds.xMax else long
        bounds.yMin = if bounds.yMin < lat then bounds.yMin else lat
        bounds.yMax = if bounds.yMax > lat then bounds.yMax else lat

  updateCoords: (newCoords, index) =>
    if index then @updateFeature(index, newCoords)
    else
      for i in [0..@fLen()]
        @updateFeature(i, newCoords)

class RainThing
  constructor: () ->
    @californication()
    # @refugeeChart()

  californication: () ->
    d3.csv 'data/cal-boundary.csv', (data) ->
      geoCali = new GeoPolygon(_.map data, (dat) -> {lat: dat.lat, long: dat.long})

      window.Cali = geoCali

      projection = d3.geo.albersUsa()
      div = d3.select('#california').append('svg').append("circle").attr("r",5).attr("transform", () -> return "translate(" + projection([-75,43]) + ")";)

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

thing = new RainThing
