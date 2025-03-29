#!/bin/bash

# install docker on host machine, set up
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh
sudo usermod -a -G docker ubuntu
id ubuntu
newgrp docker

# CHANGE TO UBUNTU DIRECTORY, DOWNLOAD DOCKER-COMPOSE FILE AND DUMP
cd /home/is214
# wget -O docker-compose.yml https://bchewy.s3.ap-southeast-1.amazonaws.com/docker-compose.yml # Dev
# wget -O docker-compose.yml https://bchewy.s3.ap-southeast-1.amazonaws.com/docker-compose-staging.yml # Staging
wget -O docker-compose.yml https://bchewy.s3.ap-southeast-1.amazonaws.com/docker-compose-prod.yml # Prod
# TODO: Applicaiton Team to replace dump.dump with the latest dump on March 19.
wget -O dump.dump https://bchewy.s3.ap-southeast-1.amazonaws.com/Odoo+CRM+dump+Mar+14+2024.dump
docker compose up --build -d

# Only for the first machine on the database. , Seed the database with the latest dump.
sudo apt install postgresql-client-common -y
sudo apt-get install postgresql-client -y


# export PGHOST=odoo-pogstgres-staging.postgres.database.azure.com
# export PGHOST=odoo-pogstgres-prod.postgres.database.azure.com
export PGHOST=odoo-pogstgres-prod.postgres.database.azure.com
export PGUSER=is214
export PGPORT=5432
export PGDATABASE=postgres
export PGPASSWORD="brian134!" 

# Check if database odoo_actual already exists
if psql -U is214 -lqt | cut -d \| -f 1 | grep -qw odoo_actual; then
    echo "Database odoo_actual already exists. Skipping creation."
else
    # Create database odoo_actual
    psql -U is214 -c 'CREATE DATABASE odoo_actual;'
    psql -U is214 -d odoo_actual -c "CREATE ROLE odoo16 WITH LOGIN;"
    pg_restore -U is214 -d odoo_actual dump.dump
fi

# psql -U is214 -c 'CREATE DATABASE odoo_actual;'
# psql -U is214 -d odoo_actual -c "CREATE ROLE odoo16 WITH LOGIN;"
# pg_restore -U is214 -d odoo_actual dump.dump # in CLI
# Rest till docker-compose is up; 5 mins - needs time to deploy
# sleep 120
# Previous docker ones
# docker exec is214-db-1 psql -U is214 -c 'CREATE DATABASE odoo_actual;'
# docker exec is214-db-1 psql -U odoo -c "CREATE ROLE odoo16 WITH LOGIN;"
# cat dump.dump | docker exec -i is214-db-1 pg_restore -U odoo -d odoo_actual