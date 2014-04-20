EXTENSION = pg_monitoring
DATA = $(shell echo *.sql)

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
