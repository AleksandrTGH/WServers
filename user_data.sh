#!/bin/bash
apt update -y
apt install -y nginx
PublicIP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
echo "<html><body bgcolor=gray><center><h1>Nginx Webserver with $PublicIP</h1><h2>Deployed via Terraform</h2></center></body></html>" > /var/www/html/index.html
