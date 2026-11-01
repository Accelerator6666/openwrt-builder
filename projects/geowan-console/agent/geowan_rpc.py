"""Read-only rpcd lookup API for the GeoWAN LuCI application."""
import ipaddress
import sqlite3
from pathlib import Path

from geowan_geoip import GEOIP_DIR, GeoIPResolver, read_metadata

DB = Path("/etc/geowan-console/telemetry.sqlite3")


def lookup(request, db_path=DB, resolver_factory=GeoIPResolver):
    value = request.get("ip") if isinstance(request, dict) else None
    if not isinstance(value, str) or not value.strip() or len(value) > 64:
        return {"ip": str(value or ""), "lookup_status": "invalid"}

    try:
        address = ipaddress.ip_address(value.strip())
    except ValueError:
        return {"ip": value.strip(), "lookup_status": "invalid"}

    version = str(read_metadata().get("release") or "unknown")
    if address.is_global:
        try:
            conn = sqlite3.connect(
                "file:" + str(db_path) + "?mode=ro", uri=True, timeout=2
            )
            row = conn.execute(
                "SELECT country_code,country_name,continent_code,continent_name,"
                "region,city,asn,asn_org,provider,database_version,lookup_status "
                "FROM geoip_cache WHERE ip=?",
                (str(address),)
            ).fetchone()
            conn.close()
            if row and row[9] == version:
                keys = (
                    "country_code", "country_name", "continent_code",
                    "continent_name", "region", "city", "asn", "asn_org",
                    "provider", "database_version", "lookup_status"
                )
                return {"ip": str(address), **dict(zip(keys, row))}
        except (OSError, sqlite3.Error):
            pass

    resolver = resolver_factory()
    try:
        return resolver.lookup(str(address))
    finally:
        resolver.close()


def dispatch(method, request):
    if method == "lookup":
        return lookup(request)
    return {"error": "unknown_method"}
