# -*- coding: utf-8 -*-
import scrapy

# Javascript psuedocode

# var classSelector = function (className) {
#   return '*[contains(concat(" ", normalize-space(@class), " "), " ' + className + ' ")]';
# }
#
# var delims = [":", ".", "$", ""];
#
# precipData = [];
#
# var arr = $('.center-content pre').text().split('\n');
# arr.splice(0, 3);
# arr = arr.filter(function(item) { return delims.indexOf(item.charAt(0)) === -1 });
# arr.map(function(item) {
#   console.log(JSON.stringify(item));
#   var parts = item.split(" : ");
#   var id = parts[0];
#   var name = parts[1];
#   var rawPrecip = parts[2];
#   precipBuckets = rawPrecip.split("/ ");
#   var precipRow = {
#     id: id,
#     name: name,
#     precip: precipBuckets
#   };
#   precipData.push(precipRow);
#   // console.log("id = " + id + "\nname = " + name + "\nprecip = " + JSON.stringify(precipBuckets))
# });
# copy(precipData);
#
# XPATH version
#
# var classSelector = function (className) {
#   return '*[contains(concat(" ", normalize-space(@class), " "), " ' + className + ' ")]';
# }
#
# $x('//' + classSelector('.center-content')'//pre')[0]

class NoaaSpider(scrapy.Spider):
    name = "noaa"
    allowed_domains = ["www.cnrfc.noaa.gov"]
    start_urls = (
        'http://www.www.cnrfc.noaa.gov/',
    )


    def classSelector(self, className):
        return '*[contains(concat(" ", normalize-space(@class), " "), " ' + className + ' ")]'

    def parse(self, response):
        # selector = self.classSelector("footer")
        xpathStr = '//' + self.classSelector('center-content')'//pre'


        somedict = {}
        some['key'] = 'value'
        somedict = {
            "something": "else",
            "another": []
        }

        pass
