#!/usr/bin/env python3
"""GeoWAN read-only telemetry, sampled event audit and expiring-set recovery.

Does not edit existing firewall rules, DNAT, GeoIP databases or router services.
Python 3 standard library + sqlite3 only.
"""
import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import time

DB = Path(os.environ.get("GEOWAN_DB", "/etc/geowan-console/telemetry.sqlite3"))
STATUS = Path(os.environ.get("GEOWAN_STATUS", "/tmp/geowan-console/status.json"))
MAX_TTL = 7 * 86400
LOG_MARKER = re.compile(r"\bGEOWAN([46])\b")
FIELD = re.compile(r"\b(SRC|DST|DPT|PROTO|SPT)=([^\s]+)")
SYSLOG_TIME = re.compile(r"^(?:[A-Za-z]{3}\s+)?([A-Za-z]{3}\s+\d{1,2}\s+\d\d:\d\d:\d\d)")
SERVICE_PORTS = {31080: "JumpServer 反代", 20443: "SSL VPN", 3389: "RDP 后端", 58964: "RDP 公网"}


def cmd(*args, input_text=None):
    return subprocess.run(
        list(args), input=input_text, text=True, capture_output=True,
        timeout=40, check=True
    ).stdout


def db_open():
    DB.parent.mkdir(parents=True, exist_ok=True)
    DB.parent.chmod(0o700)
    conn = sqlite3.connect(str(DB), timeout=20)
    conn.execute("PRAGMA busy_timeout=20000")
    conn.execute("""CREATE TABLE IF NOT EXISTS events(
        id TEXT PRIMARY KEY, ts INTEGER NOT NULL, family INTEGER NOT NULL,
        src TEXT NOT NULL, dst TEXT, port INTEGER, proto TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS bans(
        ip TEXT PRIMARY KEY, family INTEGER NOT NULL,
        first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
    )""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts)")
    conn.commit()
    return conn


def parse_member(entry, family):
    """nft JSON versions encode elements as strings or {'elem': {'val':...}}."""
    obj = entry.get("elem", entry) if isinstance(entry, dict) else entry
    if isinstance(obj, dict):
        raw = obj.get("val", obj.get("addr"))
        expires = obj.get("expires")
    else:
        raw, expires = obj, None
    if isinstance(raw, dict):
        raw = raw.get("prefix", raw.get("val"))
    try:
        ip = ipaddress.ip_address(raw)
        if ip.version != family or ip.is_multicast or ip.is_unspecified:
            return None
    except (ValueError, TypeError):
        return None
    seconds = MAX_TTL
    if isinstance(expires, (int, float)):
        # nft -j prints timeout/expires in milliseconds on recent releases.
        seconds = min(MAX_TTL, max(1, int(expires / 1000)))
    return str(ip), seconds


def read_members(family):
    name = f"geo_black{family}"
    data = json.loads(cmd("nft", "-j", "list", "set", "inet", "fw4", name))
    for row in data.get("nftables", []):
        item = row.get("set", {})
        if item.get("name") == name:
            result = {}
            for entry in item.get("elem", []):
                parsed = parse_member(entry, family)
                if parsed:
                    result[parsed[0]] = parsed[1]
            return result
    raise RuntimeError(f"{name} missing in nft output")


def log_ts(line, now):
    found = SYSLOG_TIME.match(line)
    if not found:
        return now
    try:
        t = dt.datetime.strptime(f"{dt.datetime.fromtimestamp(now).year} {found.group(1)}",
                                 "%Y %b %d %H:%M:%S")
        stamp = int(t.timestamp())
        if stamp > now + 86400:
            stamp = int(t.replace(year=t.year - 1).timestamp())
        return stamp
    except ValueError:
        return now


def parse_log(line, now, boot):
    match = LOG_MARKER.search(line)
    if not match:
        return None
    family = int(match.group(1))
    fields = dict(FIELD.findall(line))
    try:
        ip = ipaddress.ip_address(fields.get("SRC", ""))
        if ip.version != family:
            return None
    except ValueError:
        return None
    dst = fields.get("DST", "")
    try:
        dst = str(ipaddress.ip_address(dst)) if dst else ""
    except ValueError:
        dst = ""
    try:
        port = int(fields["DPT"])
        if not (1 <= port <= 65535):
            port = None
    except (KeyError, ValueError):
        port = None
    proto = fields.get("PROTO", "")[:12].upper()
    if not re.fullmatch(r"[A-Z0-9]{1,12}", proto):
        proto = ""
    digest = hashlib.sha256((boot + "\0" + line).encode()).hexdigest()
    return digest, log_ts(line, now), family, str(ip), dst, port, proto


def read_log():
    try:
        return cmd("logread").splitlines()
    except (OSError, subprocess.CalledProcessError):
        return []


def read_counters():
    result = {"black4": 0, "black6": 0, "geo4": 0, "geo6": 0}
    try:
        output = cmd("nft", "list", "chain", "inet", "fw4", "geo_filter")
    except (OSError, subprocess.CalledProcessError):
        return result
    for family in (4, 6):
        src = "ip saddr" if family == 4 else "ip6 saddr"
        expressions = [
            (f"{src} @geo_black{family}", f"black{family}"),
            (f"{src} != @geo_cn{family}", f"geo{family}"),
        ]
        for expression, key in expressions:
            for line in output.splitlines():
                if expression in line and "counter packets" in line and "drop" in line:
                    found = re.search(r"counter packets (\d+)", line)
                    if found:
                        result[key] = int(found.group(1))
    return result


def boot_id():
    try:
        return Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    except OSError:
        return "unknown-boot"


def snapshot(conn, now):
    sizes = {}
    errors = []
    for family in (4, 6):
        try:
            members = read_members(family)
            sizes[str(family)] = len(members)
            for ip, ttl in members.items():
                conn.execute("""INSERT INTO bans(ip,family,first_seen,last_seen,expires_at)
                    VALUES(?,?,?,?,?) ON CONFLICT(ip) DO UPDATE SET
                    last_seen=excluded.last_seen,expires_at=excluded.expires_at""",
                    (ip, family, now, now, now + ttl))
        except (OSError, subprocess.CalledProcessError, ValueError, RuntimeError) as exc:
            errors.append(f"IPv{family}: {exc}")
            sizes[str(family)] = None
    conn.execute("DELETE FROM bans WHERE expires_at <= ?", (now,))
    return sizes, errors


def collect():
    now = int(time.time())
    conn = db_open()
    with conn:
        sizes, errors = snapshot(conn, now)
        boot = boot_id()
        for line in read_log():
            row = parse_log(line, now, boot)
            if row:
                conn.execute("INSERT OR IGNORE INTO events VALUES (?,?,?,?,?,?,?)", row)
        # Retain 30 days of sampled events, not an unlimited log.
        conn.execute("DELETE FROM events WHERE ts < ?", (now - 30 * 86400,))
    status = build_status(conn, now, sizes, errors)
    conn.close()
    STATUS.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".status-", dir=str(STATUS.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(status, f, ensure_ascii=False, separators=(",", ":"))
        os.chmod(name, 0o600)
        os.replace(name, STATUS)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    print(f"GeoWAN collect: {status['active_bans']} active records, "
          f"{status['samples_24h']} sampled events, errors={len(errors)}")


def build_status(conn, now, sizes, errors):
    since = now - 86400
    total = conn.execute("SELECT COUNT(*) FROM events WHERE ts>=?", (since,)).fetchone()[0]
    active = conn.execute("SELECT COUNT(*) FROM bans WHERE expires_at>?", (now,)).fetchone()[0]
    top_ip = [{"ip": ip, "count": cnt} for ip, cnt in conn.execute(
        "SELECT src,COUNT(*) n FROM events WHERE ts>=? GROUP BY src ORDER BY n DESC LIMIT 12",
        (since,))]
    top_port = [{"port": port, "service": SERVICE_PORTS.get(port, "其他端口"),
                 "count": cnt} for port, cnt in conn.execute(
        "SELECT port,COUNT(*) n FROM events WHERE ts>=? AND port IS NOT NULL "
        "GROUP BY port ORDER BY n DESC LIMIT 12", (since,))]
    events = [{"time": ts, "src": src, "dst": dst, "port": port, "proto": proto}
              for ts, src, dst, port, proto in conn.execute(
        "SELECT ts,src,dst,port,proto FROM events ORDER BY ts DESC LIMIT 80")]
    banned = [{"ip": ip, "family": fam, "expires": expiry} for ip, fam, expiry in
              conn.execute("SELECT ip,family,expires_at FROM bans WHERE expires_at>? "
                           "ORDER BY last_seen DESC LIMIT 120", (now,))]
    bucket_start = now - now % 3600 - 23 * 3600
    buckets = dict(conn.execute(
        "SELECT (ts/3600)*3600, COUNT(*) FROM events WHERE ts >= ? GROUP BY (ts/3600)",
        (bucket_start,)))
    return {
        "version": "0.1.0", "updated": now, "status": "degraded" if errors else "ok",
        "errors": errors, "set_sizes": sizes, "counters": read_counters(),
        "active_bans": active, "samples_24h": total, "top_sources": top_ip,
        "top_ports": top_port, "events": events, "blacklist": banned,
        "hours": [{"time": ts, "count": buckets.get(ts, 0)}
                  for ts in range(bucket_start, bucket_start + 24 * 3600, 3600)],
        "disclaimer": "事件和排行来自内核限速日志样本；包计数仅代表本次防火墙加载后的命中量。"
    }


def restore():
    now = int(time.time())
    conn = db_open()
    restored = 0
    for family in (4, 6):
        try:
            current = read_members(family)
        except (OSError, subprocess.CalledProcessError, ValueError, RuntimeError) as exc:
            print(f"Skip IPv{family}: {exc}")
            continue
        rows = conn.execute(
            "SELECT ip,expires_at FROM bans WHERE family=? AND expires_at>?",
            (family, now)).fetchall()
        pending = []
        for ip, expiry in rows:
            if ip not in current:
                ttl = min(MAX_TTL, max(1, expiry - now))
                pending.append(f"{ip} timeout {ttl}s")
        for start in range(0, len(pending), 64):
            members = ", ".join(pending[start:start + 64])
            try:
                cmd("nft", "add", "element", "inet", "fw4", f"geo_black{family}",
                    "{ " + members + " }")
                restored += len(pending[start:start + 64])
            except (OSError, subprocess.CalledProcessError) as exc:
                print(f"Restore IPv{family} batch failed: {exc}")
    conn.close()
    print(f"GeoWAN restored {restored} expiring IP entries")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("collect", "restore"))
    args = parser.parse_args()
    if args.action == "collect":
        collect()
    else:
        restore()


if __name__ == "__main__":
    main()
