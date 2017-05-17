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

SRC_EXTS = cppo extlib re cmdliner graph cudf dose uutf jsonm opam_file_format
PKG_EXTS = findlib cppo topkg ocamlbuild result graph cmdliner uutf jsonm camlp4 extlib re cudf dose opam_file_format

include Makefile.sources
include Makefile.packages

ARCHIVES = $(foreach lib,$(SRC_EXTS),$(notdir $(URL_$(lib))))
lib_of = $(foreach lib,$(SRC_EXTS),$(if $(findstring $(1),$(URL_$(lib))),$(lib),,))

ARCHIVE_FILE = $(1)$(patsubst %.tbz,.tbz,$(patsubst %.tar.gz,.tar.gz,$(URL_$(2)$(1))))
DOWNLOAD_COOKIE = touch $(1).$(4)download && $(if $(filter $(MD5_$(2)$(1)),$(MD5_$(3)$(1))),touch,rm -f) $(1).$(5)download && rm -f $(call ARCHIVE_FILE,$(1),$(2)) $(1).stamp $(1).pkgbuild

ifdef OCAML
# Portable md5check
MD5CHECK = $(OCAML) ../shell/md5check.ml $(1) $(2)
else
MD5CHECK = test "`md5sum $(1) | sed -e 's/^[^a-f0-9]*\([a-f0-9]*\).*/\1/'`" = "$(2)" || (rm $(1) && false)
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

clone: $(SRC_EXTS:=.stamp) graph-workaround.stamp extlib-cppo.stamp dose-cppo.stamp
	@

clone-pkg: $(PKG_EXTS:=.pkgstamp)
	@

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
https://opam.ocaml.org/2.0~dev/cache/md5/$(shell echo $(MD5_$(1)) | cut -c -2)/$(MD5_$(1))
endef

define get_from_cache
{ $(call FETCH,$(call cache_url,$(1)),$(MD5_$(1))) && \
  mv $(MD5_$(1)) $(call ARCHIVE_FILE,$(1),$(2)) && \
  $(call MD5CHECK,$(call ARCHIVE_FILE,$(1),$(2)),$(MD5_$(2)$(1))); }
endef

%.download: Makefile.sources
	@$(call DOWNLOAD_COOKIE,$*,,PKG_,,pkg)
	[ -e $(call ARCHIVE_FILE,$*) ] || \
    cp archives/$(notdir $(URL_$*)) $(call ARCHIVE_FILE,$*) 2>/dev/null || \
	$(call FETCH,$(URL_$*),$(call ARCHIVE_FILE,$*)) && $(call MD5CHECK,$(call ARCHIVE_FILE,$*),$(MD5_$*)) || \
	$(call get_from_cache,$*)

%.pkgdownload: Makefile.sources
	@$(call DOWNLOAD_COOKIE,$*,PKG_,,pkg)
	[ -e $(call ARCHIVE_FILE,$*,PKG_) ] || \
    cp archives/$(notdir $(URL_PKG_$*)) $(call ARCHIVE_FILE,$*,PKG_) 2>/dev/null || \
	$(call FETCH,$(URL_PKG_$*),$(call ARCHIVE_FILE,$*,PKG_)) && $(call MD5CHECK,$(call ARCHIVE_FILE,$*,PKG_),$(MD5_PKG_$*)) || \
	$(call get_from_cache,$*,PKG_)

%.stamp: %.download
	mkdir -p tmp-$*
	cd tmp-$* && $(if $(patsubst %.tar.gz,,$(URL_$*)),bunzip2,gunzip) -c ../$(call ARCHIVE_FILE,$*) | tar x
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
graph-workaround.stamp: graph.stamp
	cp graph/src/sig.mli graph/src/sig.ml
	cp graph/src/sig_pack.mli graph/src/sig_pack.ml
	cp graph/src/dot_ast.mli graph/src/dot_ast.ml
	@touch $@

