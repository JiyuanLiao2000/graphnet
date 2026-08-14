"""Modules for reading experiment-specific data and applying Extractors."""
from .graphnet_file_reader import GraphNeTFileReader
from .i3reader import I3Reader
from .internal_parquet_reader import ParquetReader

def __getattr__(name):
    """Lazily import optional readers and their dependencies."""
    if name == "LiquidOReader":
        from .liquido_reader import LiquidOReader
        return LiquidOReader
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
from .prometheus_reader import PrometheusReader
