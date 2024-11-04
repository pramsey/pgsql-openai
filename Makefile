
EXTENSION = openai

DATA = $(wildcard *.sql)
FUNCTIONS = $(wildcard sql/*.sql)

REGRESS = openai
EXTRA_CLEAN =

PG_CONFIG = pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

