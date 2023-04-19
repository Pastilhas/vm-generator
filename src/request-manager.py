#!/usr/local/bin/python

import os, subprocess, json, time
from datetime import datetime
from office365.runtime.auth.user_credential import UserCredential  # type: ignore
from office365.sharepoint.client_context import ClientContext  # type: ignore


os.chdir(os.path.dirname(os.path.abspath(__file__)))


def message(msg):
    timestamp = datetime.utcnow().isoformat(sep=' ', timespec='seconds')
    print(f'[{timestamp}] {msg}')


def query_sp():
    try:
        ctx = ClientContext(sp_url).with_credentials(UserCredential(sp_user, sp_pass))
        sp_list = ctx.web.lists.get_by_title(sp_list_name)
        sp_items = sp_list.get_items()
        ctx.load(sp_items)
        ctx.execute_query()
        message(f'Read {len(sp_items)} items from the sharepoint list')
        return [i.properties for i in sp_items]
    except:
        message('Error reading sharepoint list')
        return []


def parse_items(items):
    new, old = [], []

    for item in items:
        if not item['Active']:
            continue
        todate = datetime.strptime(item['To'], '%Y-%m-%dT%H:%M:%SZ').date()
        fromdate = datetime.strptime(item['From'], '%Y-%m-%dT%H:%M:%SZ').date()
        now = datetime.today().date()

        name = f'vm{item["Id"]}'
        res = subprocess.run(
            f'virsh list | grep -o {name}', shell=True, capture_output=True
        )
        exists = res.stdout.decode().strip()
        if not exists and fromdate < now and todate >= now:
            new.append(
                [
                    name,
                    str(item['GPUS'] * 4),
                    str(item['RAM_x0028_32GB_x0029_'] * 32),
                    str(item['GPUS']),
                    str(item['Storage_x0028_2TB_x0029_']),
                ]
            )
        elif exists and todate < now:
            old.append(name)

    return new, old


with open('config.json', 'r') as f:
    obj = json.load(f)
    (sp_user, sp_pass, sp_list_name, sp_url) = tuple(obj.values())


try:
    while True:
        time.sleep(5)
        items = query_sp()
        new, old = parse_items(items)

        for item in new:
            res = subprocess.run(
                'bash vm-create.sh ' + ' '.join(item), shell=True, capture_output=True
            )
            out, err = res.stdout.decode(), res.stderr.decode()
            for line in out.splitlines():
                message(line)
            for line in err.splitlines():
                message('ERR ' + line)

        for item in old:
            res = subprocess.run(
                'bash vm-destroy.sh ' + item, shell=True, capture_output=True
            )
            out, err = res.stdout.decode(), res.stderr.decode()
            for line in out.splitlines():
                message(line)
            for line in err.splitlines():
                message('ERR ' + line)

        if new or old:
            message(f'created {len(new)} and destroyed {len(old)}')

except Exception as ex:
    message(ex)
    message('Exiting')
    exit(1)
