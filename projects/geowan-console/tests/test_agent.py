import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agent"))
import geowan_agent as g


class AgentTests(unittest.TestCase):
    def test_ipv4_nft_member_expiry_milliseconds(self):
        self.assertEqual(
            g.parse_member({"elem": {"val": "8.8.8.8", "expires": 120000}}, 4),
            ("8.8.8.8", 120),
        )
        self.assertIsNone(g.parse_member({"elem": {"val": "8.8.8.8"}}, 6))
        self.assertIsNone(g.parse_member({"elem": {"val": "bad-data"}}, 4))

    def test_nft_json_inventory(self):
        example = {"nftables": [{"metainfo": {}}, {"set": {
            "name": "geo_black4", "elem": [
                {"elem": {"val": "8.8.8.8", "expires": 30000}},
                {"elem": {"val": "1.1.1.1", "expires": 60000}}
            ]
        }}]}
        with mock.patch.object(g, "cmd", return_value=json.dumps(example)):
            result = g.read_members(4)
        self.assertEqual(result, {"8.8.8.8": 30, "1.1.1.1": 60})

    def test_log_parsing_and_injection_rejection(self):
        line = (
            "Sat Oct 31 00:42:00 2026 kern.warn kernel: GEOWAN4 "
            "IN=pppoe-wan SRC=8.8.8.8 DST=10.0.0.61 "
            "PROTO=TCP SPT=40001 DPT=31080"
        )
        row = g.parse_log(line, 1793436120, "boot1")
        self.assertEqual(row[2:7], (4, "8.8.8.8", "10.0.0.61", 31080, "TCP"))
        self.assertIsNone(g.parse_log("GEOWAN4 SRC=not-an-ip", 123, "boot"))

    def test_sqlite_retention_and_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(g, "DB", Path(tmp) / "db.sqlite"):
                conn = g.db_open()
                now = 1800000000
                conn.execute("INSERT INTO events VALUES(?,?,?,?,?,?,?)",
                             ("abc", now - 20, 4, "8.8.8.8", "10.0.0.61", 31080, "TCP"))
                conn.execute("INSERT INTO bans VALUES(?,?,?,?,?)",
                             ("8.8.8.8", 4, now - 100, now - 20, now + 500))
                conn.commit()
                with mock.patch.object(g, "read_counters", return_value={"black4": 1}):
                    data = g.build_status(conn, now, {"4": 1, "6": 0}, [])
                self.assertEqual(data["samples_24h"], 1)
                self.assertEqual(data["active_bans"], 1)
                self.assertEqual(data["top_ports"][0]["port"], 31080)
                self.assertEqual(len(data["hours"]), 24)
                conn.close()


if __name__ == "__main__":
    unittest.main()
