import sqlite3
import sys
from pathlib import Path
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agent"))
import geowan_rpc


class FakeResolver:
    available = True
    version = "2026-11"

    def lookup(self, ip):
        return {
            "ip": ip,
            "country_code": "US",
            "country_name": "美国",
            "city": "Mountain View",
            "asn": 15169,
            "asn_org": "Google LLC",
            "lookup_status": "ok"
        }

    def close(self):
        pass


class RpcLookupTests(unittest.TestCase):
    def test_invalid_ip_is_rejected_before_database_access(self):
        result = geowan_rpc.lookup({"ip": "bad address"})
        self.assertEqual(result["lookup_status"], "invalid")

    def test_cached_lookup_uses_current_database_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "telemetry.sqlite3"
            conn = sqlite3.connect(path)
            conn.execute("""CREATE TABLE geoip_cache(
                ip TEXT PRIMARY KEY,country_code TEXT,country_name TEXT,
                continent_code TEXT,continent_name TEXT,region TEXT,city TEXT,
                asn INTEGER,asn_org TEXT,provider TEXT,database_version TEXT,
                lookup_status TEXT,updated_at INTEGER
            )""")
            conn.execute(
                "INSERT INTO geoip_cache VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                ("8.8.8.8", "US", "美国", "NA", "北美洲", "California",
                 "Mountain View", 15169, "Google LLC", "DB-IP Lite",
                 "2026-11", "ok", 1800000000)
            )
            conn.commit()
            conn.close()

            with mock.patch.object(
                geowan_rpc, "read_metadata", return_value={"release": "2026-11"}
            ):
                result = geowan_rpc.lookup(
                    {"ip": "8.8.8.8"}, db_path=path,
                    resolver_factory=lambda: self.fail("cache should be used")
                )
            self.assertEqual(result["country_code"], "US")
            self.assertEqual(result["asn"], 15169)

    def test_uncached_lookup_uses_local_resolver(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = geowan_rpc.lookup(
                {"ip": "8.8.4.4"},
                db_path=Path(tmp) / "missing.sqlite3",
                resolver_factory=FakeResolver
            )
            self.assertEqual(result["country_code"], "US")
            self.assertEqual(result["city"], "Mountain View")


if __name__ == "__main__":
    unittest.main()
