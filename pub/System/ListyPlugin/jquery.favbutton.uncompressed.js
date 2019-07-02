/*
 * jQuery favbutton plugin 1.00
 *
 * (c)opyright 2017-2019 Michael Daum http://michaeldaumconsulting.com
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
    dry: false,
    animationClass: "faa-flash animated"
  };

  /***************************************************************************
   * class definition
   */
  function FavButton(elem, opts) {
    var self = this;

    self.elem = $(elem);
    self.icon = self.elem.find(".listyFavButtonIcon");
    self.label = self.elem.find(".listyFavButtonLabel");
    self.opts = $.extend({}, defaults, opts, self.elem.data());
    self.init();
  }

  /***************************************************************************
   * logging
   */
  FavButton.prototype.log = function() {
    var self = this, args;

    if (typeof(console) !== 'undefined' && self.opts.debug) {
      args = $.makeArray(arguments);
      args.unshift("FAV: ");
      console.log.apply(self, args); // eslint-disable-line no-console
    }
  };

  /*************************************************************************
   * calls a notification systems, defaults to pnotify
   */
  FavButton.prototype.showMessage = function(type, msg, title) {
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
  FavButton.prototype.hideMessages = function() {
    $.pnotify_remove_all();
  };

  /*************************************************************************
   * set state
   */
  FavButton.prototype.setState = function(state) {
    var self = this;

    function successCallback(response) {
      self.log("success response=",response);
      self._isSaving = false;
      self.icon.children().removeClass(self.opts.animationClass);
      self.opts.isFavorite = state;
      self.flagState(state);

      self.log("triggering changedCollection");
      $(document).trigger("changedCollection", {
        source: self.opts.source,
        collection: self.opts.collection,
        web: self.opts.web,
        topic: self.opts.topic,
        action: state?"add":"remove"
      });
    }

    function errorCallback(response) {
      self.log("error response=",response);
      self._isSaving = false;
      self.icon.children().removeClass(self.opts.animationClass);
      self.showMessage("error", response.error.message);
    }

    self.icon.children().addClass(self.opts.animationClass);
    self._isSaving = true;

    if (self.opts.dry) {
      window.setTimeout(successCallback, 1000);
    } else {
      if (state) {
        self.log("new favorite state=",state);
        $.jsonRpc(foswiki.getScriptUrl("jsonrpc"), {
          namespace: "ListyPlugin",
          method: "saveListyItem",
          params: {
            name: "",
            index: "",
            type: "topic", 
            topic: self.opts.source,
            collection: self.opts.collection,
            listyWeb: self.opts.web,
            listyTopic: self.opts.topic
          },
          success: function(response) { 
            successCallback(response);
            self.opts.name = response.result.name;
            self.showMessage("info", $.i18n("Added to favorites"));
          },
          error: function(response) { 
            errorCallback(response);
          }
        });
      } else {
        self.log("remove favorite state=",state);
        $.jsonRpc(foswiki.getScriptUrl("jsonrpc"), {
          namespace: "ListyPlugin",
          method: "deleteListyItem",
          params: {
            name: self.opts.name,
            topic: self.opts.source,
            collection: self.opts.collection
          },
          success: function(response) { 
            successCallback(response);
            self.log("success response=",response);
            self.opts.name = "";
            self.showMessage("info", $.i18n("Removed from favorites"));
          },
          error: function(response) { 
            errorCallback(response);
          }
        });
      }
    }
  };

  /*************************************************************************
   * update state
   */
  FavButton.prototype.flagState = function(state) {
    var self = this,
        icon, text, title;

    if (typeof(state) === 'undefined') {
      state = self.opts.isFavorite;
    }

    //self.log("flagging state", state);

    if (state) {
      icon = self.opts.unfavicon;
      text = self.opts.unfavtext;
      title = self.opts.unfavtitle;
    } else {
      icon = self.opts.favicon;
      text = self.opts.favtext;
      title = self.opts.favtitle;
    }

    self.elem.attr("title", decodeURIComponent(title));
    self.icon.html(decodeURIComponent(icon));
    self.label.html(decodeURIComponent(text));
  };

  /*************************************************************************
   * toggle state
   */
  FavButton.prototype.toggleState = function() {
    var self = this;
    self.setState(!self.opts.isFavorite);
  };

  /***************************************************************************
   * init listy instance
   */
  FavButton.prototype.init = function() {
    var self = this;

    self.log("opts=",self.opts);

    self.elem.on("click", function(ev) {
      if (!self._isSaving) {
        self.log("clicked on favbutton");
        self.toggleState();
      } else {
        self.log("save in progress ... ignored click");
      }
      ev.stopPropagation();
      return false;
    });

    $(document).on("changedCollection", function(ev, data) {
      if (data.source === self.opts.source && 
          data.collection === self.opts.collection &&
          data.web === self.opts.web && 
          data.topic === self.opts.topic) {

        self.log("got a changedCollection event with data=",data);

        if (typeof(data.action) !== 'undefined') {
          if (data.action === 'edit' || data.action === 'add') {
            self.opts.isFavorite = true;
          } else {
            self.opts.isFavorite = false;
          }
          self.flagState();
        }
      }
    });
  };

  /***************************************************************************
   * make it a jQuery plugin
   */
  $.fn.favButton = function(opts) {
    return this.each(function() {
      if (!$.data(this, "favButton")) {
        $.data(this, "favButton", new FavButton(this, opts));
      }
    });
  };

  /***************************************************************************
   * enable declarative widget instanziation
   */
  $(".jqFavButton").livequery(function() {
    var $this = $(this),
      opts = $.extend({}, defaults, $this.data());

    $this.addClass("jqInitedFavButton").favButton(opts);
  });

})(jQuery);

