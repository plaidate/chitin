# Fightin' Chitin - insect fighting game for Playdate.
#
#   make            release build -> out/Chitin.pdx
#   make smoke      instrumented build -> out/ChitinSmoke.pdx
#
# Staging copies source/* into build/<variant>/source and writes the generated
# smokeflag.lua (pdc wants one source root).

OUT := out

all: release

release: build/release/source
	pdc build/release/source $(OUT)/Chitin.pdx

smoke: build/smoke/source
	pdc build/smoke/source $(OUT)/ChitinSmoke.pdx

# balance = a smoke build that also loops AI-vs-AI through every matchup and
# writes a win-rate matrix to the datastore (see tools/balance.sh).
balance: build/balance/source
	pdc build/balance/source $(OUT)/ChitinBalance.pdx

build/release/source: source/*
	mkdir -p $@ $(OUT)
	cp source/* $@/
	echo 'SMOKE_BUILD = false' > $@/smokeflag.lua

build/smoke/source: source/*
	mkdir -p $@ $(OUT)
	cp source/* $@/
	echo 'SMOKE_BUILD = true' > $@/smokeflag.lua
	echo 'SHOT_PATH = "$(CURDIR)/build/chitin-shot.png"' >> $@/smokeflag.lua

build/balance/source: source/*
	mkdir -p $@ $(OUT)
	cp source/* $@/
	echo 'SMOKE_BUILD = true' > $@/smokeflag.lua
	echo 'BALANCE_BUILD = true' >> $@/smokeflag.lua
	echo 'SHOT_PATH = "$(CURDIR)/build/chitin-shot.png"' >> $@/smokeflag.lua

clean:
	rm -rf build $(OUT)

.PHONY: all release smoke balance clean
