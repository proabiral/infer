# Copyright (c) 2015-present, Facebook, Inc.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

.PHONY: default
default: infer

ROOT_DIR = .
include $(ROOT_DIR)/Makefile.config

ORIG_SHELL_BUILD_MODE = $(BUILD_MODE)
# override this for faster builds (but slower infer)
BUILD_MODE ?= opt

MAKE_SOURCE = $(MAKE) -C $(SRC_DIR) INFER_BUILD_DIR=_build/$(BUILD_MODE)

ifneq ($(UTOP),no)
BUILD_SYSTEMS_TESTS += infertop
endif

ifeq ($(BUILD_C_ANALYZERS),yes)
BUILD_SYSTEMS_TESTS += \
  assembly \
  backtrack_level \
  ck_analytics ck_imports \
  clang_compilation_db_escaped clang_compilation_db_relpath \
  clang_multiple_files \
  clang_translation \
  clang_unknown_ext \
  clang_with_blacklisted_flags \
  clang_with_E_flag \
  clang_with_M_flag \
  clang_with_MD_flag \
  deduplicate_template_warnings \
  delete_results_dir \
  diff \
  diff_gen_build_script \
  duplicate_symbols \
  fail_on_issue \
  j1 \
  linters \
  project_root_rel \
  reactive \
  run_hidden_linters \
  tracebugs \
  utf8_in_procname \

DIRECT_TESTS += \
  c_biabduction \
  c_bufferoverrun \
  c_errors \
  c_frontend \
  c_performance \
  c_uninit \
  cpp_bufferoverrun \
  cpp_conflicts \
  cpp_errors \
  cpp_frontend \
  cpp_linters-for-test-only \
  cpp_liveness \
  cpp_nullable \
  cpp_ownership cpp_pulse \
  cpp_quandary cpp_quandaryBO \
  cpp_racerd \
  cpp_siof \
	cpp_starvation \
  cpp_uninit \

ifneq ($(BUCK),no)
BUILD_SYSTEMS_TESTS += buck_blacklist buck-clang-db buck_flavors buck_flavors_run buck_flavors_deterministic
endif
ifneq ($(CMAKE),no)
BUILD_SYSTEMS_TESTS += clang_compilation_db cmake inferconfig inferconfig_not_strict
endif
ifneq ($(NDKBUILD),no)
BUILD_SYSTEMS_TESTS += ndk_build
endif
ifneq ($(PYTHON_lxml),no)
BUILD_SYSTEMS_TESTS += results_xml
endif
ifeq ($(HAS_OBJC),yes)
BUILD_SYSTEMS_TESTS += objc_getters_setters objc_missing_fld objc_retain_cycles objc_retain_cycles_weak
DIRECT_TESTS += \
  objc_frontend objc_errors objc_linters objc_ioslints objcpp_errors objcpp_nullable objcpp_retain-cycles \
  objc_linters-def-folder objc_nullable objc_liveness objcpp_liveness objc_uninit \
  objcpp_frontend objcpp_linters cpp_linters  objc_linters-for-test-only objcpp_linters-for-test-only \
	objcpp_racerd
ifneq ($(XCODE_SELECT),no)
BUILD_SYSTEMS_TESTS += xcodebuild_no_xcpretty
endif
ifneq ($(XCPRETTY),no)
BUILD_SYSTEMS_TESTS += xcodebuild
endif
endif # HAS_OBJC
endif # BUILD_C_ANALYZERS

ifeq ($(BUILD_JAVA_ANALYZERS),yes)
BUILD_SYSTEMS_TESTS += \
	differential_interesting_paths_filter \
  differential_of_costs_report \
  differential_skip_anonymous_class_renamings \
  differential_skip_duplicated_types_on_filenames \
  differential_skip_duplicated_types_on_filenames_with_renamings \
  gradle \
	java_test_determinator \
  javac \
  resource_leak_exception_lines \
	racerd_dedup

DIRECT_TESTS += \
  java_bufferoverrun \
  java_checkers \
  java_classloads \
  java_crashcontext \
  java_eradicate \
  java_hoisting \
  java_hoistingExpensive \
  java_infer \
  java_lab \
  java_performance \
  java_purity \
  java_quandary \
  java_racerd \
  java_starvation \
  java_tracing \

ifneq ($(ANT),no)
BUILD_SYSTEMS_TESTS += ant
endif
ifneq ($(BUCK),no)
BUILD_SYSTEMS_TESTS += buck genrule buck_javac_jar
# Introduce the dependency only if the two tests are going to be built in parallel, so that they do
# not run in parallel (otherwise Buck has a bad time). This works by checking if one of the main
# testing targets was passed as a goal on the command line.
ifneq ($(filter build_systems_tests config_tests test test-replace,${MAKECMDGOALS}),)
build_genrule_print: build_buck_print
build_genrule_replace: build_buck_replace
build_genrule_test: build_buck_test
endif
endif
ifneq ($(MVN),no)
BUILD_SYSTEMS_TESTS += mvn
endif
endif

ifeq ($(BUILD_C_ANALYZERS)+$(BUILD_JAVA_ANALYZERS),yes+yes)
BUILD_SYSTEMS_TESTS += make utf8_in_pwd waf
# the waf test and the make test run the same `make` command; use the same trick as for
# &quot;build_buck_test&quot; to prevent make from running them in parallel
ifneq ($(filter build_systems_tests config_tests test test-replace,${MAKECMDGOALS}),)
build_waf_replace: build_make_replace
build_waf_print: build_make_print
build_waf_test: build_make_test
endif
endif