SRC_cppo = cppo_version.ml cppo_types.ml cppo_parser.mli cppo_parser.ml cppo_lexer.ml \
					 cppo_command.ml cppo_eval.ml cppo_main.ml

cppo/cppo$(EXE): cppo.stamp
	echo 'let cppo_version = "$(VERSION)"' > cppo/cppo_version.ml
	ocamllex cppo/cppo_lexer.mll
	ocamlyacc cppo/cppo_parser.mly
	ocamlopt -o cppo/cppo$(EXE) -I cppo -dtypes unix.cmxa str.cmxa $(foreach ml,$(SRC_cppo),cppo/$(ml))

ifeq ($(OCAML_4_02),true)
CPPOVARS=-D OCAML4 -D OCAML_4_02
else
CPPOVARS=-D OCAML4
endif

extlib-cppo.stamp: cppo/cppo$(EXE) extlib.stamp
	cppo/cppo$(EXE) $(CPPOVARS) extlib/src/extBytes.mlpp -o extlib/src/extBytes.ml
	cppo/cppo$(EXE) $(CPPOVARS) extlib/src/extHashtbl.mlpp -o extlib/src/extHashtbl.ml
	cppo/cppo$(EXE) $(CPPOVARS) extlib/src/extString.mlpp -o extlib/src/extString.ml
	cppo/cppo$(EXE) $(CPPOVARS) extlib/src/extBuffer.mlpp -o extlib/src/extBuffer.ml
	@touch $@

dose-cppo.stamp: dose.stamp
	for f in `find dose -regex ".*.mli*"`; do\
		T=`mktemp`; \
		echo "(*pp cppo$(if $(filter 1,$(WIN32)),\,/)cppo$(EXE) -V OCAML:$(OCAMLVERSION) *)" > $$T; \
		if fgrep -q OCAMLGRAPHVERSION $$f ; then \
		  echo "#define OCAMLGRAPHVERSION 186" >> $$T ; \
		fi ; \
		cat $$f >> $$T && mv $$T $$f;\
	done
	@touch $@

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

LIB_EXTS = extlib re cmdliner graph cudf dose_common dose_versioning dose_pef dose_opam dose_algo uutf jsonm opam_file_format

proj_uutf: proj_cmdliner

proj_jsonm: proj_uutf

proj_cudf: proj_extlib

proj_dose_common: proj_extlib proj_re proj_cudf

proj_dose_versioning: proj_extlib proj_dose_common proj_re proj_cudf

proj_dose_pef: proj_extlib proj_dose_common proj_re proj_cudf

proj_dose_opam: proj_extlib proj_dose_pef proj_re proj_cudf

proj_dose_algo: proj_extlib proj_dose_common proj_graph proj_cudf

