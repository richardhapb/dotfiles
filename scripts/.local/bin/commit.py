#!/usr/bin/env python

import os
import json
import base64
import subprocess
import urllib.request

diff = subprocess.check_output(['git', 'diff', '--staged']).decode('utf-8')
diff_base64 = base64.b64encode(diff.encode()).decode('utf-8')

url = 'https://api.anthropic.com/v1/messages'
headers = {
    'x-api-key': os.environ['ANTHROPIC_API_KEY'],
    'anthropic-version': '2023-06-01',
    'content-type': 'application/json'
}

data = {
    'model': 'claude-opus-4-20250514',
    'max_tokens': 1024,
    'messages': [{
        'role': 'user',
        'content': f'The following git diff is base64 encoded. First decode it, then write a commit message for the change with commitizen convention. Keep the title under 50 characters and wrap message at 72 characters, send only the commit, whitout your comments. Format as a gitcommit code block.\n\n{diff_base64}'
    }]
}

req = urllib.request.Request(
    url,
    data=json.dumps(data).encode('utf-8'),
    headers=headers,
    method='POST'
)

with urllib.request.urlopen(req) as response:
    result = json.loads(response.read().decode('utf-8'))
    commit_msg = result['content'][0]['text'].replace('```gitcommit', '').replace('```', '')
    print(commit_msg)