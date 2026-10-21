# Project Makefile: Prime Brokerage Clearing, SPAN Margin & AI Risk Engine
COBC       := cobc
COBC_FLAGS := -Wall -I copybooks
PYTHON     := python3

TARGET_BIN := bin/CLRENGIN
MAIN_SRC   := src/CLRENGIN.cbl
SUB_SRC    := src/RISKAUDT.cbl

.PHONY: all data build run verify clean

all: data run

data:
	$(PYTHON) python/ai_anomaly_scorer.py

build: $(MAIN_SRC) $(SUB_SRC)
	@mkdir -p bin output
	$(COBC) -x $(COBC_FLAGS) -o $(TARGET_BIN) $(MAIN_SRC) $(SUB_SRC)

run: data
	@mkdir -p output
	@if command -v $(COBC) >/dev/null 2>&1; then \
		$(MAKE) build && ./$(TARGET_BIN); \
	else \
		echo "[INFO] GnuCOBOL (cobc) not detected locally; running exact fixed-point reference engine (install with 'brew install gnucobol' to compile native binary)"; \
		$(PYTHON) python/verify_clearing_math.py; \
	fi

verify:
	$(PYTHON) python/verify_clearing_math.py

clean:
	rm -rf bin/