inst_objs = cp $(1)/*.cm*i lib

copy: build
	mkdir -p lib
	cp *.cma lib 2>/dev/null || true
	cp *.cmxa lib 2/dev/null || true
	cp *.a lib 2>/dev/null || cp *.lib lib 2/dev/null || true
	$(call inst_objs,extlib/src)
	$(call inst_objs,re/lib)
	$(call inst_objs,cmdliner/src)
	$(call inst_objs,graph/src)
	$(call inst_objs,cudf)
	$(call inst_objs,dose/algo)
	$(call inst_objs,uutf/src)
	$(call inst_objs,jsonm/src)
	$(call inst_objs,opam_file_format/src)
	$(call inst_objs,.)

# --

addmli = $(foreach ml,$(2),$(wildcard $(addsuffix .mli,$(basename $(1)/$(ml)))) $(1)/$(ml))

SRC_extlib = extBytes.ml extBuffer.ml enum.ml extHashtbl.ml extList.ml extString.ml global.ml \
IO.ml option.ml pMap.ml refList.ml std.ml uChar.ml unzip.ml uTF8.ml optParse.ml	\
dynArray.ml dllist.ml bitSet.ml base64.ml extArray.ml extLib.ml

define PROJ_extlib
  SOURCES = $(call addmli,extlib/src,$(SRC_extlib))
  RESULT = extlib
  # Don't omit !! it leaks between subprojs...
  LIB_PACK_NAME =
endef
export PROJ_extlib

SRC_re = re_cset.ml re_automata.ml re.ml re_glob.ml re_perl.ml re_pcre.ml re_posix.ml

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
cudf_822_parser.mly cudf_822_lexer.mll cudf_types_pp.ml \
cudf.ml cudf_checker.ml cudf_parser.mly cudf_printer.ml \
cudf_c.ml

define PROJ_cudf
  SOURCES = $(call addmli,cudf,$(SRC_cudf))
  RESULT = cudf
  LIB_PACK_NAME =
  INCDIRS = extlib/src
endef
export PROJ_cudf

SRC_dose_common = shell_lexer.mll util.ml url.ml input.ml\
									format822.ml format822_parser.mly format822_lexer.mll \
									criteria_parser.mly criteria_lexer.mll criteria_types.ml criteria.ml\
									edosSolver.ml cudfSolver.ml	cudfAdd.ml cudfDiff.ml

define PROJ_dose_common
  SOURCES = $(call addmli,dose/common,$(SRC_dose_common))
  RESULT = dose_common
  LIB_PACK_NAME = common
  INCDIRS = extlib/src cudf re/lib
endef
export PROJ_dose_common

SRC_dose_versioning = debian.ml semverNode.ml semver.ml utils.ml

define PROJ_dose_versioning
  SOURCES = $(call addmli,dose/versioning,$(SRC_dose_versioning))
  RESULT = dose_versioning
  LIB_PACK_NAME = versioning
  INCDIRS = extlib/src cudf re/lib
endef
export PROJ_dose_versioning

SRC_dose_pef = packages_types.ml packages_parser.mly packages_lexer.mll printer.ml packages.ml \
							 pefcudf.ml 

#SOURCES = $(SRC_dose_pef)

define PROJ_dose_pef
  SOURCES = $(call addmli,dose/pef,$(SRC_dose_pef))
  RESULT = dose_pef
  LIB_PACK_NAME = pef
  INCDIRS = extlib/src cudf re/lib
endef
export PROJ_dose_pef

SRC_dose_opam = opamcudf.ml packages.ml

define PROJ_dose_opam
  SOURCES = $(call addmli,dose/opam,$(SRC_dose_opam))
  RESULT = dose_opam
  LIB_PACK_NAME = opam
  INCDIRS = extlib/src cudf re/lib
endef
export PROJ_dose_opam

SRC_dose_algo = defaultgraphs.ml diagnostic.ml dominators.ml flatten.ml \
								statistics.ml depsolver_int.ml depsolver.ml strongconflicts_int.ml\
								strongconflicts.ml strongdeps.ml

define PROJ_dose_algo
  SOURCES = $(call addmli,dose/algo,$(SRC_dose_algo))
  RESULT = dose_algo
  LIB_PACK_NAME = algo
  INCDIRS = extlib/src graph/src cudf
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

SRC_opam_file_format = \
  opamParserTypes.mli \
  opamLexer.mli opamLexer.mll \
  opamBaseParser.mly \
	opamParser.mli opamParser.ml \
  opamPrinter.mli  opamPrinter.ml

define PROJ_opam_file_format
  SOURCES = $(call addmli,opam_file_format/src,$(SRC_opam_file_format))
  RESULT = opam-file-format
  LIB_PACK_NAME =
endef
export PROJ_opam_file_format

# --

ifndef SUBROJS
  export SUBPROJS = $(LIB_EXTS)
endif

proj_%:
	+$(MAKE) -f $(OCAMLMAKEFILE) subproj_$* SUBTARGET=$(SUBTARGET) make_deps=yes

OCAMLMAKEFILE = ../OCamlMakefile
export OCAMLMAKEFILE
