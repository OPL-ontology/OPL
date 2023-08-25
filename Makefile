# OPL ontology Makefile
# Jie Zheng
#
# This Makefile is used to build artifacts
# for the Ontology for Parasite Lifecycle.
#

### Configuration
#
# prologue:
# <http://clarkgrubb.com/makefile-style-guide#toc2>

MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:

### Definitions

SHELL   := /bin/bash
OBO     := http://purl.obolibrary.org/obo
OPL  := $(OBO)/OPL_
TODAY   := $(shell date +%Y-%m-%d)

### Directories
#
# This is a temporary place to put things.
build:
	mkdir -p $@


### ROBOT
#
# We use the latest official release version of ROBOT
build/robot.jar: | build
	curl -L -o $@ "https://github.com/ontodev/robot/releases/latest/download/robot.jar"

ROBOT := java -jar build/robot.jar


### Imports
#
# Use Ontofox to import various modules.
build/import_%.owl: src/ontology/OntoFox_input/input_%.txt | build/robot.jar build
	curl -s -F file=@$< -o $@ https://ontofox.hegroup.org/service.php

# Use ROBOT to remove external java axioms
src/ontology/import/import_%.owl: build/import_%.owl
	$(ROBOT) remove --input build/import_$*.owl \
	--base-iri 'http://purl.obolibrary.org/obo/$*_' \
	--axioms external \
	--preserve-structure false \
	--trim false \
	--output $@ 

IMPORT_FILES := $(wildcard src/ontology/import/import_*.owl)

.PHONY: imports
imports: $(IMPORT_FILES)


### Templates
#
src/ontology/modules/%.owl: src/ontology/templates/%.tsv | build/robot.jar
	echo '' > $@
	$(ROBOT) merge \
	--input src/ontology/opl_dev.owl \
	template \
	--template $< \
	annotate \
	--ontology-iri "http://purl.obolibrary.org/obo/opl/dev/$(notdir $@)" \
	--output $@

# Update all modules
MODULE_NAMES := opl_terms\
 opl_misc\
 opl_anatomical_entity\
 opl_development_stage\
 opl_development_stage_occurs_in\
 opl_organism\
 opl_organism_located_in\
 ncbitaxon_axioms\
 opl_obsolete

MODULE_FILES := $(foreach x,$(MODULE_NAMES),src/ontology/modules/$(x).owl)

.PHONY: modules
modules: $(MODULE_FILES)


### Build
#
# Here we create a standalone OWL file appropriate for release.
# This involves merging, reasoning, annotating,
# and removing any remaining import declarations.
build/opl_merged.owl: src/ontology/opl_dev.owl | build/robot.jar build
	$(ROBOT) merge \
	--input $< \
	annotate \
	--ontology-iri "$(OBO)/opl/opl_merged.owl" \
	--version-iri "$(OBO)/opl/$(TODAY)/opl_merged.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output build/opl_merged.tmp.owl
	sed '/<owl:imports/d' build/opl_merged.tmp.owl > $@
	rm build/opl_merged.tmp.owl

opl.owl: build/opl_merged.owl
	$(ROBOT) reason \
	--input $< \
	--reasoner HermiT \
	annotate \
	--ontology-iri "$(OBO)/opl.owl" \
	--version-iri "$(OBO)/opl/$(TODAY)/opl.owl" \
	--annotation owl:versionInfo "$(TODAY)" \
	--output $@

test_report.tsv: build/opl_merged.owl
	$(ROBOT) report \
	--input $< \
        --fail-on none \
	--output $@

### Test
#
# Run main tests
MERGED_VIOLATION_QUERIES := $(wildcard src/sparql/*-violation.rq)

build/terms-report.csv: build/opl_merged.owl src/sparql/terms-report.rq | build
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/opl-previous-release.owl: | build
	curl -L -o $@ "http://purl.obolibrary.org/obo/opl.owl"

build/released-entities.tsv: build/opl-previous-release.owl src/sparql/get-opl-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/current-entities.tsv: build/opl_merged.owl src/sparql/get-opl-entities.rq | build/robot.jar
	$(ROBOT) query --input $< --select $(word 2,$^) $@

build/dropped-entities.tsv: build/released-entities.tsv build/current-entities.tsv
	comm -23 $^ > $@

# Run all validation queries and exit on error.
.PHONY: verify
verify: verify-merged verify-entities

# Run validation queries on opl_merged and exit on error.
.PHONY: verify-merged
verify-merged: build/opl_merged.owl $(MERGED_VIOLATION_QUERIES) | build/robot.jar
	$(ROBOT) verify --input $< --output-dir build \
	--queries $(MERGED_VIOLATION_QUERIES)

# Check if any entities have been dropped and exit on error.
.PHONY: verify-entities
verify-entities: build/dropped-entities.tsv
	@echo $(shell < $< wc -l) " opl IRIs have been dropped"
	@! test -s $<

# Run a Hermit reasoner to find inconsistencies
.PHONY: reason
reason: build/opl_merged.owl | build/robot.jar
	$(ROBOT) reason --input $< --reasoner HermiT

.PHONY: test
test: reason verify


### General/Users/jiezheng/Documents/ontology/opl
#
# Full build
.PHONY: all
all: test opl.owl build/terms-report.csv

# Remove generated files
.PHONY: clean
clean:
	rm -rf build

# Check for problems such as bad line-endings
.PHONY: check
check:
	src/scripts/check-line-endings.sh tsv

# Fix simple problems such as bad line-endings
.PHONY: fix
fix:
	src/scripts/fix-eol-all.sh
