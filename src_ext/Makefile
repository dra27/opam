ifneq ($(filter-out archives cache-archives lib-pkg,$(MAKECMDGOALS)),)
-include ../Makefile.config
endif

ifneq ($(wildcard Makefile.config),)
include Makefile.config
CAN_PKG=1
else
CAN_PKG=0
endif

ifndef FETCH
ifneq ($(shell command -v curl > /dev/null),)
FETCH=curl -L -o $(2) $(1)
else
FETCH=wget -O $(2) $(1)
endif
endif

# Shorthand for designating that lib-ext and lib-pkg use the same version of a library
PKG_SAME = $(eval $(call PKG_SAME_DEFS,$(1)))
define PKG_SAME_DEFS =
URL_PKG_$(1) = $(URL_$(1))
MD5_PKG_$(1) = $(MD5_$(1))
endef

SRC_EXTS = cppo extlib re cmdliner ocamlgraph cudf dose3 uutf jsonm opam-file-format result uchar
PKG_EXTS = findlib cppo topkg ocamlbuild result ocamlgraph cmdliner uutf jsonm \
           camlp4 extlib re cudf dose3 opam-file-format

include Makefile.sources
include Makefile.packages

ARCHIVES = $(foreach lib,$(SRC_EXTS),$(notdir $(URL_$(lib))))
lib_of = $(foreach lib,$(SRC_EXTS),$(if $(findstring $(1),$(URL_$(lib))),$(lib),,))

ARCHIVE_FILE = $(1)$(patsubst %.tbz,.tbz,$(patsubst %.tar.gz,.tar.gz,$(URL_$(2)$(1))))
DOWNLOAD_COOKIE = touch $(1).$(4)download && \
                  $(if $(filter $(MD5_$(2)$(1)),$(MD5_$(3)$(1))),touch,rm -f) $(1).$(5)download && \
                  rm -f $(call ARCHIVE_FILE,$(1),$(2)) $(1).stamp $(1).pkgbuild

ifdef OCAML
# Portable md5check
MD5CHECK = $(OCAML) ../shell/md5check.ml $(1) $(2)
else
MD5CHECK = test "`md5sum $(1) | sed -e 's/^[^a-f0-9]*\([a-f0-9]*\).*/\1/'`" = "$(2)" || (rm $(1) && false)
endif

lib-ext: $(JBUILDER_DEP) build copy
	@

ifeq ($(CAN_PKG),1)
lib-pkg: clone-pkg build-pkg
	@
else
lib-pkg:
	@echo "Installation of packages is only permitted for the bootstrap compiler"
	@echo "Run $(MAKE) [OCAML_PORT=auto|msvc|msvc64|mingw|mingw64] compiler first"
	@false
endif

ifeq ($(JBUILDER),)
JBUILDER_DEP=jbuilder/_build/install/default/bin/jbuilder.exe
JBUILDER_CLONE=jbuilder.stamp
JBUILDER:=$(shell echo "$(JBUILDER_DEP)" | cygpath -f - -a)
else
JBUILDER_DEP=
JBUILDER_CLONE=
endif

jbuilder/_build/install/default/bin/jbuilder.exe: $(JBUILDER_CLONE)
	cd jbuilder && ocaml bootstrap.ml && ./boot

build: $(JBUILDER_DEP) clone
	"$(JBUILDER)" build @install

build-pkg: clone-pkg $(PKG_EXTS:=.pkgbuild)
	@

%.pkgbuild: | %.pkgstamp
	@rm -f $*.pkgstamp
	$(MAKE) MAKEFLAGS= -f ../Makefile.packages -C $* $*-pkg-build && touch $@

clone: $(JBUILDER_CLONE) $(SRC_EXTS:=.stamp)
	@

clone-pkg: $(PKG_EXTS:=.pkgstamp)
	@

.PHONY: archives
archives: $(SRC_EXTS:=.download)
	@

archives-pkg: $(PKG_EXTS:=.pkgdownload)
	@

cache-archives: $(SRC_EXTS:=.cache) $(PKG_EXTS:=.pkgcache)
	@

%.cache:
	@mkdir -p archives
	@[ -e archives/$(notdir $(URL_$*)) ] || \
		($(call FETCH,$(URL_$*),$(notdir $(URL_$*))) && mv $(notdir $(URL_$*)) archives/)

%.pkgcache:
	@mkdir -p archives
	@[ -e archives/$(notdir $(URL_PKG_$*)) ] || \
		($(call FETCH,$(URL_PKG_$*),$(notdir $(URL_PKG_$*))) && mv $(notdir $(URL_PKG_$*)) archives/)

