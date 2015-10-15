ifneq ($(filter-out archives lib-pkg,$(MAKECMDGOALS)),)
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
ALTURL_PKG_$(1) = $(ALTURL_$(1))
ALTMD5_PKG_$(1) = $(ALTMD5_$(1))
endef

SRC_EXTS = extlib re cmdliner graph cudf dose uutf jsonm
PKG_EXTS = findlib graph cmdliner uutf jsonm camlp4 extlib re cudf dose

include Makefile.sources
include Makefile.packages

ARCHIVES = $(foreach lib,$(SRC_EXTS),$(notdir $(URL_$(lib))))
lib_of = $(foreach lib,$(SRC_EXTS),$(if $(findstring $(1),$(URL_$(lib))),$(lib),,))

# Note that ALTURL doesn't have to have the same file name, but it is assumed that
# it will be compressed the same way (i.e. .tar.gz or .tbz)
ARCHIVE_FILE = $(1)$(patsubst %.tbz,.tbz,$(patsubst %.tar.gz,.tar.gz,$(URL_$(2)$(1))))
DOWNLOAD_ARCHIVE = ([ -e  $(call ARCHIVE_FILE,$(1),$(3)) ] || cp archives/$(notdir $($(2)URL_$(3)$(1))) $(call ARCHIVE_FILE,$(1),$(3)) || $(call FETCH,$($(2)URL_$(3)$(1)),$(call ARCHIVE_FILE,$(1),$(3)))) && $(call MD5CHECK,$(call ARCHIVE_FILE,$(1),$(3)),$($(2)MD5_$(3)$(1)))
DOWNLOAD = rm -f $(call ARCHIVE_FILE,$(1),$(2)) $(1).stamp $(1).pkgbuild && $(if $(ALTURL_$(2)$(1)),($(call DOWNLOAD_ARCHIVE,$(1),,$(2)) || (rm $(call ARCHIVE_FILE,$(1),$(2)) && false)) || ($(call DOWNLOAD_ARCHIVE,$(1),ALT,$(2))),$(call DOWNLOAD_ARCHIVE,$(1),,$(2)))
DOWNLOAD_COOKIE = touch $(1).$(4)download && $(if $(filter $(MD5_$(2)$(1)),$(MD5_$(3)$(1))),touch,rm -f) $(1).$(5)download

ifdef OCAML
# Portable md5check
MD5CHECK = $(OCAML) ../shell/md5check.ml $(1) $(2)
else
MD5CHECK = test "`md5sum $(1) | sed -e "s/^[^a-f0-9]*\([a-f0-9]*\).*/\1/"`" = "$(2)" || (rm $(1) && false)
endif

lib-ext: clone build copy
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

ifeq ($(OCAMLC),no)
SUBTARGET=ncl
else
ifeq ($(OCAMLOPT),no)
SUBTARGET=bcl
else
SUBTARGET="bcl ncl"
endif
endif

build: clone
	$(MAKE) $(SUBPROJS:%=proj_%)

build-pkg: clone-pkg $(PKG_EXTS:=.pkgbuild)
	@

%.pkgbuild: %.pkgstamp
	$(MAKE) MAKEFLAGS= -f ../Makefile.packages -C $* $*-pkg-build
	@touch $@
	@rm -f $*.pkgstamp

all: bcl ncl

clone: $(SRC_EXTS:=.stamp) graph-workaround
	@

clone-pkg: $(PKG_EXTS:=.pkgstamp)
	@

archives: $(SRC_EXTS:=.download)
	@

archives-pkg: $(PKG_EXTS:=.pkgdownload)
	@

%.download: $(call ARCHIVE_FILE,$*) Makefile.sources
	@$(call DOWNLOAD_COOKIE,$*,,PKG_,,pkg)
	$(call DOWNLOAD,$*)

%.pkgdownload: $(call ARCHIVE_FILE,$*,,PKG_) Makefile.sources
	@$(call DOWNLOAD_COOKIE,$*,PKG_,,pkg)
	$(call DOWNLOAD,$*,PKG_)