ifeq ($(IS_INFER_RELEASE),no)
configure: configure.ac $(wildcard m4/*.m4)
#	rerun ./autogen.sh in case of failure as the failure may be due to needing to rerun
#	./configure
	$(QUIET)($(call silent_on_success,Generate ./configure,./autogen.sh)) || \
	./autogen.sh

Makefile.autoconf: configure Makefile.autoconf.in
#	rerun ./configure with the flags that were used last time it was run (if available)
#	retry in case of failure as the failure may be due to needing to rerun ./configure
	$(QUIET)($(call silent_on_success,Running\
	./configure $(shell ./config.status --config || true),\
	./configure $(shell ./config.status --config || true))) || \
	./configure $(shell ./config.status --config || true)
endif

.PHONY: fb-setup
fb-setup:
	$(QUIET)$(call silent_on_success,Facebook setup,\
	$(MAKE) -C facebook setup)

OCAMLFORMAT_EXE?=ocamlformat

.PHONY: fmt
fmt:
	parallel $(OCAMLFORMAT_EXE) -i ::: $$(git diff --name-only --diff-filter=ACMRU $$(git merge-base origin/master HEAD) | grep &quot;\.mli\?$$&quot;)

DUNE_ML:=$(shell find * -name &#39;dune*.in&#39; | grep -v workspace)

.PHONY: fmt_dune
fmt_dune:
	parallel $(OCAMLFORMAT_EXE) -i ::: $(DUNE_ML)

SRC_ML:=$(shell find * \( -name _build -or -name facebook-clang-plugins -or -path facebook/dependencies -or -path sledge/llvm \) -not -prune -or -type f -and -name &#39;*&#39;.ml -or -name &#39;*&#39;.mli 2&gt;/dev/null)

.PHONY: fmt_all
fmt_all:
	parallel $(OCAMLFORMAT_EXE) -i ::: $(SRC_ML) $(DUNE_ML)

# pre-building these avoids race conditions when building, eg src_build and test_build in parallel
.PHONY: src_build_common
src_build_common:
	$(QUIET)$(call silent_on_success,Generating source dependencies,\
	$(MAKE_SOURCE) src_build_common)

.PHONY: src_build
src_build: src_build_common
	$(QUIET)$(call silent_on_success,Building native($(BUILD_MODE)) Infer,\
	$(MAKE_SOURCE) infer)

.PHONY: byte
byte: src_build_common
	$(QUIET)$(call silent_on_success,Building byte Infer,\
	$(MAKE_SOURCE) byte)

.PHONY: test_build
test_build: src_build_common
	$(QUIET)$(call silent_on_success,Testing Infer builds without warnings,\
	$(MAKE_SOURCE) test)

# deadcode analysis: only do the deadcode detection on Facebook builds and if GNU sed is available
.PHONY: real_deadcode
real_deadcode: src_build_common
	$(QUIET)$(call silent_on_success,Testing there is no dead OCaml code,\
	$(MAKE) -C $(SRC_DIR)/deadcode)

.PHONY: deadcode
deadcode:
ifeq ($(IS_FACEBOOK_TREE),no)
	$(QUIET)echo &quot;Deadcode detection only works in Facebook builds, skipping&quot;
endif
ifeq ($(GNU_SED),no)
	$(QUIET)echo &quot;Deadcode detection only works with GNU sed installed, skipping&quot;
endif

ifeq ($(IS_FACEBOOK_TREE),yes)
ifneq ($(GNU_SED),no)
deadcode: real_deadcode
endif
endif


.PHONY: toplevel toplevel_test
toplevel toplevel_test: src_build_common

toplevel:
	$(QUIET)$(call silent_on_success,Building Infer REPL,\
	$(MAKE_SOURCE) toplevel)
	$(QUIET)echo
	$(QUIET)echo &quot;You can now use the infer REPL:&quot;
	$(QUIET)echo &quot;  \&quot;$(ABSOLUTE_ROOT_DIR)/scripts/infer_repl\&quot;&quot;

toplevel_test: test_build
	$(QUIET)$(call silent_on_success,Building Infer REPL (test mode),\
	$(MAKE_SOURCE) BUILD_MODE=test toplevel)

ifeq ($(IS_FACEBOOK_TREE),yes)
byte src_build_common src_build test_build: fb-setup
endif

ifeq ($(BUILD_C_ANALYZERS),yes)
byte src_build src_build_common test_build: clang_plugin
endif

$(INFER_COMMAND_MANUALS): src_build $(MAKEFILE_LIST)
	$(QUIET)$(MKDIR_P) $(@D)
	$(QUIET)$(INFER_BIN) $(patsubst infer-%.1,%,$(@F)) --help --help-format=groff &gt; $@

$(INFER_COMMAND_TEXT_MANUALS): src_build $(MAKEFILE_LIST)
	$(QUIET)$(MKDIR_P) $(@D)
	$(QUIET)$(INFER_BIN) $(patsubst infer-%.txt,%,$(@F)) --help --help-format=plain &gt; $@

$(INFER_MANUAL): src_build $(MAKEFILE_LIST)
	$(QUIET)$(MKDIR_P) $(@D)
	$(QUIET)$(INFER_BIN) --help --help-format=groff &gt; $@

$(INFER_TEXT_MANUAL): src_build $(MAKEFILE_LIST)
	$(QUIET)$(MKDIR_P) $(@D)
	$(QUIET)$(INFER_BIN) --help --help-format=plain &gt; $@

$(INFER_FULL_TEXT_MANUAL): src_build $(MAKEFILE_LIST)
	$(QUIET)$(MKDIR_P) $(@D)
	$(QUIET)$(INFER_BIN) --help-full --help-format=plain &gt; $@

$(INFER_GROFF_MANUALS_GZIPPED): %.gz: %
	$(QUIET)$(REMOVE) $@
	gzip $&lt;

infer_models: src_build
ifeq ($(BUILD_JAVA_ANALYZERS),yes)
	$(MAKE) -C $(ANNOTATIONS_DIR)
endif
	$(MAKE) -C $(MODELS_DIR) all

.PHONY: infer byte_infer
infer byte_infer:
	$(QUIET)$(call silent_on_success,Building Infer models,\
	$(MAKE) infer_models)
	$(QUIET)$(call silent_on_success,Building Infer manuals,\
	$(MAKE) $(INFER_MANUALS))
infer: src_build
byte_infer: byte

.PHONY: opt
opt:
	$(QUIET)$(MAKE) BUILD_MODE=opt infer

.PHONY: clang_setup
clang_setup:
	$(QUIET)export CC=&quot;$(CC)&quot; CFLAGS=&quot;$(CFLAGS)&quot;; \
	export CXX=&quot;$(CXX)&quot; CXXFLAGS=&quot;$(CXXFLAGS)&quot;; \
	export CPP=&quot;$(CPP)&quot; LDFLAGS=&quot;$(LDFLAGS)&quot; LIBS=&quot;$(LIBS)&quot;; \
	$(FCP_DIR)/clang/setup.sh --only-check-install || \
	$(FCP_DIR)/clang/setup.sh

.PHONY: clang_plugin
clang_plugin: clang_setup
	$(QUIET)$(call silent_on_success,Building clang plugin,\
	$(MAKE) -C $(FCP_DIR)/libtooling all \
	  CC=&quot;$(CC)&quot; CXX=&quot;$(CXX)&quot; \
	  CFLAGS=&quot;$(CFLAGS)&quot; CXXFLAGS=&quot;$(CXXFLAGS)&quot; \
	  CPP=&quot;$(CPP)&quot; LDFLAGS=&quot;$(LDFLAGS)&quot; LIBS=&quot;$(LIBS)&quot; \
	  LOCAL_CLANG=$(CLANG_PREFIX)/bin/clang \
	  CLANG_PREFIX=$(CLANG_PREFIX) \
	  CLANG_INCLUDES=$(CLANG_INCLUDES))
	$(QUIET)$(call silent_on_success,Building clang plugin OCaml interface,\
	$(MAKE) -C $(FCP_DIR)/clang-ocaml all \
          build/clang_ast_proj.ml build/clang_ast_proj.mli \
	  CC=$(CC) CXX=$(CXX) \
	  CFLAGS=&quot;$(CFLAGS)&quot; CXXFLAGS=&quot;$(CXXFLAGS)&quot; \
	  CPP=&quot;$(CPP)&quot; LDFLAGS=&quot;$(LDFLAGS)&quot; LIBS=&quot;$(LIBS)&quot; \
	  LOCAL_CLANG=$(CLANG_PREFIX)/bin/clang \
	  CLANG_PREFIX=$(CLANG_PREFIX) \
	  CLANG_INCLUDES=$(CLANG_INCLUDES))

.PHONY: clang_plugin_test
clang_plugin_test: clang_setup
		$(QUIET)$(call silent_on_success,Running facebook-clang-plugins/libtooling/ tests,\
		$(MAKE) -C $(FCP_DIR)/libtooling test \
		  CC=$(CC) CXX=$(CXX) \
		  CFLAGS=&quot;$(CFLAGS)&quot; CXXFLAGS=&quot;$(CXXFLAGS)&quot; \
		  CPP=&quot;$(CPP)&quot; LDFLAGS=&quot;$(LDFLAGS)&quot; LIBS=&quot;$(LIBS)&quot; \
		  LOCAL_CLANG=$(CLANG_PREFIX)/bin/clang \
		  CLANG_PREFIX=$(CLANG_PREFIX) \
		  CLANG_INCLUDES=$(CLANG_INCLUDES))
		$(QUIET)$(call silent_on_success,Running facebook-clang-plugins/clang-ocaml/ tests,\
		$(MAKE) -C $(FCP_DIR)/clang-ocaml test \
		  CC=$(CC) CXX=$(CXX) \
		  CFLAGS=&quot;$(CFLAGS)&quot; CXXFLAGS=&quot;$(CXXFLAGS)&quot; \
		  CPP=&quot;$(CPP)&quot; LDFLAGS=&quot;$(LDFLAGS)&quot; LIBS=&quot;$(LIBS)&quot; \
		  LOCAL_CLANG=$(CLANG_PREFIX)/bin/clang \
		  CLANG_PREFIX=$(CLANG_PREFIX) \
		  CLANG_INCLUDES=$(CLANG_INCLUDES))

.PHONY: clang_plugin_test
clang_plugin_test_replace: clang_setup
		$(QUIET)$(call silent_on_success,Running facebook-clang-plugins/libtooling/ record tests,\
		$(MAKE) -C $(FCP_DIR)/libtooling record-test-outputs \
		  CC=$(CC) CXX=$(CXX) \
		  CFLAGS=&quot;$(CFLAGS)&quot; CXXFLAGS=&quot;$(CXXFLAGS)&quot; \
		  CPP=&quot;$(CPP)&quot; LDFLAGS=&quot;$(LDFLAGS)&quot; LIBS=&quot;$(LIBS)&quot; \
		  LOCAL_CLANG=$(CLANG_PREFIX)/bin/clang \
		  CLANG_PREFIX=$(CLANG_PREFIX) \
		  CLANG_INCLUDES=$(CLANG_INCLUDES))
		$(QUIET)$(call silent_on_success,Running facebook-clang-plugins/clang-ocaml/ record tests,\
		$(MAKE) -C $(FCP_DIR)/clang-ocaml record-test-outputs \
		  CC=$(CC) CXX=$(CXX) \
		  CFLAGS=&quot;$(CFLAGS)&quot; CXXFLAGS=&quot;$(CXXFLAGS)&quot; \
		  CPP=&quot;$(CPP)&quot; LDFLAGS=&quot;$(LDFLAGS)&quot; LIBS=&quot;$(LIBS)&quot; \
		  LOCAL_CLANG=$(CLANG_PREFIX)/bin/clang \
		  CLANG_PREFIX=$(CLANG_PREFIX) \
		  CLANG_INCLUDES=$(CLANG_INCLUDES))

.PHONY: ocaml_unit_test
ocaml_unit_test: test_build
	$(QUIET)$(REMOVE_DIR) infer-out-unit-tests
	$(QUIET)$(call silent_on_success,Running OCaml unit tests,\
	INFER_ARGS=--results-dir^infer-out-unit-tests $(BUILD_DIR)/test/inferunit.bc)

define silence_make
  $(1) 2&gt; &gt;(grep -v &#39;warning: \(ignoring old\|overriding\) \(commands\|recipe\) for target&#39;)
endef

.PHONY: $(DIRECT_TESTS:%=direct_%_test)
$(DIRECT_TESTS:%=direct_%_test): infer
	$(QUIET)$(call silent_on_success,Running test: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C \
	  $(INFER_DIR)/tests/codetoanalyze/$(shell printf $@ | cut -f 2 -d _)/$(shell printf $@ | cut -f 3 -d _) \
	  test))

.PHONY: $(DIRECT_TESTS:%=direct_%_print)
$(DIRECT_TESTS:%=direct_%_print): infer
	$(QUIET)$(call silent_on_success,Running: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C \
	  $(INFER_DIR)/tests/codetoanalyze/$(shell printf $@ | cut -f 2 -d _)/$(shell printf $@ | cut -f 3 -d _) \
	  print))

.PHONY: $(DIRECT_TESTS:%=direct_%_clean)
$(DIRECT_TESTS:%=direct_%_clean):
	$(QUIET)$(call silent_on_success,Cleaning: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C \
	  $(INFER_DIR)/tests/codetoanalyze/$(shell printf $@ | cut -f 2 -d _)/$(shell printf $@ | cut -f 3 -d _) \
	  clean))

.PHONY: $(DIRECT_TESTS:%=direct_%_replace)
$(DIRECT_TESTS:%=direct_%_replace): infer
	$(QUIET)$(call silent_on_success,Recording: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C \
	  $(INFER_DIR)/tests/codetoanalyze/$(shell printf $@ | cut -f 2 -d _)/$(shell printf $@ | cut -f 3 -d _) \
	  replace))

.PHONY: direct_tests
direct_tests: $(DIRECT_TESTS:%=direct_%_test)

.PHONY: $(BUILD_SYSTEMS_TESTS:%=build_%_test)
$(BUILD_SYSTEMS_TESTS:%=build_%_test): infer
	$(QUIET)$(call silent_on_success,Running test: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C $(INFER_DIR)/tests/build_systems/$(patsubst build_%_test,%,$@) test))

.PHONY: $(BUILD_SYSTEMS_TESTS:%=build_%_print)
$(BUILD_SYSTEMS_TESTS:%=build_%_print): infer
	$(QUIET)$(call silent_on_success,Running: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C $(INFER_DIR)/tests/build_systems/$(patsubst build_%_print,%,$@) print))

.PHONY: $(BUILD_SYSTEMS_TESTS:%=build_%_clean)
$(BUILD_SYSTEMS_TESTS:%=build_%_clean):
	$(QUIET)$(call silent_on_success,Cleaning: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C $(INFER_DIR)/tests/build_systems/$(patsubst build_%_clean,%,$@) clean))

.PHONY: $(BUILD_SYSTEMS_TESTS:%=build_%_replace)
$(BUILD_SYSTEMS_TESTS:%=build_%_replace): infer
	$(QUIET)$(call silent_on_success,Recording: $(subst _, ,$@),\
	$(call silence_make,\
	$(MAKE) -C $(INFER_DIR)/tests/build_systems/$(patsubst build_%_replace,%,$@) replace))

build_infertop_print build_infertop_test build_infertop_replace: toplevel_test

.PHONY: build_systems_tests
build_systems_tests: $(BUILD_SYSTEMS_TESTS:%=build_%_test)

.PHONY: endtoend_test
endtoend_test: $(BUILD_SYSTEMS_TESTS:%=build_%_test) $(DIRECT_TESTS:%=direct_%_test)

.PHONY: check_missing_mli
check_missing_mli:
	$(QUIET)for x in $$(find $(INFER_DIR)/src -name &quot;*.ml&quot;); do \
	    test -f &quot;$$x&quot;i || echo Missing &quot;$$x&quot;i; done

.PHONY: checkCopyright
checkCopyright: src_build_common
	$(QUIET)$(call silent_on_success,Building checkCopyright,\
	$(MAKE) -C $(SRC_DIR) checkCopyright)

.PHONY: validate-skel
validate-skel:
ifeq ($(IS_FACEBOOK_TREE),yes)
	$(QUIET)$(call silent_on_success,Validating facebook/,\
	$(MAKE) -C facebook validate)
endif

.PHONY: crash_if_not_all_analyzers_enabled
crash_if_not_all_analyzers_enabled:
ifneq ($(BUILD_C_ANALYZERS)+$(BUILD_JAVA_ANALYZERS),yes+yes)
ifneq ($(BUILD_C_ANALYZERS),yes)
	@echo &#39;*** ERROR: Cannot run the full tests: the Clang analyzers are disabled.&#39;
	@echo &#39;*** ERROR: You can run clang-only tests with:&#39;
	@echo &#39;*** ERROR:&#39;
	@echo &#39;*** ERROR:   make config_tests&#39;
	@echo &#39;*** ERROR:&#39;
endif
ifneq ($(BUILD_JAVA_ANALYZERS),yes)
	@echo &#39;*** ERROR: Cannot run the full tests: the Java analyzers are disabled.&#39;
	@echo &#39;*** ERROR: You can run Java-only tests with:&#39;
	@echo &#39;*** ERROR:&#39;
	@echo &#39;*** ERROR:   make config_tests&#39;
	@echo &#39;*** ERROR:&#39;
endif
	@echo &#39;*** ERROR: To run the full set of tests, please enable all the analyzers.&#39;
	@exit 1
else
	@:
endif

.PHONY: mod_dep
mod_dep: src_build_common
	$(QUIET)$(call silent_on_success,Building Infer source dependency graph,\
	$(MAKE) -C $(SRC_DIR) mod_dep.dot)

.PHONY: config_tests
config_tests: test_build ocaml_unit_test endtoend_test checkCopyright validate-skel mod_dep

ifneq ($(filter config_tests test,${MAKECMDGOALS}),)
test_build: src_build
checkCopyright: src_build test_build
endif

.PHONY: test
test: crash_if_not_all_analyzers_enabled config_tests
ifeq (,$(findstring s,$(MAKEFLAGS)))
	$(QUIET)echo &quot;$(TERM_INFO)ALL TESTS PASSED$(TERM_RESET)&quot;
endif

.PHONY: quick-test
quick-test: test_build ocaml_unit_test

.PHONY: test-replace
test-replace: $(BUILD_SYSTEMS_TESTS:%=build_%_replace) $(DIRECT_TESTS:%=direct_%_replace) \
              clang_plugin_test_replace

.PHONY: uninstall
uninstall:
	$(REMOVE_DIR) $(DESTDIR)$(libdir)/infer/
	$(REMOVE) $(DESTDIR)$(bindir)/infer
	$(REMOVE) $(INFER_COMMANDS:%=$(DESTDIR)$(bindir)/%)
	$(REMOVE) $(foreach manual,$(INFER_GROFF_MANUALS_GZIPPED),\
	  $(DESTDIR)$(mandir)/man1/$(notdir $(manual)))
ifeq ($(IS_FACEBOOK_TREE),yes)
	$(MAKE) -C facebook uninstall
endif

.PHONY: test_clean
test_clean: $(DIRECT_TESTS:%=direct_%_clean) $(BUILD_SYSTEMS_TESTS:%=build_%_clean)

.PHONY: install
install: infer $(INFER_GROFF_MANUALS_GZIPPED)
# create directory structure
	test -d      &#39;$(DESTDIR)$(bindir)&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(bindir)&#39;
	test -d      &#39;$(DESTDIR)$(mandir)/man1&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(mandir)/man1&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/&#39;
ifeq ($(BUILD_C_ANALYZERS),yes)
	test -d      &#39;$(DESTDIR)$(libdir)/infer/facebook-clang-plugins/libtooling/build/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/facebook-clang-plugins/libtooling/build/&#39;
	find facebook-clang-plugins/clang/install/. -type d -print0 | xargs -0 -n 1 \
	  $(SHELL) -x -c &quot;test -d &#39;$(DESTDIR)$(libdir)&#39;/infer/\$$1 || \
	    $(MKDIR_P) &#39;$(DESTDIR)$(libdir)&#39;/infer/\$$1&quot; --
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/clang_wrappers/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/clang_wrappers/&#39;
	find infer/models/cpp/include -type d -print0 | xargs -0 -n 1 \
	  $(SHELL) -x -c &quot;test -d &#39;$(DESTDIR)$(libdir)&#39;/infer/\$$1 || \
	    $(MKDIR_P) &#39;$(DESTDIR)$(libdir)&#39;/infer/\$$1&quot; --
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/linter_rules/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/linter_rules/&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/etc/&#39; || \
		$(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/etc&#39;
endif
ifeq ($(BUILD_JAVA_ANALYZERS),yes)
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/java/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/java/&#39;
endif
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/annotations/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/annotations/&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/wrappers/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/wrappers/&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/specs/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/specs/&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/python/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/python/&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/python/inferlib/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/python/inferlib/&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/lib/python/inferlib/capture/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/lib/python/inferlib/capture/&#39;
	test -d      &#39;$(DESTDIR)$(libdir)/infer/infer/bin/&#39; || \
	  $(MKDIR_P) &#39;$(DESTDIR)$(libdir)/infer/infer/bin/&#39;
# copy files
ifeq ($(BUILD_C_ANALYZERS),yes)
	$(INSTALL_DATA) -C          &#39;facebook-clang-plugins/libtooling/build/FacebookClangPlugin.dylib&#39; \
	  &#39;$(DESTDIR)$(libdir)/infer/facebook-clang-plugins/libtooling/build/FacebookClangPlugin.dylib&#39;
#	do not use &quot;install&quot; for symbolic links as this will copy the destination file instead
	find facebook-clang-plugins/clang/install/. -not -type d -not -type l -not -name &#39;*.a&#39; -print0 \
	  | xargs -0 -I \{\} $(INSTALL_PROGRAM) -C \{\} &#39;$(DESTDIR)$(libdir)&#39;/infer/\{\}
#	all the symlinks in clang are relative and safe to brutally copy over
	find facebook-clang-plugins/clang/install/. -type l -not -name &#39;*.a&#39; -print0 \
	  | xargs -0 -I \{\} $(COPY) -a \{\} &#39;$(DESTDIR)$(libdir)&#39;/infer/\{\}
	find infer/lib/clang_wrappers/* -print0 | xargs -0 -I \{\} \
	  $(INSTALL_PROGRAM) -C \{\} &#39;$(DESTDIR)$(libdir)&#39;/infer/\{\}
#	only for files that point to infer
	(cd &#39;$(DESTDIR)$(libdir)/infer/infer/lib/wrappers/&#39; &amp;&amp; \
	 $(foreach cc,$(shell find &#39;$(LIB_DIR)/wrappers&#39; -type l), \
	  [ $(cc) -ef &#39;$(INFER_BIN)&#39; ] &amp;&amp; \
	  $(REMOVE) &#39;$(notdir $(cc))&#39; &amp;&amp; \
	  $(LN_S) ../../bin/infer &#39;$(notdir $(cc))&#39;;))
	find infer/lib/specs/* -print0 | xargs -0 -I \{\} \
	  $(INSTALL_DATA) -C \{\} &#39;$(DESTDIR)$(libdir)&#39;/infer/\{\}
	find infer/models/cpp/include -not -type d -print0 | xargs -0 -I \{\} \
		$(INSTALL_DATA) -C \{\} &#39;$(DESTDIR)$(libdir)&#39;/infer/\{\}
	$(INSTALL_DATA) -C          &#39;infer/lib/linter_rules/linters.al&#39; \
	  &#39;$(DESTDIR)$(libdir)/infer/infer/lib/linter_rules/linters.al&#39;
	$(INSTALL_DATA) -C          &#39;infer/etc/clang_ast.dict&#39; \
	  &#39;$(DESTDIR)$(libdir)/infer/infer/etc/clang_ast.dict&#39;
endif
ifeq ($(BUILD_JAVA_ANALYZERS),yes)
	$(INSTALL_DATA) -C          &#39;infer/annotations/annotations.jar&#39; \
	  &#39;$(DESTDIR)$(libdir)/infer/infer/annotations/annotations.jar&#39;
	find infer/lib/java/*.jar -print0 | xargs -0 -I \{\} \
	  $(INSTALL_DATA) -C \{\} &#39;$(DESTDIR)$(libdir)&#39;/infer/\{\}
	$(INSTALL_PROGRAM) -C      &#39;$(LIB_DIR)&#39;/wrappers/javac \
	  &#39;$(DESTDIR)$(libdir)&#39;/infer/infer/lib/wrappers/
endif
	find infer/lib/python/inferlib/* -type f -print0 | xargs -0 -I \{\} \
	  $(INSTALL_DATA) -C \{\} &#39;$(DESTDIR)$(libdir)&#39;/infer/\{\}
	$(INSTALL_PROGRAM) -C       infer/lib/python/infer.py \
	  &#39;$(DESTDIR)$(libdir)&#39;/infer/infer/lib/python/infer.py
	$(INSTALL_PROGRAM) -C       infer/lib/python/inferTraceBugs \
	  &#39;$(DESTDIR)$(libdir)&#39;/infer/infer/lib/python/inferTraceBugs
	$(INSTALL_PROGRAM) -C       infer/lib/python/report.py \
	  &#39;$(DESTDIR)$(libdir)&#39;/infer/infer/lib/python/report.py
	$(INSTALL_PROGRAM) -C &#39;$(INFER_BIN)&#39; &#39;$(DESTDIR)$(libdir)&#39;/infer/infer/bin/
	(cd &#39;$(DESTDIR)$(bindir)/&#39; &amp;&amp; \
	 $(REMOVE) infer &amp;&amp; \
	 $(LN_S) &#39;$(libdir_relative_to_bindir)&#39;/infer/infer/bin/infer infer)
	for alias in $(INFER_COMMANDS); do \
	  (cd &#39;$(DESTDIR)$(bindir)&#39;/ &amp;&amp; \
	   $(REMOVE) &quot;$$alias&quot; &amp;&amp; \
	   $(LN_S) infer &quot;$$alias&quot;); done
	for alias in $(INFER_COMMANDS); do \
	  (cd &#39;$(DESTDIR)$(libdir)&#39;/infer/infer/bin &amp;&amp; \
	   $(REMOVE) &quot;$$alias&quot; &amp;&amp; \
	   $(LN_S) infer &quot;$$alias&quot;); done
	$(foreach man,$(INFER_GROFF_MANUALS_GZIPPED), \
	  $(INSTALL_DATA) -C $(man) &#39;$(DESTDIR)$(mandir)/man1/$(notdir $(man))&#39;;)
ifeq ($(IS_FACEBOOK_TREE),yes)
ifdef DESTDIR
ifeq (,$(findstring :/,:$(DESTDIR)))
#	DESTDIR is set and relative
	$(MAKE) -C facebook install &#39;DESTDIR=../$(DESTDIR)&#39;
else
#	DESTDIR is set and absolute
	$(MAKE) -C facebook install
endif
else
#	DESTDIR not set
	$(MAKE) -C facebook install
endif
endif

# Nuke objects built from OCaml. Useful when changing the OCaml compiler, for instance.
.PHONY: ocaml_clean
ocaml_clean:
ifeq ($(BUILD_C_ANALYZERS),yes)
	$(QUIET)$(call silent_on_success,Cleaning facebook-clang-plugins OCaml build,\
	$(MAKE) -C $(FCP_DIR)/clang-ocaml clean)
endif
	$(QUIET)$(call silent_on_success,Cleaning infer OCaml build,\
	$(MAKE) -C $(SRC_DIR) clean)
	$(QUIET)$(call silent_on_success,Cleaning ocamldot,\
	$(MAKE) -C $(DEPENDENCIES_DIR)/ocamldot clean)

.PHONY: clean
clean: test_clean ocaml_clean
ifeq ($(BUILD_C_ANALYZERS),yes)
	$(QUIET)$(call silent_on_success,Cleaning facebook-clang-plugins C++ build,\
	$(MAKE) -C $(FCP_DIR) clean)
endif
	$(QUIET)$(call silent_on_success,Cleaning Java annotations,\
	$(MAKE) -C $(ANNOTATIONS_DIR) clean)
	$(QUIET)$(call silent_on_success,Cleaning infer models,\
	$(MAKE) -C $(MODELS_DIR) clean)
ifeq ($(IS_FACEBOOK_TREE),yes)
	$(QUIET)$(call silent_on_success,Cleaning facebook/,\
	$(MAKE) -C facebook clean)
endif
	$(QUIET)$(call silent_on_success,Removing *.o and *.o.sh,\
	find $(INFER_DIR)/tests \( -name &#39;*.o&#39; -o -name &#39;*.o.sh&#39; \) -delete)
	$(QUIET)$(call silent_on_success,Removing build logs,\
	$(REMOVE_DIR) _build_logs $(MAN_DIR))

.PHONY: conf-clean
conf-clean: clean
	$(REMOVE) $(PYTHON_DIR)/inferlib/*.pyc
	$(REMOVE) $(PYTHON_DIR)/inferlib/*/*.pyc
	$(REMOVE) .buckversion
	$(REMOVE) Makefile.config
	$(REMOVE) acinclude.m4
	$(REMOVE) aclocal.m4
	$(REMOVE_DIR) autom4te.cache/
	$(REMOVE) config.log
	$(REMOVE) config.status
	$(REMOVE) configure
	$(REMOVE_DIR) $(MODELS_DIR)/c/out/
	$(REMOVE_DIR) $(MODELS_DIR)/cpp/out/
	$(REMOVE_DIR) $(MODELS_DIR)/java/infer-out/
	$(REMOVE_DIR) $(MODELS_DIR)/objc/out/


# phony because it depends on opam&#39;s internal state
.PHONY: opam.locked
opam.locked: opam
# allow users to not force a run of opam update since it&#39;s very slow
ifeq ($(NO_OPAM_UPDATE),)
	$(QUIET)$(call silent_on_success,opam update,$(OPAM) update)
endif
	$(QUIET)$(call silent_on_success,generating opam.locked,\
	  $(OPAM) lock .)

# This is a magical version number that doesn&#39;t reinstall the world when added on top of what we
# have in opam.locked. To upgrade this version number, manually try to install several utop versions
# until you find one that doesn&#39;t recompile the world. TODO(t20828442): get rid of magic
OPAM_DEV_DEPS = ocamlformat.0.8 ocp-indent merlin utop.2.2.0 webbrowser

ifneq ($(EMACS),no)
OPAM_DEV_DEPS += tuareg
endif

.PHONY: devsetup
devsetup: Makefile.autoconf
	$(QUIET)[ $(OPAM) != &quot;no&quot; ] || (echo &#39;No `opam` found, aborting setup.&#39; &gt;&amp;2; exit 1)
	$(QUIET)$(call silent_on_success,installing $(OPAM_DEV_DEPS),\
	  OPAMSWITCH=$(OPAMSWITCH); $(OPAM) install --yes --no-checksum user-setup $(OPAM_DEV_DEPS))
	$(QUIET)echo &#39;$(TERM_INFO)*** Running `opam user-setup`$(TERM_RESET)&#39; &gt;&amp;2
	$(QUIET)OPAMSWITCH=$(OPAMSWITCH); OPAMYES=1; $(OPAM) user-setup install
	$(QUIET)if [ &quot;$(PLATFORM)&quot; = &quot;Darwin&quot; ] &amp;&amp; [ x&quot;$(GNU_SED)&quot; = x&quot;no&quot; ]; then \
	  echo &#39;$(TERM_INFO)*** Installing GNU sed$(TERM_RESET)&#39; &gt;&amp;2; \
	  brew install gnu-sed; \
	fi
	$(QUIET)if [ &quot;$(PLATFORM)&quot; = &quot;Darwin&quot; ] &amp;&amp; ! $$(parallel -h | grep -q GNU); then \
	  echo &#39;$(TERM_INFO)*** Installing GNU parallel$(TERM_RESET)&#39; &gt;&amp;2; \
	  brew install parallel; \
	fi
	$(QUIET)if [ ! -d &quot;$$HOME&quot;/.parallel ]; then mkdir &quot;$$HOME&quot;/.parallel; fi
	$(QUIET)touch &quot;$$HOME&quot;/.parallel/will-cite
# 	expand all occurrences of &quot;~&quot; in PATH and MANPATH
	$(QUIET)infer_repo_is_in_path=$$(echo $${PATH//\~/$$HOME} | grep -q &quot;$(ABSOLUTE_ROOT_DIR)&quot;/infer/bin; echo $$?); \
	infer_repo_is_in_manpath=$$(echo $${MANPATH//\~/$$HOME} | grep -q &quot;$(ABSOLUTE_ROOT_DIR)&quot;/infer/man; echo $$?); \
	shell_config_file=&quot;&lt;could not auto-detect, please fill in yourself&gt;&quot;; \
	if [ $$(basename &quot;$(ORIG_SHELL)&quot;) = &quot;bash&quot; ]; then \
	  if [ &quot;$(PLATFORM)&quot; = &quot;Linux&quot; ]; then \
	    shell_config_file=&quot;$$HOME&quot;/.bashrc; \
	  else \
	    shell_config_file=&quot;$$HOME&quot;/.bash_profile; \
	  fi; \
	elif [ $$(basename &quot;$(ORIG_SHELL)&quot;) = &quot;zsh&quot; ]; then \
	  shell_config_file=&quot;$$HOME&quot;/.zshrc; \
	fi; \
	if [ &quot;$$infer_repo_is_in_path&quot; != &quot;0&quot; ] || [ &quot;$$infer_repo_is_in_manpath&quot; != &quot;0&quot; ]; then \
	  echo &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: `infer` is not in your PATH or MANPATH. If you are hacking on infer, you may$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: want to make infer executables and manuals available in your terminal. Type$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: the following commands to configure the current terminal and record the$(TERM_RESET)&#39; &gt;&amp;2; \
	  printf &#39;$(TERM_INFO)*** NOTE: changes in your shell configuration file (%s):$(TERM_RESET)\n&#39; &quot;$$shell_config_file&quot;&gt;&amp;2; \
	  echo &gt;&amp;2; \
	  if [ &quot;$$infer_repo_is_in_path&quot; != &quot;0&quot; ]; then \
	    printf &#39;$(TERM_INFO)  export PATH=&quot;%s/infer/bin&quot;:$$PATH$(TERM_RESET)\n&#39; &quot;$(ABSOLUTE_ROOT_DIR)&quot; &gt;&amp;2; \
	  fi; \
	  if [ &quot;$$infer_repo_is_in_manpath&quot; != &quot;0&quot; ]; then \
	    printf &#39;$(TERM_INFO)  export MANPATH=&quot;%s/infer/man&quot;:$$MANPATH$(TERM_RESET)\n&#39; &quot;$(ABSOLUTE_ROOT_DIR)&quot; &gt;&amp;2; \
	  fi; \
	  if [ &quot;$$infer_repo_is_in_path&quot; != &quot;0&quot; ]; then \
	    printf &quot;$(TERM_INFO)  echo &#39;export PATH=\&quot;%s/infer/bin\&quot;:\$$PATH&#39; &gt;&gt; \&quot;$$shell_config_file\&quot;$(TERM_RESET)\n&quot; &quot;$(ABSOLUTE_ROOT_DIR)&quot; &gt;&amp;2; \
	  fi; \
	  if [ &quot;$$infer_repo_is_in_manpath&quot; != &quot;0&quot; ]; then \
	    printf &quot;$(TERM_INFO)  echo &#39;export MANPATH=\&quot;%s/infer/man\&quot;:\$$MANPATH&#39; &gt;&gt; \&quot;$$shell_config_file\&quot;$(TERM_RESET)\n&quot; &quot;$(ABSOLUTE_ROOT_DIR)&quot; &gt;&amp;2; \
	  fi; \
	fi; \
	if [ -z &quot;$(ORIG_SHELL_BUILD_MODE)&quot; ]; then \
	  echo &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: Set `BUILD_MODE=default` in your shell to disable flambda by default.$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: Compiling with flambda is ~5 times slower than without, so unless you are$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: testing infer on a very large project it will not be worth it. Use the$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: commands below to set the default build mode. You can then use `make opt`$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: when you really do want to enable flambda.$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &gt;&amp;2; \
	  printf &quot;$(TERM_INFO)  export BUILD_MODE=default$(TERM_RESET)\n&quot; &gt;&amp;2; \
	  printf &quot;$(TERM_INFO)  echo &#39;export BUILD_MODE=default&#39; &gt;&gt; \&quot;$$shell_config_file\&quot;$(TERM_RESET)\n&quot; &gt;&amp;2; \
	fi
	$(QUIET)PATH=$(ORIG_SHELL_PATH); if [ &quot;$$(ocamlc -where 2&gt;/dev/null)&quot; != &quot;$$($(OCAMLC) -where)&quot; ]; then \
	  echo &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: The current shell is not set up for the right opam switch.$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &#39;$(TERM_INFO)*** NOTE: Please run:$(TERM_RESET)&#39; &gt;&amp;2; \
	  echo &gt;&amp;2; \
	  echo &quot;$(TERM_INFO)  eval \$$($(OPAM) env)$(TERM_RESET)&quot; &gt;&amp;2; \
	fi

GHPAGES ?= no

.PHONY: doc
doc: src_build_common
	$(QUIET)$(call silent_on_success,Generating infer documentation,\
	$(MAKE_SOURCE) doc)
# do not call the browser if we are publishing the docs
ifeq ($(filter doc-publish,${MAKECMDGOALS}),)
	$(QUIET)$(call silent_on_success,Opening in browser,\
	browse $(SRC_DIR)/_build/$(BUILD_MODE)/_doc/_html/index.html)
	$(QUIET)echo &quot;Tip: you can generate the doc for all the opam dependencies of infer like this:&quot;
	$(QUIET)echo
	$(QUIET)echo &quot;  odig odoc # takes a while, run it only when the dependencies change&quot;
	$(QUIET)echo &quot;  odig doc&quot;
endif

.PHONY: doc-publish
doc-publish: doc $(INFER_GROFF_MANUALS)
ifeq ($(GHPAGES),no)
	$(QUIET)echo &quot;$(TERM_ERROR)Please set GHPAGES to a checkout of the gh-pages branch of the GitHub repo of infer$(TERM_RESET)&quot; &gt;&amp;2
	$(QUIET)exit 1
endif
#	sanity check to avoid cryptic error messages and potentially annoying side-effects
	$(QUIET)if ! [ -d &quot;$(GHPAGES)&quot;/static/man ]; then \
	  echo &quot;$(TERM_ERROR)ERROR: GHPAGES doesn&#39;t seem to point to a checkout of the gh-pages branch of the GitHub repo of infer:$(TERM_RESET)&quot; &gt;&amp;2; \
	  echo &quot;$(TERM_ERROR)ERROR:   &#39;$(GHPAGES)/static/man&#39; not found or not a directory.$(TERM_RESET)&quot; &gt;&amp;2; \
	  echo &quot;$(TERM_ERROR)ERROR: Please fix this and try again.$(TERM_RESET)&quot; &gt;&amp;2; \
	  exit 1; \
	fi
	$(QUIET)$(call silent_on_success,Copying man pages,\
	$(REMOVE_DIR) &quot;$(GHPAGES)&quot;/static/man/*; \
	for man in $(INFER_GROFF_MANUALS); do \
	  groff -Thtml &quot;$$man&quot; &gt; &quot;$(GHPAGES)&quot;/static/man/$$(basename &quot;$$man&quot;).html; \
	done)
ifeq ($(IS_FACEBOOK_TREE),no)
	$(QUIET)$(call silent_on_success,Copying OCaml modules documentation,\
	version=$$($(INFER_BIN) --version | head -1 | cut -d &#39; &#39; -f 3 | cut -c 2-); \
	rsync -a --delete $(SRC_DIR)/_build/$(BUILD_MODE)/_doc/_html/ &quot;$(GHPAGES)&quot;/static/odoc/&quot;$$version&quot;; \
	$(REMOVE) &quot;$(GHPAGES)&quot;/static/odoc/latest; \
	$(LN_S) &quot;$$version&quot; &quot;$(GHPAGES)&quot;/static/odoc/latest)
else
	$(QUIET)echo &quot;Not an open-source tree, skipping the API docs generation&quot;
endif

# print list of targets
.PHONY: show-targets
show-targets:
	$(QUIET)$(MAKE) -pqrR . | grep --only-matching -e &#39;^[a-zA-Z0-9][^ ]*:&#39; | cut -d &#39;:&#39; -f 1 | sort