define cache_url
https://opam.ocaml.org/2.0~dev/cache/md5/$(shell echo $(MD5_$(2)$(1)) | cut -c -2)/$(MD5_$(2)$(1))
endef

define get_from_cache
{ $(call FETCH,$(call cache_url,$(1),$(2)),$(MD5_$(2)$(1))) && \
  mv $(MD5_$(2)$(1)) $(call ARCHIVE_FILE,$(1),$(2)) && \
  $(call MD5CHECK,$(call ARCHIVE_FILE,$(1),$(2)),$(MD5_$(2)$(1))); }
endef

%.download: Makefile.sources
	@$(call DOWNLOAD_COOKIE,$*,,PKG_,,pkg)
	[ -e $(call ARCHIVE_FILE,$*) ] || \
	cp archives/$(notdir $(URL_$*)) $(call ARCHIVE_FILE,$*) 2>/dev/null || \
	{ $(call FETCH,$(URL_$*),$(call ARCHIVE_FILE,$*)) && $(call MD5CHECK,$(call ARCHIVE_FILE,$*),$(MD5_$*)); } || \
	$(call get_from_cache,$*)

%.pkgdownload: Makefile.sources
	@$(call DOWNLOAD_COOKIE,$*,PKG_,,pkg)
	[ -e $(call ARCHIVE_FILE,$*,PKG_) ] || \
	cp archives/$(notdir $(URL_PKG_$*)) $(call ARCHIVE_FILE,$*,PKG_) 2>/dev/null || \
	{ $(call FETCH,$(URL_PKG_$*),$(call ARCHIVE_FILE,$*,PKG_)) && $(call MD5CHECK,$(call ARCHIVE_FILE,$*,PKG_),$(MD5_PKG_$*)); } || \
	$(call get_from_cache,$*,PKG_)

%.stamp: %.download
	mkdir -p tmp-$*
	cd tmp-$* && $(if $(patsubst %.tar.gz,,$(URL_$*)),bunzip2,gunzip) -c ../$(call ARCHIVE_FILE,$*) | tar xf -
	rm -rf $*
	@for ii in tmp-$*/*; do if [ -d $${ii} ]; then mv $${ii} $*; fi; done; \
	rm -rf tmp-$*
	@if [ -d patches/$* ]; then \
          cd $* && \
	  for p in ../patches/$*/*.patch; do \
	    patch -p1 < $$p; \
	  done; \
        fi
	@if [ -d patches/$*.common ]; then \
          cd $* && \
	  for p in ../patches/$*.common/*.patch; do \
	    patch -p1 < $$p; \
	  done; \
        fi
	@for j in $(wildcard jbuild-$* jbuild-$*-*); do \
     cp $$j $*$$(echo "$$j" | sed -e "s/jbuild-$*//" -e "s|-|/|g")/jbuild; \
   done
	@touch $*/$*.opam
	@touch $@ && rm -f $*.pkgstamp

%.pkgstamp: %.pkgdownload
	mkdir -p tmp-$*
	cd tmp-$* && tar xf$(if $(patsubst %.tar.gz,,$(call ARCHIVE_FILE,$*,PKG_)),j,z) ../$(call ARCHIVE_FILE,$*,PKG_)
	rm -rf $*
# On Cygwin, the mv has a tedious habit of sometimes failing, hence the slightly odd repetition
	@for ii in tmp-$*/*; do if [ -d $${ii} ]; then mv $${ii} $* || mv $${ii} $*; fi; done; \
	rm -rf tmp-$*
	@if [ -d patches/$*.pkg ]; then \
          cd $* && \
	  for p in ../patches/$*.pkg/*.patch; do \
	    patch -p1 < $$p; \
	  done; \
        fi
	@if [ -d patches/$*.common ]; then \
          cd $* && \
	  for p in ../patches/$*.common/*.patch; do \
	    patch -p1 < $$p; \
	  done; \
        fi
	@touch $@ && rm -f $*.stamp

clean:
	rm -rf lib

distclean: clean
	rm -rf jbuilder $(SRC_EXTS) $(PKG_EXTS)
	rm -f Makefile.config
	rm -f *.tar.gz *.tbz *.*stamp *.*download *.pkgbuild
	[ -d archives ] && ([ "$$(find archives -maxdepth 0 -type d -empty)" != "" ] && rmdir archives || echo "WARNING! $$(pwd)/archives/ not empty so left") || true

LIB_EXTS = extlib re cmdliner ocamlgraph cudf dose3 uutf jsonm opam-file-format result uchar

copy: build
	mkdir -p lib
	for d in $(LIB_EXTS:%=$$(find ../_build/install/default/lib/% -type d)); do \
    cp $$d/* lib/ 2>/dev/null; \
  done
	rm lib/META lib/opam lib/*.cmxs lib/*.mli
