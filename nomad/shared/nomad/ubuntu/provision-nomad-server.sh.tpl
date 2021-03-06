#!/bin/bash

set -ex

# Wait for cloud-init to finish.
echo "Waiting 180 seconds for cloud-init to complete."
timeout 180 /bin/bash -c \
  'until stat /var/lib/cloud/instance/boot-finished 2>/dev/null; do echo "Waiting ..."; sleep 2; done'

NOMAD_VERSION=0.5.6

INSTANCE_ID=`curl ${instance_id_url}`
INSTANCE_PRIVATE_IP=$(ifconfig eth0 | grep "inet addr" | awk '{ print substr($2,6) }')

sudo apt-get -qq -y update

#######################################
# NOMAD INSTALL
#######################################

# install dependencies
echo "Installing dependencies..."
sudo apt-get install -qq -y wget unzip

# install nomad
echo "Fetching nomad..."
cd /tmp/

wget -q https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip -O nomad.zip

echo "Installing nomad..."
unzip nomad.zip
rm nomad.zip
sudo chmod +x nomad
sudo mv nomad /usr/bin/nomad
sudo mkdir -pm 0600 /etc/nomad.d

# setup nomad directories
sudo mkdir -pm 0600 /opt/nomad
sudo mkdir -p /opt/nomad/data

echo "Nomad installation complete."

#######################################
# NOMAD CONFIGURATION
#######################################

sudo tee /etc/nomad.d/nomad.hcl > /dev/null <<EOF
name       = "$$INSTANCE_ID"
data_dir   = "/opt/nomad/data"
datacenter = "${region}"

bind_addr = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = ${nomad_server_nodes}
}

addresses {
  rpc  = "$$INSTANCE_PRIVATE_IP"
  serf = "$$INSTANCE_PRIVATE_IP"
}

advertise {
  http = "$$INSTANCE_PRIVATE_IP:4646"
}

consul {
}

EOF

sudo tee /etc/init/nomad.conf > /dev/null <<EOF
description "Nomad"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

console log

script
  if [ -f "/etc/service/nomad" ]; then
    . /etc/service/nomad
  fi

  exec /usr/bin/nomad agent \
    -config="/etc/nomad.d" \
    $${NOMAD_FLAGS} \
    >>/var/log/nomad.log 2>&1
end script

EOF

#######################################
# START SERVICES
#######################################

sudo service nomad start