%.stamp: %.download
	mkdir -p tmp-$*
	cd tmp-$* && tar xf$(if $(patsubst %.tar.gz,,$(call ARCHIVE_FILE,$*)),j,z) ../$(call ARCHIVE_FILE,$*)
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
	@touch $@ && rm -f $*.pkgstamp

%.pkgstamp: %.pkgdownload
	mkdir -p tmp-$*
	cd tmp-$* && tar xf$(if $(patsubst %.tar.gz,,$(call ARCHIVE_FILE,$*,PKG_)),j,z) ../$(call ARCHIVE_FILE,$*,PKG_)
	rm -rf $*
	@for ii in tmp-$*/*; do if [ -d $${ii} ]; then mv $${ii} $*; fi; done; \
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

# OCamlMakefile doesn't include stand-alone mlis in the packs...
graph-workaround: graph.stamp
	cp graph/src/sig.mli graph/src/sig.ml
	cp graph/src/sig_pack.mli graph/src/sig_pack.ml
	cp graph/src/dot_ast.mli graph/src/dot_ast.ml

clean:
	rm -rf lib
	$(MAKE) -f $(OCAMLMAKEFILE) subprojs SUBTARGET=cleanup

distclean:
	rm -rf $(SRC_EXTS) $(PKG_EXTS) ._ncdi ._bcdi ._d
	rm -f depends.ocp Makefile.config
	rm -f *.tar.gz *.tbz *.*stamp *.*download *.pkgbuild
	rm -f *.cm* *.o *.a *.lib *.obj
	rm -rf lib
	[ -d archives ] && ([ "$$(find archives -maxdepth 0 -type d -empty)" != "" ] && rmdir archives || echo "WARNING! $$(pwd)/archives/ not empty so left") || true

LIB_EXTS = extlib re cmdliner graph cudf dose_common dose_debian dose_algo uutf jsonm

proj_uutf: proj_cmdliner

proj_jsonm: proj_uutf

proj_cudf: proj_extlib

proj_dose_common: proj_extlib proj_re proj_cudf

proj_dose_debian: proj_extlib proj_dose_common proj_re proj_cudf

proj_dose_algo: proj_extlib proj_dose_common proj_graph proj_cudf

inst_objs = cp $(1)/*.cm*i lib

copy: build
	mkdir -p lib
	cp *.cma lib || true
	cp *.cmxa lib || true
	cp *.a lib || true
	cp *.lib lib || true
	$(call inst_objs,extlib)
	$(call inst_objs,re/lib)
	$(call inst_objs,cmdliner/src)
	$(call inst_objs,graph/src)
	$(call inst_objs,cudf)
	$(call inst_objs,dose/common)
	$(call inst_objs,dose/deb)
	$(call inst_objs,dose/algo)
	$(call inst_objs,uutf/src)
	$(call inst_objs,jsonm/src)
	$(call inst_objs,.)

# --

addmli = $(foreach ml,$(2),$(wildcard $(addsuffix .mli,$(basename $(1)/$(ml)))) $(1)/$(ml))

SRC_extlib = enum.ml extHashtbl.ml extList.ml extString.ml global.ml install.ml	\
IO.ml option.ml pMap.ml refList.ml std.ml uChar.ml unzip.ml uTF8.ml optParse.ml	\
dynArray.ml dllist.ml bitSet.ml base64.ml extArray.ml extLib.ml

define PROJ_extlib
  SOURCES = $(call addmli,extlib,$(SRC_extlib))
  RESULT = extlib
  # Don't omit !! it leaks between subprojs...
  LIB_PACK_NAME =
endef
export PROJ_extlib

SRC_re = cset.ml automata.ml re.ml re_perl.ml re_pcre.ml re_emacs.ml re_glob.ml	\
re_str.ml

define PROJ_re
  SOURCES = $(call addmli,re/lib,$(SRC_re))
  RESULT = re
  LIB_PACK_NAME =
endef
export PROJ_re

SRC_cmdliner = cmdliner.ml

define PROJ_cmdliner
  SOURCES = $(call addmli,cmdliner/src,$(SRC_cmdliner))
  RESULT = cmdliner
  LIB_PACK_NAME =
endef
export PROJ_cmdliner

SRC_graph_lib = bitv.ml heap.ml unionfind.ml
SRC_graph = sig_pack.ml sig.ml dot_ast.ml builder.ml classic.ml contraction.ml	\
delaunay.ml dominator.ml dot_parser.mly fixpoint.ml gmap.ml gml.mll graphml.ml	\
graphviz.ml leaderlist.ml oper.ml rand.ml strat.ml traverse.ml util.ml		\
version.ml kruskal.ml flow.ml dot_lexer.mll components.ml coloring.ml blocks.ml	\
dot.ml imperative.ml merge.ml minsep.ml persistent.ml nonnegative.ml path.ml	\
topological.ml pack.ml mcs_m.ml cliquetree.ml md.ml

define PROJ_graph
  SOURCES = $(call addmli,graph/lib,$(SRC_graph_lib)) $(call addmli,graph/src,$(SRC_graph))
  RESULT = graph
  LIB_PACK_NAME = graph
endef
export PROJ_graph

SRC_cudf = cudf_types.ml cudf_type_parser.mly cudf_type_lexer.mll cudf_conf.ml	\
cudf_822_parser.mly cudf_822_lexer.mll cudf_types_pp.ml main_cudf_parse_822.ml	\
cudf.ml cudf_checker.ml cudf_parser.mly cudf_printer.ml main_cudf_check.ml	\
cudf_c.ml

define PROJ_cudf
  SOURCES = $(call addmli,cudf,$(SRC_cudf))
  RESULT = cudf
  LIB_PACK_NAME =
  INCDIRS = extlib
endef
export PROJ_cudf

SRC_dose_common = util.ml url.ml input.ml edosSolver.ml cudfSolver.ml	\
cudfAdd.ml cudfDiff.ml

define PROJ_dose_common
  SOURCES = $(call addmli,dose/common,$(SRC_dose_common))
  RESULT = dose_common
  LIB_PACK_NAME = common
  INCDIRS = extlib cudf re/lib
endef
export PROJ_dose_common

SRC_dose_debian = architecture.ml format822.ml format822_parser.mly		\
packages_parser.mly version.ml packages_lexer.mll format822_lexer.mll		\
packages.ml release.ml sources.ml printer.ml evolution.ml debutil.ml debcudf.ml \
apt.ml edsp.ml

define PROJ_dose_debian
  SOURCES = $(call addmli,dose/deb,$(SRC_dose_debian))
  RESULT = dose_debian
  LIB_PACK_NAME = debian
  INCDIRS = extlib cudf dose/common re/lib
endef
export PROJ_dose_debian

SRC_dose_algo = defaultgraphs.ml diagnostic_int.ml diagnostic.ml		\
dominators.ml flatten.ml statistics.ml depsolver_int.ml depsolver.ml		\
strongconflicts_int.ml strongconflicts.ml strongdeps_int.ml strongdeps.ml

define PROJ_dose_algo
  SOURCES = $(call addmli,dose/algo,$(SRC_dose_algo))
  RESULT = dose_algo
  LIB_PACK_NAME = algo
  INCDIRS = extlib graph/src dose/common dose/deb cudf
endef
export PROJ_dose_algo

define PROJ_uutf
  SOURCES = $(call addmli,uutf/src,uutf.ml)
  RESULT = uutf
  LIB_PACK_NAME =
endef
export PROJ_uutf

define PROJ_jsonm
  SOURCES = $(call addmli,jsonm/src,jsonm.ml)
  RESULT = jsonm
  LIB_PACK_NAME =
  INCDIRS = uutf/src
endef
export PROJ_jsonm

# --

ifndef SUBROJS
  export SUBPROJS = $(LIB_EXTS)
endif

proj_%:
	+$(MAKE) -f $(OCAMLMAKEFILE) subproj_$* SUBTARGET=$(SUBTARGET) make_deps=yes

OCAMLMAKEFILE = ../OCamlMakefile
export OCAMLMAKEFILE
