/*
 * jQuery listy plugin 6.00
 *
 * (c)opyright 2011-2022 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */
"use strict";
(function($) {

  /***************************************************************************
   * globals
   */
  var defaults = {
    debug: false,
    updateWidth: true
  },
  saveInProgress;

  /***************************************************************************
   * class definition
   */
  function Listy(elem, opts) {
    var self = this;

    self.elem = $(elem);
    self.affected = {};
    self.opts = $.extend({}, defaults, opts, self.elem.data());
    if (typeof self.opts.allCollections === "string") {
      self.opts.allCollections = self.opts.allCollections.split(/\s*,\s*/);
    }
    self.init();

    //self.log("finished new()", self);
  }

  /***************************************************************************
   * logging
   */
  Listy.prototype.log = function() {
    var self = this, args;

    if (typeof(console) !== 'undefined' && self.opts.debug) {
      args = $.makeArray(arguments);
      args.unshift("LISTY: ");
      console.log.apply(self, args); // eslint-disable-line no-console
    }
  };

  /*************************************************************************
   * calls a notification systems, defaults to pnotify
   */
  Listy.prototype.showMessage = function(type, msg, title) {
    $.pnotify({
      title: title,
      text: msg,
      hide: (type === "error" ? false : true),
      type: type,
      sticker: false,
      closer_hover: false,
      delay: (type === "error" ? 8000 : 2000)
    });
  };

  /*************************************************************************
   * hide all open error messages in the notification system
   */
  Listy.prototype.hideMessages = function() {
    $.pnotify_remove_all();
  };


  /***************************************************************************
   * init listy instance
   */
  Listy.prototype.init = function() {
    var self = this, html;

    // attach to dom
    self.id = self.elem.attr("id");
    self.addButton = self.elem.find(".jqListyAdd");
    self.revertButton = self.elem.find(".jqListyRevert");
    self.saveButton = self.elem.find(".jqListySave");
    try {
      html = self.elem.find(".jqListyParams").html();
      if (html) {
        self.listyParams = JSON.parse(html);
      }
    } catch (error) {
      console.error("failed to parse json listy params",html);
      //console.error(error);
    };

    self.listyContainer = self.elem.find(".jqListyContainer");

    // bind internal functions to events
    self.elem.on("refresh.listy", function() {
      self.updateWidth();
    });

    self.elem.on("reload.listy", function() {
      self.reload();
    });

    self.elem.on("save.listy", function() {
      self.save();
    });

    self.elem.on("modified.listy", function() {
      self.flagModified();
    });

    $(document).on("changedCollection", function(ev, data) {
      if (data.source === self.opts.source && 
          data.collection === self.opts.collection) {

        self.log("got a changedCollection event with data=",data);
        self.flagModified();
        self.reload();
      }
    });

    // init gui
    self.listyContainer.sortable({
      connectWith: ".jqListyEditable .jqListyContainer",
      //revert: true, /* SMELL: buggy - when the page scrolled the placeholder animates to a weird position */
      distance: 5,
      tolerance: "pointer",
      placeholder: "ui-sortable-placeholder jqListyPlaceholder",
      forcePlaceholderSize: true,
      cursor: "move",
      //cursorAt : {"top": -16, "left": -16},
      //cursorAt : {"top": 0, "left": 0},

      start: function(event, ui) {
        var $item = $(ui.item),
            $placeholder = $(ui.placeholder),
            height = $item.height();
        self.log("got a start in ", self.id);
        $placeholder.height(height);
        $item.addClass("jqListySelected");
      },

      remove: function(/*event, ui*/) {
        self.log("got a remove in " + self.id);
      },

      receive: function(event, ui) {
        var sender = ui.sender.parent().data("listy");

        self.log("got a receive in ", self.id);

        if (self.isEqual(sender)) {

          sender.listyContainer.sortable("cancel");
          sender.updateModified();

          self.listyContainer.sortable("cancel");
          self.updateModified();

          self.showMessage("notice", $.i18n("sorry, can't drop elements here"));
          return;
        }

        // add remember the other editor
        self.affected[sender.id] = sender;

        // add me to the other's notification list
        sender.affected[self.id] = self;

        //self.log("affected=", self.affected);
      },

      update: function(event, ui) {
        var sender = ui.sender;

        if (sender) {
          sender = sender.parent().data("listy");
          self.log("got an update to ", self.id,"from ",sender.id);
        } else {
          self.log("got an update to ", self.id);
        }

        //self.log(self.listyContainer.sortable("toArray"));
        //self.log("ui=",ui);

        self.updateModified();
        if (self.opts.autoSave) {
          //self.log("saving ",self.id);
          self.save().then(function() {
            var data, md5, senderMd5;
            if (sender) {
              self.reload(); 
              // check whether we need to reload this listy
/*
              data = self.getItemData(ui.item.attr("id"));
              self.log("save initiated by sender ...",sender.id);
              md5 = self.elem.data("formatterMd5")[data.type];
              senderMd5 = sender.elem.data("formatterMd5")[data.type];
              if (md5 !== senderMd5) {
                self.log("need to reload",self.id);
                self.reload(true);
              } else {
                self.log("no need to reload a listy ... same formatter");
              }
*/
            }
          });
        }
      },

      stop: function(event, ui) {
        var $item = $(ui.item);

        //self.log("got a stop in ", self.id);

        $item.removeClass("jqListySelected");
      }
    }).disableSelection();

    // remember initial sorting
    self.initialSorting = self.listyContainer.sortable("toArray").join(",");

    // remember width
    self.updateWidth();

    // process list elements
    var $toolsTemplate = self.elem.find(".jqListyItemTools");
    self.listyContainer.children("li").each(function() {
      var $item = $(this),
          $tools = $toolsTemplate.clone().appendTo($item);

      $item.hoverIntent({
        over: function() {
          $tools.fadeIn(500, function() {
            $tools.css({
              opacity: 1.0
            });
          });
        },
        out: function() {
          $tools.stop();
          $tools.css({
            display: "none",
            opacity: 1.0
          });
        }
      });
    });

    // revert button behavior
    self.revertButton.on("click", function() {
      self.reload();
      return false;
    });

    // save button behavior
    self.saveButton.on("click", function() {
      self.save();
      return false;
    });

    // delete button behavior
    self.elem.find(".jqListyDelete").on("click", function() {
      var $this = $(this),
        $item = $this.parents("li:first"),
        name = $item.attr("id"),
        data = self.getItemData(name);

      self.dialog({
        name: "listy::confirmdelete",
        title: $.i18n("Delete Listy Item"),
        data: {
          name: name,
          title: data.title || data.topic || data.url,
          source: self.opts.source,
          collection: self.opts.collection
        }
      }).then(
        function(dialog) {
          $(dialog).children("form").ajaxSubmit({
            beforeSubmit: function() {
              if (!self.elem.data("blockUI.isBlocked")) {
                self.elem.block({message:''});
              }
            },
            success: function() {
              //self.showMessage("info", "deleted item");
              $(document).trigger("changedCollection", {
                source: self.opts.source,
                collection: self.opts.collection,
                web: data.web,
                topic: data.topic,
                action: "delete"
              });

              self.flagModified();
              self.reload();
            },
            error: function(xhr) {
              var msg = JSON.parse(xhr.responseText).error.message;
              self.elem.unblock();
              self.showMessage("error", msg);
            }
          });
        }
      );

      return false;
    });

    // edit button behavior
    var _editHandler = function($item) {
      var name = $item.attr("id"),
          data = self.getItemData(name),
          url = foswiki.getScriptUrl("rest", "JQueryPlugin", "tmpl", {
            load: "listyplugin",
            showcollections: self.opts.showCollections,
            topic: foswiki.getPreference("WEB") + "." + foswiki.getPreference("TOPIC"),
          });

      self.dialog({
        url: url,
        name: "listy::edititem",
        data: {
          collection: self.opts.collection,
          allCollections: self.opts.allCollections,
          name: name,
          source: self.opts.source,
          summary: data.summary,
          title: data.title,
          web: data.web,
          topic: data.topic,
          url: data.url,
          type: data.type
        },
        methods: {
          renderCollections: function() {
            return self.renderCollections();
          }
        }
        
      }).then(
        function(dialog) {
          $(dialog).children("form").ajaxSubmit({
            beforeSubmit: function() {
              if (!self.elem.data("blockUI.isBlocked")) {
                self.elem.block({message:''});
              }
            },
            success: function(/*json*/) {
              $(document).trigger("changedCollection", {
                source: self.opts.source,
                collection: self.opts.collection,
                web: data.web,
                topic: data.topic,
                action: "edit"
              });

              //self.flagModified();
              //self.reload();
            },
            error: function(xhr) {
              var msg = JSON.parse(xhr.responseText).error.message;
              self.elem.unblock();
              self.showMessage("error", msg);
            }
          });
        }
      );

      return false;
    };

    self.elem.find(".jqListyEdit").on("click", function() {
      var $this = $(this), $item = $this.parents("li:first");
      _editHandler($item);
      return false;
    }).each(function() {
      var $this = $(this);
      $this.parent().parent().on("dblclick", function() {
        _editHandler($(this));
        return false;
      });
    });

    // add button behavior
    self.addButton.add(self.elem.find(".jqListyAddHere")).on("click", function() {
      var $this = $(this), 
        $thisItem = $this.parents("li:first"),
        $nextItem = $this.parents("li:first").next("li:first"),
        thisIndex, nextIndex,
        index = "";

      if ($thisItem.length) {
        thisIndex = self.getItemData($thisItem.attr("id")).index - 1;
        if ($nextItem.length) {
          nextIndex = 
          nextIndex = self.getItemData($nextItem.attr("id")).index - 1;
        } else {
          nextIndex = thisIndex + 2;
        }
        index = (nextIndex - thisIndex) / 2 + thisIndex;
      } else {
        if ($this.is(".top")) {
          $thisItem = self.listyContainer.find("> li:first");
          if ($thisItem.length) {
          thisIndex = self.getItemData($thisItem.attr("id")).index;
          index = thisIndex-1;
          }
        }
      }

      self.dialog({
        url: foswiki.getScriptUrl("rest", "JQueryPlugin", "tmpl", {
          load: "listyplugin",
          showcollections: self.opts.showCollections,
          types: self.opts.itemTypes,
          topic: foswiki.getPreference("WEB")+"."+foswiki.getPreference("TOPIC")
        }),
        name: "listy::additem",
        data: {
          collection: self.opts.collection,
          allCollections: self.opts.allCollections,
          source: self.opts.source,
          summary: "",
          title: "",
          web: foswiki.getPreference("WEB"),
          topic: "",
          url: "",
          index: index
        },
        methods: {
          renderCollections: function() {
            return self.renderCollections();
          }
        }
        
      }).then(
        function(dialog) {
          $(dialog).children("form").ajaxSubmit({
            success: function(/*json*/) {

              $(document).trigger("changedCollection", {
                source: self.opts.source,
                collection: self.opts.collection,
                web: foswiki.getPreference("WEB"),
                topic: foswiki.getPreference("TOPIC"),
                action: "add"
              });

              //self.flagModified();
              //self.reload();
            },
            error: function(xhr) {
              var msg = JSON.parse(xhr.responseText).error.message;
              self.showMessage("error", msg);
            }
          });
        }
      );
      
      return false;
    });

  };

  /***************************************************************************
   * get data of a listy item
   */
  Listy.prototype.getItemData = function(name) {
    var self = this,
        data = {};

    self.elem.find("#"+name+" .jqListyData").each(function() {
      data = $.extend(data, JSON.parse($(this).html()));
    });

    if (typeof(data[name]) === 'undefined') {
      return {};
    }
/*
    $.each(data[name], function(key, val) {
      data[name][key] = decodeURIComponent(val).replace(/["&<>]/g, function(i) {
        return '&#' + i.charCodeAt(0) + ';';
      });
    });
*/

    return data[name];
  };


  /***************************************************************************
   * update the object's modified state
   */
  Listy.prototype.updateModified = function() {
    var self = this;

    if (self.isModified()) {
      self.flagModified();
    } else {
      self.unflagModified();
    }
  };

  /***************************************************************************
   * returns an option list of available collections
   */
  Listy.prototype.renderCollections = function() {
    var self = this,
        lines = [];

    $.each(self.opts.allCollections, function(index, elem) {
      lines.push("<label><input type='radio' class='foswikiRadio' name='collection' value='"+elem+"' "+(elem === self.opts.collection ? "checked" : "")+">"+elem+"</label>");
    });

    return lines.join("\n");
  };

  /***************************************************************************
   * test the object as being modified
   */
  Listy.prototype.isModified = function() {
    var self = this;

    return (self.initialSorting !== self.listyContainer.sortable("toArray").join(","));
  };

  /***************************************************************************
   * flag the object as being modified
   */
  Listy.prototype.flagModified = function() {
    var self = this;

    self.modified = true;
    if (!self.opts.autoSave) {
      self.saveButton.show();
      self.revertButton.show();
      self.addButton.hide();
      self.updateWidth();
    }
  };

  /***************************************************************************
   * updates the min-width property for the listy element
   */
  Listy.prototype.updateWidth = function() {
    var self = this;

    if (!self.opts.updateWidth) {
      return;
    }

    self.elem.css("min-width", "");
    window.setTimeout(function() {
      self.elem.css("min-width", self.elem.css("width"));
    });
  };

  /***************************************************************************
   * unflag the object as being modified
   */
  Listy.prototype.unflagModified = function() {
    var self = this;

    self.modified = false;
    self.saveButton.hide();
    self.revertButton.hide();
    self.addButton.show();
  };


  /***************************************************************************
   * reload listy
   */
  Listy.prototype.reload = function(dontPropagate) {
    var self = this, params;

    if (saveInProgress) {
      //self.log("there is a save in progress ... waiting for it to finish");
      return saveInProgress.done(function() {
        return self.reload(dontPropagate);
      });
    }

    self.log("reloading ",self.id,"dontPropagate=",dontPropagate);

    if (!self.listyParams) {
      self.log("hm, ... no listyParams");
      return $.Deferred().resolve().promise();
    }

    if (!self.modified) {
      self.log("not modified");
      return $.Deferred().resolve().promise();
    }

    self.unflagModified();

    params = $.extend({
      "name": "LISTY",
      "web": foswiki.getPreference("WEB"),
      "topic": foswiki.getPreference("WEB") + "." + foswiki.getPreference("TOPIC"),
      "render": "on"
    }, self.listyParams); // deep copy

    return $.ajax({
      url: foswiki.getScriptUrl("rest", "RenderPlugin", "tag"),
      type: "POST",
      data: params,
      beforeSend: function() {
        if (!self.elem.data("blockUI.isBlocked")) {
          self.elem.block({message:''});
        }
      },
      success: function(data) {

        /* destroy self */
        self.elem.find(".jqListyTml").remove();
        self.elem.replaceWith(data); // SMELL

        // reload of listy collections of the same topic
        if (!dontPropagate) {
          $.each(self.affected, function(id, bm) {
            bm.reload();
          });
          self.affected = {};
        }
        //self.showMessage("info", "reloaded "+self.opts.collection);
        $(document).trigger("reloaded", {
          source: self.opts.source,
          collection: self.opts.collection,
          web: data.web,
          topic: data.topic,
          action: "reload"
        });
      },
      error: function(xhr) {
        var msg;
        if (xhr.status !== 404) {
          msg = JSON.parse(xhr.responseText).error.message;
        } else {
          msg = xhr.status + " " + xhr.statusText;
        }
        self.showMessage("error", msg);
      }
    });
  };

  /***************************************************************************
   * save the current collection
   */
  Listy.prototype.save = function() {
    var self = this,
      sorting, params = {};

    if (!self.modified) {
      self.log("not modified");
      return $.Deferred().resolve().promise();
    }

    if (saveInProgress) {
      return saveInProgress.done(function() {
        saveInProgress = undefined;
        return self.save();
      });
    }

    self.log("saveListy", self.id);

    sorting = self.listyContainer.sortable("toArray");

    //self.log("sorging=",sorting);

    // build the save opts
    params = $.extend({
      topic: self.opts.source,
      sorting: sorting.join(",")
    }, self.opts);

    self.elem.find(".jqListyData").each(function() {
      $.extend(params, JSON.parse($(this).html()));
    });

    //self.log("params=", params);

    return saveInProgress = $.jsonRpc(foswiki.getScriptUrl("jsonrpc"), {
      namespace: "ListyPlugin",
      method: "saveListy",
      params: params,
      beforeSend: function() {
/*
        if (!self.elem.data("blockUI.isBlocked")) {
          self.elem.block({message:''});
        }
*/
     },
      success: function(/*json*/) {
        // reload of listy collections of the same topic
        var nextId = Object.keys(self.affected)[0],
            nextListy;

        if (!self.opts.autoSave) {
          if (typeof(nextId) !== 'undefined') {
            nextListy = self.affected[nextId];
            delete self.affected[nextId];
          }

          if (self.isEqual(nextListy)) {
            nextListy.reload();
          } else {
            nextListy.save();
          }
        }

        //self.reload(true); // dontPropagate
        //self.showMessage("success", "saved into collection '" + self.opts.collection+'"');
        saveInProgress = undefined;
      },
      error: function(json) {
        self.elem.unblock();
        self.showMessage("error", json.error.message);
        saveInProgress = undefined;
      }
    });
  };

  /***************************************************************************
   * test if the given listy is pointing to the same collection on the same topic
   */
  Listy.prototype.isEqual = function(other) {
    var self = this;
    return (self.opts.source === other.opts.source && self.opts.collection === other.opts.collection);
  };

  /*****************************************************************************
   * opens a dialog based on a jquery template
   */
  Listy.prototype.dialog = function(opts) {
    var self = this,
      defaults = {
        url: foswiki.getScriptUrl("rest", "JQueryPlugin", "tmpl", {
          load: "listyplugin",
          topic: foswiki.getPreference("WEB") + "." + foswiki.getPreference("TOPIC"),
        }),
        name: undefined,
        title: $.i18n("Confirmation required"),
        okayText: $.i18n("OK"),
        okayIcon: "ui-icon-check",
        cancelText: $.i18n("Cancel"),
        cancelIcon: "ui-icon-cancel",
        width: 'auto',
        modal: true,
        position: {
          my: 'center',
          at: 'center',
          of: window
        },
        open: function() {},
        data: {
          /* default variables to be used in jquery.render */
          /*
          web: self.opts.web,
          topic: self.opts.topic,*/
        }
      };

    /* if opts is a string, then use it as the text variable in the template */
    if (typeof(opts) === 'string') {
      opts = {
        data: {
          text: opts
        }
      };
    }

    /* merge in defaults */
    opts = $.extend({}, defaults, opts);

    /* build url */
    if (typeof(opts.name) !== 'undefined') {
      if (typeof(opts.data.type) !== 'undefined') {
        opts.name += "::" + opts.data.type;
      }
      opts.url += "&name=" + opts.name;
    }

    self.hideMessages();

    return $.Deferred(function(dfd) {
      $.loadTemplate({
        url: opts.url
      }).then(function(template) {
        $(template.render(opts.data, opts.methods)).dialog({
          buttons: [{
            text: opts.okayText,
            icon: opts.okayIcon,
            click: function() {
              $(this).dialog("close");
              dfd.resolve(this);
              return true;
            }
          }, {
            text: opts.cancelText,
            icon: opts.cancelIcon,
            click: function() {
              $(this).dialog("close");
              dfd.reject();
              return false;
            }
          }],
          open: function() {
            var $this = $(this),
              title = $this.data("title");

            if (typeof(title) !== 'undefined') {
              $this.dialog("option", "title", title);
            }

            $this.find("input").on("keydown", function(ev) {
              var $input = $(this);
              if (!$input.is(".ui-autocomplete-input") || !$input.data("ui-autocomplete").menu.element.is(":visible")) {
                if (ev.keyCode === 13) {
                  ev.preventDefault();
                  $this.dialog("close");
                  dfd.resolve($this[0]);
                }
              }
            });


            // continue
            opts.open.call(self, this, opts.data);
          },
          focus: function(ev, ui) {
            $(this).find(".listyFocus:first").focus();
          },
          close: function() {
            $(this).remove();
          },
          show: 'fade',
          modal: opts.modal,
          draggable: true,
          resizable: false,
          title: opts.title,
          width: opts.width,
          position: opts.position
        });
      }, function(xhr) {
        self.showMessage("error", xhr.responseText);
      });
    }).promise();
  };


  /***************************************************************************
   * make it a jQuery plugin
   */
  $.fn.listy = function(opts) {
    return this.each(function() {
      if (!$.data(this, "listy")) {
        $.data(this, "listy", new Listy(this, opts));
      }
    });
  };

  /***************************************************************************
   * enable declarative widget instanziation
   */
  $(".jqListyEditable").livequery(function() {
    var $this = $(this),
      opts = $.extend({}, defaults, $this.data());

    $this.addClass("jqInitedListy").listy(opts);
  });

})(jQuery);
