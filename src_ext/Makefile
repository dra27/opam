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
PKG_EXTS = findlib cppo topkg ocamlbuild result graph cmdliner uutf jsonm \
           camlp4 extlib re cudf dose opam_file_format

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

%.pkgbuild: | %.pkgstamp
	@rm -f $*.pkgstamp
	$(MAKE) MAKEFLAGS= -f ../Makefile.packages -C $* $*-pkg-build && touch $@

all: bcl ncl

clone: $(SRC_EXTS:=.stamp) graph-workaround.stamp extlib-cppo.stamp dose-cppo.stamp
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

LIB_EXTS = extlib re cmdliner graph cudf dose_common dose_versioning dose_pef dose_opam dose_algo \
           uutf jsonm opam_file_format

proj_uutf: proj_cmdliner

proj_jsonm: proj_uutf

proj_cudf: proj_extlib

proj_dose_common: proj_extlib proj_re proj_cudf

proj_dose_versioning: proj_extlib proj_dose_common proj_re proj_cudf

proj_dose_pef: proj_extlib proj_dose_common proj_re proj_cudf

proj_dose_opam: proj_extlib proj_dose_pef proj_re proj_cudf

proj_dose_algo: proj_extlib proj_dose_common proj_graph proj_cudf

# --

addmli = $(foreach ml,$(2),$(wildcard $(addsuffix .mli,$(basename $(1)/$(ml)))) $(1)/$(ml))

define MAKE_LIB
define PROJ_$1
  SRC_DIR = $(lastword $2)
  SOURCES = $(foreach DIR,$(filter-out $(lastword $2),$2),$(call addmli,$(DIR),$(SRC_$1_$(notdir $(DIR))))) \
            $(call addmli,$(lastword $2),$(SRC_$1))
  RESULT = $(if $4,$4,$1)
  LIB_PACK_NAME = $(filter-out @,$(PACK_NAME))
  INCDIRS = $(foreach DEP,$3,$(eval $(PROJ_$(DEP)))$(SRC_DIR))
endef
export PROJ_$1
endef
PROCESS_LIB=$(eval $(call MAKE_LIB,$1,$(if $2,$(foreach DIR,$2,$1/$(DIR)),$1),$3,$4))
BASIC_LIB=$(foreach PACK_NAME,@,$(call PROCESS_LIB,$1,$2,$3,$4))
PACK_LIB=$(foreach PACK_NAME,$1,$(call PROCESS_LIB,$1,$2,$3,$4))
SUB_PACK_LIB=$(foreach PACK_NAME,$2,$(eval $(call MAKE_LIB,$1_$2,$1/$2,$3,$4)))

SRC_extlib = extBytes.ml extBuffer.ml enum.ml extHashtbl.ml extList.ml extString.ml global.ml \
IO.ml option.ml pMap.ml refList.ml std.ml uChar.ml unzip.ml uTF8.ml optParse.ml	\
dynArray.ml dllist.ml bitSet.ml base64.ml extArray.ml extLib.ml
$(call BASIC_LIB,extlib,src)

SRC_re = re_cset.ml re_automata.ml re.ml re_glob.ml re_perl.ml re_pcre.ml re_posix.ml
$(call BASIC_LIB,re,lib)

SRC_cmdliner = cmdliner.ml
$(call BASIC_LIB,cmdliner,src)

SRC_graph_lib = bitv.ml heap.ml unionfind.ml
SRC_graph = sig_pack.ml sig.ml dot_ast.ml builder.ml classic.ml contraction.ml	\
delaunay.ml dominator.ml dot_parser.mly fixpoint.ml gmap.ml gml.mll graphml.ml	\
graphviz.ml leaderlist.ml oper.ml rand.ml strat.ml traverse.ml util.ml		\
version.ml kruskal.ml flow.ml dot_lexer.mll components.ml coloring.ml blocks.ml	\
dot.ml imperative.ml merge.ml minsep.ml persistent.ml nonnegative.ml path.ml	\
topological.ml pack.ml mcs_m.ml cliquetree.ml md.ml
$(call PACK_LIB,graph,lib src)

SRC_cudf = cudf_types.ml cudf_type_parser.mly cudf_type_lexer.mll cudf_conf.ml	\
cudf_822_parser.mly cudf_822_lexer.mll cudf_types_pp.ml \
cudf.ml cudf_checker.ml cudf_parser.mly cudf_printer.ml \
cudf_c.ml
$(call BASIC_LIB,cudf,,extlib)

SRC_dose_common = shell_lexer.mll util.ml url.ml input.ml\
									format822.ml format822_parser.mly format822_lexer.mll \
									criteria_parser.mly criteria_lexer.mll criteria_types.ml criteria.ml\
									edosSolver.ml cudfSolver.ml	cudfAdd.ml cudfDiff.ml
$(call SUB_PACK_LIB,dose,common,extlib cudf re)

SRC_dose_versioning = debian.ml semverNode.ml semver.ml utils.ml
$(call SUB_PACK_LIB,dose,versioning,extlib cudf re)

SRC_dose_pef = packages_types.ml packages_parser.mly packages_lexer.mll printer.ml packages.ml \
							 pefcudf.ml
$(call SUB_PACK_LIB,dose,pef,extlib cudf re)

SRC_dose_opam = opamcudf.ml packages.ml
$(call SUB_PACK_LIB,dose,opam,extlib cudf re)

SRC_dose_algo = defaultgraphs.ml diagnostic.ml dominators.ml flatten.ml \
								statistics.ml depsolver_int.ml depsolver.ml strongconflicts_int.ml\
								strongconflicts.ml strongdeps.ml
$(call SUB_PACK_LIB,dose,algo,extlib graph cudf)

SRC_uutf = uutf.ml
$(call BASIC_LIB,uutf,src)

SRC_jsonm = jsonm.ml
$(call BASIC_LIB,jsonm,src,uutf)

SRC_opam_file_format = \
  opamParserTypes.mli \
  opamLexer.mli opamLexer.mll \
  opamBaseParser.mly \
	opamParser.mli opamParser.ml \
  opamPrinter.mli  opamPrinter.ml
$(call BASIC_LIB,opam_file_format,src,,opam-file-format)

# --

define INSTALL_OBJECTS
	cp $(eval $(call PROJ_$(LIB)))$(if $(LIB_PACK_NAME),$(LIB_PACK_NAME).cm*i $(LIB_PACK_NAME).cmx,$(SRC_DIR)/*.cm*i $(SRC_DIR)/*.cmx) lib 2>/dev/null || true

endef

copy: build
	mkdir -p lib
	cp *.cma *.cmxa *$(shell ocamlc -config | grep "^ext_lib:" | tr -d '\r' | sed -e "s/.*: //") lib 2>/dev/null || true
	$(foreach LIB,$(LIB_EXTS),$(INSTALL_OBJECTS))

# --

ifndef SUBROJS
  export SUBPROJS = $(LIB_EXTS)
endif

proj_%:
	+$(MAKE) -f $(OCAMLMAKEFILE) subproj_$* SUBTARGET=$(SUBTARGET) make_deps=yes

OCAMLMAKEFILE = ../OCamlMakefile
export OCAMLMAKEFILE
