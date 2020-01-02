#!/usr/bin/env sh
# You should change the OSM_USERNAME, OSM_UID, and other variables in `variables` as necessary
#set -ex

function variables() {
	# This must be set to 0 when not testing a "new" setup
	DEBUG=0

	OSM_USERNAME="vorpalblade-kaart"
    OSM_UID=9019988
	DATABASE_DIR="${HOME}/workspace/test_db"
	POSTGRES_DB="devel_tasking_manager"
	POSTGRES_USER="devel_postgres_user"
	#TODO change the password
	POSTGRES_PASSWORD="hunter1-password-is-weak"
	POSTGRES_ENDPOINT="localhost"
	POSTGRES_PORT=5000
	source tasking-manager.env
}

function check_dependencies() {
	if [ ! -f "$(which brew)" ]; then
		echo "We need brew ( go to https://brew.sh/ to get it )"
	fi
	echo "We are now installing python (with pip), postgres, postgis, and geos from homebrew"
	brew install python postgres postgis geos || echo "We couldn't install all the dependencies. Issues may occur."
}

function database_setup() {
	export PGDATA="${DATABASE_DIR}"
	# IMPORTANT TODO REMOVE
	if [ -d "${PGDATA}" ] && [ ${DEBUG} -gt 0 ]; then
		rm -rf "${PGDATA}"
	fi

	if [ ! -d "${PGDATA}" ]; then
		mkdir -p "${PGDATA}"
		initdb "${PGDATA}"
		pg_ctl -D "${PGDATA}" -l logfile start
		createdb "${POSTGRES_DB}"
		createdb "$(whoami)"
		local commands=("CREATE USER \"${POSTGRES_USER}\" PASSWORD '${POSTGRES_PASSWORD}';"
				"CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${POSTGRES_USER}\";"
				"\\c \"${POSTGRES_DB}\";"
				"CREATE EXTENSION postgis;")
		for command in "${commands[@]}"; do
			psql --dbname="${POSTGRES_DB}" --command="${command}" || echo "${command} didn't work"
		done
		export TM_DB="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_ENDPOINT}/${POSTGRES_DB}"
	else
		pg_ctl -D "${PGDATA}" -l logfile start
		export TM_DB="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_ENDPOINT}/${POSTGRES_DB}"
	fi
	setup_python
	python3 manage.py db upgrade
	setup_users
}

function setup_users() {
	local commands=("INSERT INTO users(id, username, role, mapping_level, tasks_mapped, tasks_validated, tasks_invalidated) VALUES (2078753, 'vorpalblade', 1, 3, 0, 0, 0), (7772276, 'pizzagal', 1, 3, 0, 0, 0), (${OSM_UID}, '${OSM_USERNAME}', 0, 3, 0, 0, 0);"
			"UPDATE users set role = 1 where username = '${OSM_USERNAME}'")
		for command in "${commands[@]}"; do
			psql --dbname="${POSTGRES_DB}" --command="${command}" || echo "${command} didn't work"
		done

}

function database_shutdown() {
	pg_ctl -D "${PGDATA}" stop -s -m fast
}

function setup_python() {
	local VENV="./venv"
	if [ -d "${VENV}" ] && [ ${DEBUG} -gt 1 ]; then
		rm -rf "${VENV}"
	fi
	if [ ! -d "${VENV}" ]; then
		python3 -m venv "${VENV}"
		. "${VENV}/bin/activate"
		pip install -r requirements.txt
	else
		. "${VENV}/bin/activate"
	fi
}

function make_client() {
    VERSION="$(git describe --tags)"
    VERSION=${VERSION#v}
    if [ $(echo ${VERSION} | wc -c) -lt 10 ] && [ ${VERSION:0:1} -lt 4 ]; then
		cd client
		npm install
		gulp build
		gulp run &
		cd ..
    else
		cd frontend
		npm install
		npm run build # either this or npm start
        npm start & # either this or npm run build
		cd ..
	fi
}

function start_server() {
	setup_python
	python3 manage.py runserver -d -r
}

function main() {
	trap "database_shutdown; jobs -p | xargs kill -QUIT" EXIT SIGTERM
	variables
	check_dependencies
	database_setup
	make_client &
	start_server
}
main $@
