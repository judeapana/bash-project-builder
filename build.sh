#!/bin/bash
#activate nginx config
echo ">> Enter Application Name:";

# shellcheck disable=SC2162
read application_name;

echo ">> Enter Servername:";
# shellcheck disable=SC2162
read server_name;

echo "Path to static files:";
# shellcheck disable=SC2162
read  path_to_static;


#add worker

supervisor="
[program:${application_name}.worker]
;Worker
environment=PATH='/home/.virtualenv/${application_name}_env/bin'
command=flask rq worker
process_name=%(program_name)s-%(process_num)s
numprocs=1
directory=/home/${application_name}
stopsignal=TERM
autostart=true
autorestart=true


[program:${application_name}.scheduler]
;Scheduler
environment=PATH='/home/.virtualenv/${application_name}_env/bin'
command=flask rq scheduler
process_name=%(program_name)s-%(process_num)s
numprocs=1
directory=/home/${application_name}
stopsignal=TERM
autostart=true
autorestart=true

[group:evoting]
programs=${application_name}.scheduler,${application_name}.worker
priority=99
";

echo "$supervisor" > "/etc/supervisor/conf.d/${application_name}.conf"


nginx_conf="server {
    listen 80;
    server_name ${server_name};

    error_page 502 /502.html;
    location /502.html{
        root /var/www/html;
    }

    location / {
        include uwsgi_params;
        uwsgi_pass unix:///tmp/${application_name}.sock;
    }
    location /static/ {
        alias ${path_to_static};
    }
}"

#creating nginx conf

echo "$nginx_conf" > "/etc/nginx/sites-available/${application_name}_nginx.conf";

#systemlink
ln -s "/etc/nginx/sites-available/${application_name}_nginx.conf" "/etc/nginx/sites-enabled/${application_name}_nginx.conf";

# restart nginx
echo ">>Restarting nginx";
sudo service nginx reload;


uwsgi="[uwsgi]
chdir = /home/${application_name}/
module = wsgi:app
plugins = python38
processes = 6
threads = 4
virtualenv = /home/.virtualenv/${application_name}_env
logto = /var/log/uwsgi/${application_name}.log
master = true
socket = /tmp/${application_name}.sock
chmod-socket = 666
vacuum = true
die-on-term = true";


echo ">>Copying uwsgi";

echo "$uwsgi" > "/etc/uwsgi/vassals/uwsgi_${application_name}.ini";

#systemlink
sudo ln -s "/etc/uwsgi/apps-available/uwsgi_${application_name}.ini" "/etc/uwsgi/vassals/uwsgi_${application_name}.ini";

systemctl restart emperor.uwsgi.service
echo ">>Creating virtualenv";

#create virtualenv
virtualenv "/home/.virtualenv/${application_name}_env" "--python='/usr/bin/python3.8'";
# shellcheck disable=SC1090
source "../.virtualenv/${application_name}_env/bin/activate"
#installing packages
echo ">>>> Installing Packages";
pip install -r requirements.txt
echo ">> Certbot";
#get ssl certificate
sudo certbot "--nginx"