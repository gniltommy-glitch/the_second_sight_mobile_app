#!/usr/bin/env python3
"""Create a local QR for a helper; secrets come from env or hidden input."""
import argparse
import getpass
import json
import os
from pathlib import Path
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--endpoint', required=True)
    parser.add_argument('--output', required=True, help='PNG path; contains credentials')
    parser.add_argument('--allow-insecure', action='store_true')
    args = parser.parse_args()
    uri = urlsplit(args.endpoint)
    if (uri.scheme not in {'http', 'https'} or not uri.hostname or uri.username or
            uri.password or uri.query or uri.fragment or uri.path not in {'', '/'} or
            (uri.scheme == 'http' and not args.allow_insecure)):
        parser.error('Use HTTPS or explicitly allow HTTP LAN testing.')
    token = os.environ.get('SECONDSIGHT_TOKEN') or getpass.getpass('Pi token: ')
    key = os.environ.get('GRAPHOPPER_API_KEY') or getpass.getpass('GraphHopper key (blank to keep current): ')
    if not token.strip():
        parser.error('Pi token is required.')
    payload = {'type': 'secondsight_pairing', 'version': 1, 'endpoint': args.endpoint,
               'token': token.strip(), 'allow_insecure': args.allow_insecure}
    if key.strip():
        payload['routing_key'] = key.strip()
    try:
        import qrcode
    except ImportError:
        parser.error('Install qrcode[pil] in a virtual environment first.')
    target = Path(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    # Credentials are not printed or passed as command-line arguments.
    with target.open('wb') as handle:
        os.chmod(target, 0o600)
        qrcode.make(json.dumps(payload, ensure_ascii=False)).save(handle)
    print('Saved local pairing QR. Scan it in Settings; treat this image as a secret.')

if __name__ == '__main__':
    main()
