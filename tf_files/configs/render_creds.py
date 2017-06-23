import json
import re
import argparse
import time
from os.path import expanduser
import subprocess as sp
import jinja2
import os

# setup basic auth user for gdcapi to talk to indexd
INDEXD_USER_SETUP = (
    "python /indexd/bin/index_admin.py"
    " create --username gdcapi --password '{}'"
)

# setup database
USERAPI_DB_SETUP = (
    "userdatamodel-init --username '{}' --password '{}' --host '{}' --db '{}'"
)

# setup user and permissions
USERAPI_USER_SETUP = (
    'userapi-create create /var/www/user-api/user.yaml'
)

# setup oauth2 client for gdcapi
USERAPI_GDCAPI_SETUP = (
    'userapi-create client-create --client gdcapi --urls {} --username cdis'
)

# setup gdcapi database
#
GDCAPI_DB_SETUP = (
    "gdc_postgres_admin graph-create "
    " -U '{username}' -P '{password}' -H '{host}' -D '{database}'"
)
GDCAPI_TRANSACTION_LOGS = (
    "python /gdcapi/bin/setup_transactionlogs.py  "
    "--user {username}  --password '{password}' "
    "--host '{host}' --database '{database}'"
)

if 'http_proxy' in os.environ:
    del os.environ['http_proxy']

if 'https_proxy' in os.environ:
    del os.environ['https_proxy']


def get_creds(creds_file):
    with open(creds_file, 'r') as f:
        creds = json.load(f)
    return creds


def get_pod(kube_config, service):
    while (True):
        r = sp.Popen([
            '/usr/local/bin/kubectl',
            '--kubeconfig={}'.format(kube_config),
            'get',
            'pods'], stdout=sp.PIPE, stderr=sp.PIPE)
        lines = r.stdout.read()
        error = r.stderr.read()
        if error:
            print error
            return
        for l in lines.split('\n'):
            if service in l and 'Running' in l:
                break
        if not l:
            print "{} not found, waiting for the pod to be up".format(service)
            time.sleep(2)
        else:
            pod = l.split()[0]
            return pod


def get_base_command(kube_config, pod, service):
    command = [
        '/usr/local/bin/kubectl',
        '--kubeconfig={}'.format(kube_config),
        'exec', pod, '-c', service]
    return command


def setup_index_user(creds_file, kube_config):
    creds = get_creds(creds_file)
    data = creds['gdcapi']
    pod = get_pod(kube_config, 'indexd')
    if not pod:
        print 'no pod found'
        return
    command = get_base_command(kube_config, pod, 'indexd')
    create_user = ' '.join(command + [
        '--', INDEXD_USER_SETUP.format(data['indexd_password'])])
    print 'Creating indexd gdcapi user'
    print run_command(create_user)[0]


def setup_userapi_database(creds_file, kube_config):
    setup_index_user(creds_file, kube_config)
    creds = get_creds(creds_file)
    data = creds['userapi']
    pod = get_pod(kube_config, 'userapi')

    command = get_base_command(kube_config, pod, 'userapi')
    create_db = command + [
        '--',
        USERAPI_DB_SETUP
        .format(data['db_username'],
                data['db_password'],
                data['db_host'], data['db_database'])]
    print 'Setting up userapi database'
    print run_command(create_db)[0]

    create_users = ' '.join(
        command + [
            '--', USERAPI_USER_SETUP])
    print 'Creating users in userapi db'
    print run_command(create_users)[0]

    create_oauth = ' '.join(
        command + [
            '--', USERAPI_GDCAPI_SETUP
            .format(data['hostname']+'/api/v0/oauth2/authorize')])
    (stdout, stderr) = run_command(create_oauth)
    print 'Creating gdcapi oauth2 client'
    print stdout
    try:
        (client_id, client_secret) = eval(stdout)
    except:
        print "Fail to create gdcapi oauth client"
        print stderr
        return

    creds['gdcapi']['oauth2_client_id'] = client_id
    creds['gdcapi']['oauth2_client_secret'] = client_secret
    update_creds(creds_file, creds)


def run_command(command):
    if type(command) == list:
        command = ' '.join(command)
    r = sp.Popen([command], shell=True, stderr=sp.PIPE, stdout=sp.PIPE)
    (stdout, stderr) = r.communicate()
    if r.returncode != 0:
        print stderr
    return stdout, stderr


def setup_gdcapi_database(creds_file, kube_config):
    creds = get_creds(creds_file)
    data = creds['gdcapi']
    pod = get_pod(kube_config, 'gdcapi')
    command = get_base_command(kube_config, pod, 'gdcapi')
    create_db = ' '.join(command + ["--", GDCAPI_DB_SETUP.format(
        username=data['db_username'], password=data['db_password'],
        host=data['db_host'], database=data['db_database'])])
    print 'Setting up gdcapi database' 
    print run_command(create_db)[0]

    create_tl = ' '.join(command + ["--", GDCAPI_TRANSACTION_LOGS.format(
        username=data['db_username'], password=data['db_password'],
        host=data['db_host'], database=data['db_database'])])
    print 'Setting up gdcapi transaction log tables' 
    print run_command(create_tl)[0]


def render_creds(creds_file, result_dir):
    with open(creds_file, 'r') as f:
        creds = json.load(f)

    for service in ['userapi', 'gdcapi', 'indexd']:
            render_from_template(service, creds[service], result_dir)


def update_creds(creds_file, creds):
    with open(creds_file, "w") as f:
        json.dump(creds, f, indent=4)


def render_from_template(service, data, result_dir):
    home = expanduser("~")
    with open(
            "{}/cloud-automation/apis_configs/{}_settings.py"
            .format(home, service), "r") as f:
        content = f.read()
        template = jinja2.Template(content)
    with open(
            os.path.join(result_dir, '{}_settings.py'
                         .format(service)), 'w') as f:
        f.write(template.render(**data))


if __name__ == '__main__':
    cur_dir = os.path.dirname(os.path.realpath(__file__))
    project_dir = re.sub(r'_output$', '', cur_dir)

    creds_file = os.path.join(cur_dir, 'creds.json')
    kubeconfig = os.path.join(project_dir, 'kubeconfig')

    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='sp_name')

    secrets_parser = subparsers.add_parser(
        'secrets', help='render secrets for k8')

    db_parser = subparsers.add_parser(
        'userapi_db', help='setup userapi database')

    gdcapi_parser = subparsers.add_parser(
        'gdcapi_db', help='setup gdcapi database')

    args = parser.parse_args()
    if args.sp_name == 'secrets':
        result_dir = os.path.join(project_dir, 'apis_configs')

        if not os.path.exists(result_dir):
            os.mkdir(result_dir)

        render_creds(creds_file, result_dir)
    elif args.sp_name == 'userapi_db':
        setup_userapi_database(creds_file, kubeconfig)
    elif args.sp_name == 'gdcapi_db':
        setup_gdcapi_database(creds_file, kubeconfig)
