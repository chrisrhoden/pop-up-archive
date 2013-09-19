angular.module('Directory.collections.controllers', ['Directory.loader', 'Directory.user', 'Directory.collections.models', 'ngTutorial'])
.controller('CollectionsCtrl', ['$scope', '$modal', 'Collection', 'Loader', 'Me', 'Tutorial', function CollectionsCtrl($scope, $modal, Collection, Loader, Me, Tutorial) {

  Me.authenticated(function (me) {
    Loader.page(Collection.query(), Collection.get(me.uploadsCollectionId), 'Collections', $scope).then(function (data) {
      $scope.collection = undefined;
      $scope.uploadsCollection = data[1];
      $scope.uploadsCollection.fetchItems();
    });

    $scope.usedQuota = me.usedQuota;
    $scope.totalQuota = 900000;

    $scope.quotaPercent = function () {
      return Math.ceil(this.usedQuota * 100 / this.totalQuota) + '%';
    }

		$scope.tour = {
      'tempuploads': { 
        'content': 'If you don\'t specify a collection, audio will be automatically added to temporary uploads. Select your audio and add it to a collection to make it searchable.',
        'step': 0
      },
		  'iapublic': { 
				'content': 'Your public collections will be<br/>stored at the Internet Archive.<br/>They will be available for anyone<br/>to search, stream, or download.',
        'step': 1
			},
		  's3private': { 
				'content': 'Private collections allow you to store your audio so that is visible only to you. Users automatically have two hours of private storage.',
        'step': 2
			},
			'edit': { 
				'content': 'Use batch edit to delete or edit tags for many items at once.',
        'step': 3
			},
      'tutorial1': {
        'content': 'Hopefully collections are making more sense.<br/>Next let\'s look at uploading.',
        'step': 4
      },
      'tutorial2': {
        'content': 'Uploads are just a click or drag &amp; drop away &ndash; give it a try!',
        'step': 5
      }
		};

    $scope.$on('tutorial-step-shown', function (event) {
      if (event.targetScope.stepOptions) {
        var step = event.targetScope.stepOptions.step;
        switch (step) {
          case 4: $modal({template: "/assets/collections/tutorial1.html", persist: false, show: true, backdrop: 'static', scope: $scope, modalClass: 'big-modal'}); break;
          case 5: $modal({template: "/assets/collections/tutorial2.html", persist: false, show: true, backdrop: 'static', scope: $scope, modalClass: 'big-modal'}); break;
        }
      }
    });
		
    $scope.selectedItems = [];

    $scope.$watch('uploadsCollection.items', function (is) {
      if (angular.isArray(is)) {
        angular.forEach(is, function (item) {
          if (item.selected && $scope.selectedItems.indexOf(item) == -1) {
            $scope.selectedItems.push(item);
          }
        });
      }
    }, true);

    $scope.toggleItemSelection = function (item) {
      if (item.selected) {
        item.selected = false;
        if ($scope.selectedItems.indexOf(item) != -1) {
          $scope.selectedItems.splice($scope.selectedItems.indexOf(item), 1);
        }
      } else {
        item.selected = true;
        if ($scope.selectedItems.indexOf(item) == -1) {
          $scope.selectedItems.push(item);
        }
      }
    }

    $scope.selectAll = function (items) {
      angular.forEach(items, function (item) {
        if (!item.selected) {
          $scope.toggleItemSelection(item);
        }
      });
    }

    $scope.deleteSelection = function () {
      if (confirm("Are you sure you would like to delete these " + $scope.selectedItems.length + " items from My Uploads?\n\nThis is permanent and cannot be undone.")) {
        angular.forEach($scope.selectedItems, function (item) {
          item.delete();
          if ($scope.uploadsCollection.items.indexOf(item) !== -1) {
            $scope.uploadsCollection.items.splice($scope.uploadsCollection.items.indexOf(item), 1);
          }
        });
        $scope.selectedItems.length = 0;
      }
    }

    $scope.clearSelection = function () {
      angular.forEach($scope.selectedItems, function (item) {
        item.selected = false;
      })
      $scope.selectedItems.length = 0;
    }

    $scope.delete = function(index) {
      var confirmed = confirm("Delete collection and all items?");
      if (!confirmed) {
        return false;
      }

      var collection = $scope.collections[index];
      collection.deleting = true;
      collection.delete().then(function() {
        $scope.collections.splice(index, 1);
      });
    }
  });
}])
.controller('CollectionCtrl', ['$scope', '$routeParams', 'Collection', 'Loader', 'Item', '$location', '$timeout', function CollectionCtrl($scope, $routeParams, Collection, Loader, Item, $location, $timeout) {
  $scope.canEdit = false;

  Loader.page(Collection.get($routeParams.collectionId), Collection.query(), 'Collection/' + $routeParams.collectionId,  $scope).then(function () {
    angular.forEach($scope.collections, function (collection) {
      if (collection.id == $scope.collection.id) {
        $scope.canEdit = true;
      }
    });
  });

  $scope.edit = function () {
    $scope.editItem = true;
  }

  $scope.close = function () {
    $scope.editItem = false;
    $scope.item = new Item({collectionId:parseInt($routeParams.collectionId)});
  }

  $scope.delete = function () {
    if (confirm("Are you sure you want to delete the collection " + $scope.collection.title + " and all items it contains?\n\n This cannot be undone.")) {
      $scope.collection.delete().then(function () {
        $location.path('/collections');
      })
    }
  }

  $scope.close();

  $scope.hasFilters = false;
}])
.controller('PublicCollectionsCtrl', ['$scope', 'Collection', 'Loader', function PublicCollectionsCtrl($scope, Collection, Loader) {
  $scope.collections = Loader(Collection.public());
}])
.controller('CollectionFormCtrl', ['$scope', 'Collection', 'Me', function CollectionFormCtrl($scope, Collection, Me) {

  $scope.edit = function (collection) {
    $scope.collection = collection;
  }

  $scope.submit = function() {

    // make sure this is a resource object.
    var collection = new Collection($scope.collection);

    if (collection.id) {
      collection.update();
    } else {
      collection.create().then(function (data) {
        $scope.collections.push(collection);
        Me.authenticated(function (me) {
          me.collectionIds.push(data.id);
        });
      });
    }
  }
}])
.controller('UploadCategorizationCtrl', ['$scope', function($scope) {
  var dismiss = $scope.dismiss;

  var currentCollection;

  $scope.$watch('collections', function (is, was) {
    if (typeof is !== 'undefined') {
      for (var i=0; i < $scope.collections.length; i++) {
        if ($scope.collections[i].id != $scope.currentUser.uploadsCollectionId) {
          $scope.selectedItems.collectionId = $scope.collections[i].id;
          break;
        }
      }
    }
  });

  $scope.$watch('selectedItems.collectionId', function (is) {
    if (typeof is !== 'undefined') {
      for (var i=0; i < $scope.collections.length; i++) {
        if ($scope.collections[i].id == is) {
          currentCollection = $scope.collections[i];
          break;
        }
      }
    }
  })


  $scope.dismiss = function () {
    $scope.clearSelection();
    dismiss();
  }

  $scope.submit = function () {
    angular.forEach($scope.selectedItems, function (item) {
      item.adopt($scope.selectedItems.collectionId);
      $scope.uploadsCollection.items.splice($scope.uploadsCollection.items.indexOf(item), 1);
      if (currentCollection && currentCollection.items && currentCollection.items.push)
        curcurrentCollection.items.push(item);
    });
    $scope.dismiss();
  }
}])
.controller('NewPublicCollectionCtrl', ['$scope', 'Collection', function ($scope, Collection) {
  $scope.collection = new Collection({itemsVisibleByDefault: true});
}])
.controller('NewPrivateCollectionCtrl', ['$scope', 'Collection', function ($scope, Collection) {
  $scope.collection = new Collection({itemsVisibleByDefault: false});
}])
.controller('BatchEditCtrl', ['$scope', 'Loader', 'Collection', 'Me', function ($scope, Loader, Collection, Me) {
  Me.authenticated(function (currentUser) {
    Loader.page(Collection.query(), 'BatchEdit', $scope).then(function (collections) {
      angular.forEach(collections, function (collection) {
        collection.fetchItems();
      });
    });
  });

  $scope.selected = {};

  $scope.selectedItems = [];
  $scope.selected.tags = [];

  $scope.sortType = 0;

  var itemsByMonth = {};
  var logged = false;

  $scope.$watch(function () {
    var items = [];
    if ($scope.collections) {
      angular.forEach($scope.collections, function (collection) {
        if (collection.items) {
          items.push.apply(items, collection.items);
        }
      });
    }
    return items;
  }, function (is) {
    $scope.itemsByMonth = {};
    $scope.itemsByCollection = {};
    $scope.selectedItems.length = 0;
    if (is.length) {

      angular.forEach($scope.collections, function (collection) {
        if (collection.items && collection.items.length)
          $scope.itemsByCollection[collection.id] = {name: collection.title, items: collection.items};
      });

      var date, month, year, string;

      angular.forEach(is, function (item) {
        if (item.selected && $scope.selectedItems.indexOf(item) == -1) {
          $scope.selectedItems.push(item);
        }

        item.__dateHash = item.__dateHash || getDateHashForItem(item);
        $scope.itemsByMonth[item.__dateHash] = $scope.itemsByMonth[item.__dateHash] || {name: dateString(item.__dateHash), items: []};
        $scope.itemsByMonth[item.__dateHash].items.push(item);
      });
    }
  }, true);

  $scope.$watch('selectedItems', function (is) {
    $scope.selected.tags.length = 0;
    if (is.length) {
      var tagSet = {};
      angular.forEach(is, function (selectedItem) {
        angular.forEach(selectedItem.tags, function (tag) {
          tagSet[tag] = 1;
        });
      });
      $scope.selected.tags.push.apply($scope.selected.tags, Object.keys(tagSet).map(function (tag) {
        return { text: tag, id: tag };
      }));
    }
  }, true);

  function getDateHashForItem(item) {
    date = new Date(item.dateAdded);
    month = date.getUTCMonth();
    year  = date.getUTCFullYear();
    return 1000000 - (year * 100 + month);
  }

  function dateString (dateHash) {
    dateHash = 1000000 - dateHash;

    var year = Math.floor(dateHash / 100);
    var month = dateHash - (year * 100);

    var string;

    switch (month) {
      case 0: string = "January"; break;
      case 1: string = "February"; break;
      case 2: string = "March"; break;
      case 3: string = "April"; break;
      case 4: string = "May"; break;
      case 5: string = "June"; break;
      case 6: string = "July"; break;
      case 7: string = "August"; break;
      case 8: string = "September"; break;
      case 9: string = "October"; break;
      case 10: string = "November"; break;
      case 11: string = "December"; break;
      default: string = "chris"; break;
    }

    return string + ", " + year;
  }

  $scope.sortedItems = function () {
    if ($scope.sortType) {
      return $scope.itemsByCollection;
    } else {
      return $scope.itemsByMonth;
    }
  }

  $scope.toggleItemSelection = function (item) {
    if (item.selected) {
      item.selected = false;
      if ($scope.selectedItems.indexOf(item) != -1) {
        $scope.selectedItems.splice($scope.selectedItems.indexOf(item), 1);
      }
    } else {
      item.selected = true;
      if ($scope.selectedItems.indexOf(item) == -1) {
        $scope.selectedItems.push(item);
      }
    }
  };

  $scope.tagSelect = {
    placeholder: 'Tags...',
    width: '220px',
    tags: []
  };

  $scope.submit = function () {
    var actualTags = [];
    angular.forEach($scope.selected.tags, function (tag) {
      actualTags.push(tag.text);
    });

    angular.forEach($scope.selectedItems, function (item) {
      item.tags = actualTags;
      item.update();
    });
    $scope.clearSelection();
  }

  $scope.clearSelection = function () {
    angular.forEach($scope.selectedItems, function (item) {
      item.selected = false;
    })
    $scope.selectedItems.length = 0;
  };

  $scope.deleteSelection = function () {
    if (confirm("Are you sure you would like to delete these " + $scope.selectedItems.length + " items from My Uploads?\n\nThis is permanent and cannot be undone.")) {
      angular.forEach($scope.selectedItems, function (item) {
        item.delete();
        item.getCollection().items.splice(item.getCollection().items.indexOf(item), 1);
      });
      $scope.selectedItems.length = 0;
    }
  };
}]);
