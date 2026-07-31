import datetime
import hashlib
import json
import urllib.request
import urllib.error
import base64
import gzip
import os
import sys
from Crypto.Cipher import AES

def decrypt_aes(ciphertext, key, iv):
    cipher = AES.new(key, AES.MODE_CBC, iv)
    try:
        decrypted = cipher.decrypt(ciphertext)
        pad_len = decrypted[-1]
        if pad_len < 1 or pad_len > 16:
            return decrypted
        if all(x == pad_len for x in decrypted[-pad_len:]):
            return decrypted[:-pad_len]
        return decrypted
    except Exception as e:
        return None

def decompress_data(decrypted_bytes):
    try:
        gzip_data = base64.b64decode(decrypted_bytes.strip())
        decompressed = gzip.decompress(gzip_data)
        return decompressed.decode('utf-8', errors='ignore')
    except Exception as e:
        return None

def get_signature():
    # Timezone Jakarta (UTC+7)
    utc_now = datetime.datetime.now(datetime.timezone.utc)
    jakarta_now = utc_now + datetime.timedelta(hours=7)
    date_str = jakarta_now.strftime('%Y-%m-%d')
    clean_hash_key = "C29C7ADE672C27513F9061278B536A3C00EC3663"
    combined = date_str + clean_hash_key
    sig = hashlib.sha256(combined.encode('utf-8')).hexdigest().upper()
    return date_str, sig

def fetch_and_decrypt(category, sig, token):
    # API endpoints for movies or series
    # Movies: https://cmt.mb13.cyou/bin/mtp1.json?a=movies&b=playlist&tekon=Tokek&c={sig}&d={token}
    # Series: https://cmt.mb13.cyou/bin/mtp.json?a=series&b=playlist&tekon=Tokek&c={sig}&d={token} (Wait, check SERVER_URL6 is mtp.json, SERVER_URL3 is mtp1.json)
    
    if category == "movies":
        url = f"https://cmt.mb13.cyou/bin/mtp1.json?a=movies&b=playlist&tekon=Tokek&c={sig}&d={token}"
    elif category == "series":
        url = f"https://cmt.mb13.cyou/bin/mtp.json?a=series&b=playlist&tekon=Tokek&c={sig}&d={token}"
    else:
        url = f"https://cmt.mb13.cyou/bin/mtp1.json?a={category}&b=playlist&tekon=Tokek&c={sig}&d={token}"
        
    print(f"Requesting [{category.upper()}]: {url}")
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
    
    req = urllib.request.Request(url, headers=headers)
    raw_data = None
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            raw_data = response.read()
    except urllib.error.HTTPError as e:
        print(f"Server returned error code {e.code} for {category}")
        raw_data = e.read()
    except Exception as e:
        print(f"Failed to fetch {category}: {e}")
        return None
        
    if not raw_data:
        return None
        
    try:
        enc_data = base64.b64decode(raw_data.strip())
        if len(enc_data) < 16:
            print("Data too short")
            return None
        iv = enc_data[:16]
        ciphertext = enc_data[16:]
        
        # Test BOTH keys for decryption
        keys = [
            (b"2d1Rh1oEInA1224t", "STERONG"),
            (b"Ov3rwr1t351t50k3", "Main Key")
        ]
        
        for key, key_name in keys:
            dec = decrypt_aes(ciphertext, key, iv)
            if dec:
                decompressed = decompress_data(dec)
                if decompressed:
                    try:
                        # Try to load as JSON to verify success
                        obj = json.loads(decompressed)
                        return {
                            'json': obj,
                            'key_used': key_name
                        }
                    except Exception:
                        # Fallback check if it's plaintext notice
                        if all(32 <= x < 127 or chr(x) in '\r\n\t' for x in decompressed[:100].encode('ascii', errors='ignore')):
                            return {
                                'notice': decompressed,
                                'key_used': key_name
                            }
        return None
    except Exception as e:
        print(f"Decoding/decryption failed for {category}: {e}")
        return None

