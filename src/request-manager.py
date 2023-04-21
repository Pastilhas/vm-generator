#!/usr/local/bin/python

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import os, subprocess, json, time, smtplib
from datetime import datetime
from office365.runtime.auth.user_credential import UserCredential  # type: ignore
from office365.sharepoint.client_context import ClientContext  # type: ignore


os.chdir(os.path.dirname(os.path.abspath(__file__)))


CPU_PER_GPU = 7
RAM_STACK   = 32


(sp_user, sp_pass, sp_list_name, sp_url) = ('', '', '', '')
with open('config.json', 'r') as f:
    obj = json.load(f)
    (sp_user, sp_pass, sp_list_name, sp_url) = tuple(obj.values())


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
        return [i.properties for i in sp_items]
    except:
        message('Error reading sharepoint list')
        return []


def parse_items(items):
    changes = []
    now = datetime.today().date()
    active = [i for i in items if i['Active']]

    for item in active:
        name = f'vm{item["Id"]}'
        todate = datetime.strptime(item['To'], '%Y-%m-%dT%H:%M:%SZ').date()
        fromdate = datetime.strptime(item['From'], '%Y-%m-%dT%H:%M:%SZ').date()

        exists = subprocess.run(f'virsh list | grep -o {name}', shell=True, capture_output=True).stdout.decode().strip()

        if not exists and fromdate < now and todate >= now:
            changes.append(([
                'bash',
                'vm-create.sh',
                name,
                str(item['GPUS'] * CPU_PER_GPU),
                str(item['RAM_x0028_32GB_x0029_'] * RAM_STACK),
                str(item['GPUS']),
                str(item['Storage_x0028_2TB_x0029_']),
            ], item['UserId'], name))

        elif exists and todate < now:
            changes.append(([
                'bash',
                'vm-destroy.sh',
                name,
            ], item['UserId'], ''))

    return changes


def send_email(subject, body, userid):
    ctx = ClientContext(sp_url).with_credentials(UserCredential(sp_user, sp_pass))
    user = ctx.web.site_users.filter(f'Id eq {userid}')
    ctx.load(user)
    ctx.execute_query()
    if not user: return
    user = user[0].properties
    
    mimemsg = MIMEMultipart()
    mimemsg["From"] = sp_user
    mimemsg["To"] = user["Email"]
    mimemsg["Subject"] = subject
    mimemsg.attach(MIMEText(body, 'plain'))
        
    connection = smtplib.SMTP(host='smtp.office365.com', port=587)
    connection.starttls()
    connection.login(sp_user, sp_pass)
    connection.send_message(mimemsg)
    connection.quit()


def create_email(name, userid):
    mac = subprocess.run(f'virsh dumpxml {name} | grep -o ..:..:..:..:..:..', shell=True, capture_output=True).stdout.decode().strip()
    ip = subprocess.run(f'dhcp-lease-list | grep -Po \"(?<={mac}  ).*?(?= )\"', shell=True, capture_output=True).stdout.decode().strip()
    if not mac or not ip: raise Exception('Failed to find machine mac and ip')

    send_email('Request accepted', f'''
Your request for a machine has been accepted.
Access it using an SSH client and the following details:

IP: {ip}
Login: vm
Password: vm

For example, run this command in your preferred terminal:
ssh vm@{ip}
''', userid)
    
def destroy_email(userid):
    send_email('Access revoked', f'''
Your reservation for a machine has reached its end.
Access to it has been revoked.
''', userid)


try:
    while True:
        time.sleep(5)
        items = query_sp()
        if not items: continue
        changes = parse_items(items)
        if not changes: continue

        for (command, userid, name) in changes:
            res = subprocess.run(command, capture_output=True)
            out, err = res.stdout.decode(), res.stderr.decode()
            for line in out.splitlines(): message(line)
            for line in err.splitlines(): message('ERR ' + line)

            if name: create_email(name, userid)
            else: destroy_email(userid)

        on = subprocess.run('virsh list | grep -Poh [0-9]+', shell=True, capture_output=True).stdout.decode().strip()
        of = subprocess.run('virsh list | grep -Poh -- \"- \"', shell=True, capture_output=True).stdout.decode().strip()
        message(f'Currently   active {len(on.splitlines())}')
        message(f'Currently inactive {len(of.splitlines())}')

except Exception as ex:
    message(ex)
    message('Exiting')
    exit(1)
