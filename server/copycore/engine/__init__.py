"""Copy engine (design 3.1): snapshot diff, fan-out, lots, symbol mapping, admission, commands.

No FastAPI imports here: the engine takes a SQLAlchemy session and plain data and returns
state changes; routers translate HTTP to and from it.
"""