def main():
    # User's registered active token
    # Wait, let's ask the user or search if there's any active token they can provide.
    # We will look for token value. In the first step prompt, Koko mentioned:
    # "ID Register: 83
    #  ID Perangkat (Device ID): d253521be1d612ae8845b52c7a1dec6a + dec6a (wait, actually the deviceid is d253521be1d612ae8845b52c7a1dec6a)
    #  Nama Perangkat: a0ee7789a2d48a23957c1b42f4145052"
    # To perform the handshake and fetch the token, we need a valid signature!
    # Let's perform handshake request using these details to dynamically fetch a fresh token first!
    
    date_str, sig = get_signature()
    print(f"Date: {date_str}")
    print(f"Sig: {sig}")
    
    # Handshake request parameters
    handshake_url = "https://cmt.mb13.cyou/mtv/Q.php"
    
    # Values from user registration
    device_id = "d253521be1d612ae8845b52c7a1dec6a"
    secure_token = ""  # Start fresh
    
    # Recreate getAuthParamsHandshake map
    # map.put("action", "handshake")
    # map.put("username", HelperUtils.getPermanentId())
    # map.put("secure_token", HelperUtils.getSecureToken())
    # map.put("sig", sig)
    # map.put("String", "https://mibitivi.blogspot.com") # MAIL / WEB JNI values
    post_data = {
        'action': 'handshake',
        'username': device_id,
        'secure_token': secure_token,
        'sig': sig,
        'String': 'https://mibitivi.blogspot.com'
    }
    
    print("\n--- PERFORMING HANDSHAKE ---")
    print(f"URL: {handshake_url}")
    print(f"Post data: {post_data}")
    
    req_data = urllib.parse.urlencode(post_data).encode('utf-8')
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Content-Type': 'application/x-www-form-urlencoded'
    }
    
    req = urllib.request.Request(handshake_url, data=req_data, headers=headers)
    token = ""
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            res_raw = response.read()
            print("Handshake Response Status: 200 OK")
            
            # Decrypt handshake response (it uses Main Key 'Ov3rwr1t351t50k3' or '2d1Rh1oEInA1224t')
            enc_data = base64.b64decode(res_raw.strip())
            iv = enc_data[:16]
            ciphertext = enc_data[16:]
            
            keys = [b"2d1Rh1oEInA1224t", b"Ov3rwr1t351t50k3"]
            dec_text = None
            for key in keys:
                dec = decrypt_aes(ciphertext, key, iv)
                if dec:
                    dec_text = dec.decode('utf-8', errors='ignore')
                    # Handshake returns plain text or JSON containing the new token
                    if "success" in dec_text or "token" in dec_text or "id" in dec_text or len(dec_text) < 100:
                        print(f"Decrypted Handshake with key: {key.decode()}")
                        break
            
            if dec_text:
                print(f"Handshake Decrypted Response:\n{dec_text}")
                try:
                    res_obj = json.loads(dec_text)
                    token = res_obj.get("secure_token", res_obj.get("token", ""))
                except Exception:
                    # Parse token manually if it's plain text or custom format
                    token = dec_text.strip()
            else:
                print("Could not decrypt handshake response.")
    except Exception as e:
        print(f"Handshake failed: {e}")
        
    if not token:
        # Prompt for manual token input if handshake didn't resolve one
        print("\n[WARNING] Handshake did not return a valid secure token.")
        print("Please enter the secure_token from your active device's .snes file manually below.")
        print("Or if you don't have it, press Enter to attempt fetching anyway:")
        manual_token = input("> ").strip()
        if manual_token:
            token = manual_token
            
    print(f"\nUsing Secure Token: '{token}'")
    
    # Fetch Movies & Series
    categories = ["movies", "series"]
    for cat in categories:
        print(f"\n--- FETCHING {cat.upper()} PLAYLIST ---")
        res = fetch_and_decrypt(cat, sig, token)
        if res:
            key_used = res['key_used']
            print(f"Successful decryption using key: {key_used}")
            
            if 'json' in res:
                playlist_obj = res['json']
                channels = playlist_obj.get('channels', [])
                print(f"Found {len(channels)} entries.")
                
                # Check for active stream URL vs placeholder notice
                placeholders_count = 0
                active_streams = []
                
                for item in channels:
                    name = item.get('name', 'Untitled')
                    streams = item.get('stream_url', [])
                    
                    # stream_url is usually a list of maps for movies/series
                    if isinstance(streams, list):
                        for s_map in streams:
                            ep_url = s_map.get('episode', '')
                            judul = s_map.get('judul', 'Default')
                            
                            if "mibiupdate.mp4" in ep_url or "geocities.ws" in ep_url:
                                placeholders_count += 1
                            else:
                                active_streams.append({
                                    'title': name,
                                    'stream_name': judul,
                                    'url': ep_url,
                                    'poster': item.get('poster', ''),
                                    'sinopsis': item.get('sinopsis', '')
                                })
                    elif isinstance(streams, str):
                        if "mibiupdate.mp4" in streams or "geocities.ws" in streams:
                            placeholders_count += 1
                        else:
                            active_streams.append({
                                'title': name,
                                'stream_name': 'Movie',
                                'url': streams,
                                'poster': item.get('poster', ''),
                                'sinopsis': item.get('sinopsis', '')
                            })
                            
                print(f"Active links: {len(active_streams)} / placeholders: {placeholders_count}")
                
                # Export to local JSON file
                out_dir = r"D:\Projects\Self\stream-tv\assets"
                if not os.path.exists(out_dir):
                    os.makedirs(out_dir)
                    
                out_path = os.path.join(out_dir, f"mibi_{cat}.json")
                with open(out_path, 'w', encoding='utf-8') as out_f:
                    json.dump(active_streams, out_f, indent=4)
                print(f"Saved filtered active stream playlist to: {out_path}")
                
                # Print sample
                if active_streams:
                    print("Sample items:")
                    for entry in active_streams[:3]:
                        print(f" - {entry['title']} ({entry['stream_name']}): {entry['url']}")
            elif 'notice' in res:
                print(f"Notice received from server:\n{res['notice']}")
        else:
            print(f"Failed to fetch or decrypt {cat} playlist.")

if __name__ == '__main__':
    main()
