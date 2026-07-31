import sys
import time
import hashlib
import hmac
import base64
import requests
import json
from urllib.parse import urlparse, parse_qs

SECRET_KEY_DEFAULT = "76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O"
BASE_URL = "https://api6.aoneroom.com"

def md5_hex(data: str) -> str:
    return hashlib.md5(data.encode('utf-8')).hexdigest().lower()

def generate_x_client_token(ts: int) -> str:
    ts_str = str(ts)
    reversed_ts = ts_str[::-1]
    hash_val = md5_hex(reversed_ts)
    return f"{ts_str},{hash_val}"

def build_canonical_string(method, accept, content_type, url, body, timestamp_ms):
    parsed = urlparse(url)
    path = parsed.path
    
    # Sort query params alphabetically, maintaining blank values to match Dart
    query_params = parse_qs(parsed.query, keep_blank_values=True)
    sorted_keys = sorted(query_params.keys())
    parts = []
    for key in sorted_keys:
        for val in query_params[key]:
            parts.append(f"{key}={val}")
    query = "&".join(parts)
    canonical_url = f"{path}?{query}" if query else path
    
    body_hash = ""
    body_length = ""
    if body is not None:
        body_bytes = body.encode('utf-8')
        truncated = body_bytes[:102400]
        body_hash = hashlib.md5(truncated).hexdigest().lower()
        body_length = str(len(body_bytes))
        
    canonical = f"{method.upper()}\n{accept or ''}\n{content_type or ''}\n{body_length}\n{timestamp_ms}\n{body_hash}\n{canonical_url}"
    return canonical

def generate_x_tr_signature(method, accept, content_type, url, body, timestamp_ms):
    canonical = build_canonical_string(method, accept, content_type, url, body, timestamp_ms)
    secret_bytes = base64.b64decode(SECRET_KEY_DEFAULT)
    h = hmac.new(secret_bytes, canonical.encode('utf-8'), hashlib.md5)
    sig_b64 = base64.b64encode(h.digest()).decode('utf-8')
    return f"{timestamp_ms}|2|{sig_b64}"

def build_headers(method, url, body=None, auth_token=None):
    ts = int(time.time() * 1000)
    client_token = generate_x_client_token(ts)
    
    accept = "application/json"
    content_type = "application/json; charset=utf-8" if method == "POST" else "application/json"
    
    signature = generate_x_tr_signature(
        method=method,
        accept=accept,
        content_type=content_type,
        url=url,
        body=body,
        timestamp_ms=ts
    )
    
    client_info = {
        "package_name": "com.community.oneroom",
        "version_name": "3.0.03.0529.03",
        "version_code": 50020045,
        "os": "android",
        "os_version": "11",
        "install_ch": "ps",
        "device_id": "59bf891583d7f950ad0090886b510528",
        "install_store": "ps",
        "gaid": "f1b203a4-84c1-4b10-a29d-ee1e847c2311",
        "brand": "Redmi",
        "model": "2201117TG",
        "system_language": "en",
        "net": "NETWORK_WIFI",
        "region": "MG",
        "country": "MG",
        "timezone": "Europe/Paris",
        "sp_code": "64601",
        "language": "en",
        "locale": "en_MG",
        "preferred_language": "en",
        "X-Play-Mode": "2"
    }

    headers = {
        "User-Agent": "com.community.oneroom/50020045 (Linux; U; Android 11; en_MG; Redmi 2201117TG; Build/RP1A.200720.011; Cronet/135.0.7012.3)",
        "Accept": accept,
        "Content-Type": content_type,
        "Accept-Language": "en-MG,en;q=0.9",
        "Accept-Country": "MG",
        "Accept-Timezone": "Europe/Paris",
        "X-Language": "en",
        "X-Locale": "en-MG",
        "X-Region": "MG",
        "X-Country": "MG",
        "x-language": "en",
        "x-locale": "en-MG",
        "Connection": "keep-alive",
        "X-Client-Token": client_token,
        "x-tr-signature": signature,
        "X-Client-Info": json.dumps(client_info, separators=(',', ':')),
        "X-Client-Status": "0",
    }
    
    if auth_token:
        headers["Authorization"] = f"Bearer {auth_token}"
        
    return headers

def get_auth_token():
    path = "/wefeed-mobile-bff/tab-operating?page=1&tabId=0&version="
    url = f"{BASE_URL}{path}"
    headers = build_headers("GET", url)
    
    try:
        res = requests.get(url, headers=headers)
        x_user = res.headers.get("x-user") or res.headers.get("X-User")
        if x_user:
            try:
                payload = json.loads(x_user)
                return payload.get("token")
            except Exception:
                pass
    except Exception:
        pass
    return None

def print_curl_command(method, url, headers, body=None):
    curl_parts = [f"curl -X {method.upper()} \"{url}\""]
    for k, v in headers.items():
        # Escape double quotes in header values
        v_esc = v.replace('"', '\\"')
        curl_parts.append(f"  -H \"{k}: {v_esc}\"")
    if body:
        body_esc = body.replace('"', '\\"')
        curl_parts.append(f"  -d \"{body_esc}\"")
        
    print("\n---------------- cURL Command ----------------")
    print(" \\\n".join(curl_parts))
    print("----------------------------------------------\n")

def main():
    if len(sys.argv) < 3:
        print("Usage:")
        print("  python get_movie_meta.py search \"<query>\"")
        print("  python get_movie_meta.py get <subject_id>")
        sys.exit(1)
        
    action = sys.argv[1].lower()
    target = sys.argv[2]
    
    print("Fetching auth token...")
    token = get_auth_token()
    if not token:
        print("Failed to absorb auth token. Exiting.")
        sys.exit(1)
    print("Auth Token obtained successfully.")
    
    if action == "search":
        path = "/wefeed-mobile-bff/subject-api/search"
        url = f"{BASE_URL}{path}"
        payload = {
            "keyword": target,
            "page": 1,
            "perPage": 10,
            "subjectType": 0
        }
        body_str = json.dumps(payload, separators=(',', ':'))
        headers = build_headers("POST", url, body=body_str, auth_token=token)
        
        print_curl_command("POST", url, headers, body_str)
        
        print("Sending request...")
        res = requests.post(url, headers=headers, data=body_str)
        print("Response Code:", res.status_code)
        print("Response JSON:")
        print(json.dumps(res.json(), indent=2))
        
    elif action == "get":
        path = f"/wefeed-mobile-bff/subject-api/get?subjectId={target}"
        url = f"{BASE_URL}{path}"
        headers = build_headers("GET", url, auth_token=token)
        
        print_curl_command("GET", url, headers)
        
        print("Sending request...")
        res = requests.get(url, headers=headers)
        print("Response Code:", res.status_code)
        print("Response JSON:")
        print(json.dumps(res.json(), indent=2))
    else:
        print("Unknown action:", action)

if __name__ == "__main__":
    main()
