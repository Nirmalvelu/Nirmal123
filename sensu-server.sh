#!/bin/bash

#Adding the sensu-server repository

wget -q http://sensu.global.ssl.fastly.net/apt/pubkey.gpg -O- | sudo apt-key add -

#Creating an APT configuration file at /etc/apt/sources.list.d/sensu.list

echo "deb http://sensu.global.ssl.fastly.net/apt sensu main" | tee /etc/apt/sources.list.d/sensu.list

apt-get update && apt-get install sensu

#Client configuration
publicip='curl icanhazip.com'

cat > /etc/sensu/conf.d/client.json <<EOF

{
          "client": {
            "name": "sensu-server",
            "address": "$publicip",
            "environment": "sensu",
            "subscriptions": [ "basic"],
            "keepalive":
            {
           "handler": "mailer",
            "thresholds": {
            "warning": 250,
            "critical": 300
          }
            },
         "socket": {
          "bind": "127.0.0.1",
          "port": 3030
            }
          }
}

EOF

#To insert a Transport.json file

cat > /etc/sensu/conf.d/transport.json <<EOF

{
"transport":
{
"name": "rabbitmq",
"reconnect_on_error": true
}
}

EOF

#To insert a api.json file

cat > /etc/sensu/conf.d/api.json <<EOF

{
         "api":
           {
           "host": "localhost",
           "bind": "0.0.0.0",
           "port": 4567
          }
}

EOF

#Installing a redis server

apt-get -y install redis-server

cat > /etc/sensu/conf.d/redis.json <<EOF

{
"redis":
{
 "host": "127.0.0.1",
 "port": 6379
}
}

EOF

#Erlang Installation

wget http://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb

dpkg -i erlang-solutions_1.0_all.deb

apt-get -y update

apt-get -y install erlang-nox

#Rabbitmq Installation

wget http://www.rabbitmq.com/releases/rabbitmq-server/v3.6.0/rabbitmq-server_3.6.0-1_all.deb

dpkg -i rabbitmq-server_3.6.0-1_all.deb

cat > /etc/sensu/conf.d/rabbitmq.json <<EOF

{
      "rabbitmq":
      {
        "host": "127.0.0.1",
        "port": 5672,
        "vhost": "/sensu",
        "user": "sensu",
        "password": "secret"
      }
}

EOF

#Starting all the required services

service sensu-server start && service sensu-client start && service rabbitmq-server start && service redis-server start && service sensu-api start

#Creating a dedicated RabbitMQ vhost and user for Sensu

rabbitmqctl add_vhost /sensu
sudo rabbitmqctl add_user sensu secret sudo rabbitmqctl
set_permissions -p /sensu sensu ".*" ".*" ".*"

#Uchiwa Installation

apt-get install uchiwa

cd /etc/sensu/uchiwa.json
mv uchiwa.json uchiwa.json.bkg

cat > /etc/sensu/uchiwa.json <<EOF

{
      "sensu": [
            {
          "name": "sensu",
          "host": "localhost",
          "port": 4567,
          "timeout": 10
            }
          ],
          "uchiwa": {
            "host": "0.0.0.0",
            "port": 8080,
            "refresh": 10
          }
}

EOF

service uchiwa start

cd /opt/sensu/embedded/bin/

sensu-install -p cpu-checks
sensu-install -p disk-checks
sensu-install -p memory-checks
sensu-install -p nginx
sensu-install -p process-checks
sensu-install -p load-checks
sensu-install -p vmstats
sensu-install -p mailer

#Configuring the basic check

cat > /etc/sensu/conf.d/check_cpu_linux.json <<EOF

{
      "checks": {
         "check-cpu-linux": {
       "handlers": ["mailer"],
       "command": "/opt/sensu/embedded/bin/check-cpu.rb -w 80 -c 90 ",
       "interval": 60,
       "occurrences": 5,
          "subscribers": [ "basic" ]
       }
         }
}

EOF


cat > /etc/sensu/conf.d/check_memory_linux.json <<EOF

{
      "checks": {
        "check_memory_linux": {
      "handlers": ["mailer"],
         "command": "/opt/sensu/embedded/bin/check-memory-percent.rb -w 90 -c 95",
      "interval": 60,
      "occurrences": 5,
      "subscribers": [ "basic" ]
        }
      }
}

EOF

cat > /etc/sensu/conf.d/check_disk_usage_linux.json <<EOF

{
     "checks": {
        "check-disk-usage-linux": {
"handlers": ["mailer"],
      "command": "/opt/sensu/embedded/bin/check-disk-usage.rb -w 80 -c 90",
      "interval": 60,
      "occurrences": 5,
      "subscribers": [ "basic" ]
        }
      }
}

EOF

#To enable an alert

apt-get install postfix

cat > /etc/sensu/conf.d/handler_mail.json <<EOF

{
          "handlers": {
            "mailer": {
          "type": "pipe",
          "command": "/opt/sensu/embedded/bin/handler-mailer.rb"
            }
          }
}

EOF

cat > /etc/sensu/conf.d/mailer.json <<EOF

{
            "mailer": {
            "admin_gui": "http://$publicip:8080/",
            "mail_from": "alerts@powerupcloud.com",
            "mail_to": "alerts@powerupcloud.com",
            "smtp_address": "localhost",
            "smtp_port": "25",
            "smtp_domain": "localhost"
            }
}

EOF

service sensu-server restart
update-rc.d sensu-server defaults
update-rc.d sensu-client defaults
update-rc.d sensu-api defaults
update-rc.d uchiwa defaults

