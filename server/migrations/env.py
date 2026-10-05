from logging.config import fileConfig

from alembic import context

from copycore.config import env_database_url
from copycore.db import make_engine
from copycore.models import Base

config = context.config
if config.config_file_name is not None and config.attributes.get("configure_logger", True):
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = Base.metadata


def run_migrations_online() -> None:
    connection = config.attributes.get("connection")
    if connection is not None:
        _run(connection)
        return
    url = config.get_main_option("sqlalchemy.url") or env_database_url()
    engine = make_engine(url)
    with engine.connect() as conn:
        _run(conn)
    engine.dispose()


def _run(connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata,
                      render_as_batch=connection.dialect.name == "sqlite", compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


if context.is_offline_mode():
    raise SystemExit("offline mode is not supported")
run_migrations_online()
