(function() {
  'use strict';

  var search = angular.module('prxSearch', ['Directory.searches.models', 'Directory.items.models']);

  search.factory('SearchResults', ['Search', 'Item', '$q', function (Search, Item, $q) {
    var Results = {
      length: 0,
      query: undefined,
      currentIndex: 0
    };


    var loadings = {};
    var data = [];

    Results.setResults = function setResults(results) {
      if (results) {
        if (Results.query != results.query || Results.length != results.totalHits) {
          data.length = 0;
          Results.currentIndex = 0;
          Results.length = results.totalHits;
          Results.query = results.query;
        }
        var offset = ((results.page -1) * 25);
        angular.forEach(results.results, function (result, index) {
          data[index + offset] = new Item(result);
        });
      } else {
        Results.length = 0;
        Results.query = undefined;
        Results.currentIndex = 0;
        data.length = 0;
      }
    }

    Results.link = function () {
      var url = ['/search'];
      var params = [];

      if (Results.query) {
        params.push("query=" + Results.query);
      }

      var page = Math.ceil((Results.currentIndex + 1)/ 25);
      if (page > 1) {
        params.push("page=" + page);
      }

      params = params.join('&');

      if (params.length) {
        url.push(params);
      }

      return url.join('?');
    }

    Results.setCurrentIndex = function (requirements) {
      var set = false;
      angular.forEach(data, function (object, index) {
        if (!set) {
          var match = true;
          angular.forEach(requirements, function (value, key) {
            if (object[key] != value) {
              match = false;
            }
          });
          if (match) {
            set = true;
            Results.currentIndex = index;
          }
        }
      });
      if (!set) {
        Results.setResults();
      }
    }

    Results.getItem = function getItem(index) {
      if (index >= Results.length || index < 0) {
        return $q.reject();
      }
      if (typeof data[index] === 'undefined') {
        var page = Math.ceil((index + 1)/ 25);
        var deferred = $q.defer();
        data[index] = deferred.promise;

        if (typeof loadings[page] === 'undefined') {
          loadings[page] = Search.query({page: page, query: Results.query}).then(function(r){
            Results.setResults(r);
            loadings[page] = undefined;
          });
        }

        loadings[page] = loadings[page].then(function (){
          $q.when(data[index]).then(function (r) {
            deferred.resolve(r);
          }, function (e) {
            deferred.reject(e);
          });
        });
      }
      return data[index];
    }

    return Results;
  }]);

})();