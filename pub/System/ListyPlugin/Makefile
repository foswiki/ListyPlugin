FOSWIKI_ROOT?=~/foswiki/core
TARGET= build/pkg.js build/pkg.css

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

PKG_JS= src/listy.js src/favbutton.js
PKG_CSS= src/listy.css

clean:
	rm -f build/*

build/pkg.js: $(PKG_JS)
	@echo minifying $@ from $^; $(JSMIN) $^ > $@; \

build/pkg.css: $(PKG_CSS)
	@echo minifying $@ from $^; $(CSSMIN) $^ $(CSSMIN_ARGS)> $@
