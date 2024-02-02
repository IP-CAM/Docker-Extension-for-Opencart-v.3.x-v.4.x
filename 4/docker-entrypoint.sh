#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$1" == apache2* ]] || [ "$1" = 'php-fpm' ]; then
	uid="$(id -u)"
	gid="$(id -g)"
	if [ "$uid" = '0' ]; then
		case "$1" in
			apache2*)
				user="${APACHE_RUN_USER:-www-data}"
				group="${APACHE_RUN_GROUP:-www-data}"

				# strip off any '#' symbol ('#1000' is valid syntax for Apache)
				pound='#'
				user="${user#$pound}"
				group="${group#$pound}"
				;;
			*) # php-fpm
				user='www-data'
				group='www-data'
				;;
		esac
	else
		user="$uid"
		group="$gid"
	fi

  if [ ! -e '/var/www/html/index.php' ]; then
    echo "copy opencart"
    tar cf - --one-file-system -C /usr/src/opencart/upload . | tar xf -
    find /var/www/html \! -user www-data -exec chown www-data '{}' +
  fi

  echo "configuring opencart"

  # Rename the configuration files if they exist (config-dist.php -> config.php)
  test -f config-dist.php &&  mv config-dist.php config.php ;
  test -f admin/config-dist.php &&  mv admin/config-dist.php admin/config.php ;
  # Set permissions for the configuration files
  chmod 0640 config.php; \
  chmod 0640 admin/config.php;

  # Check databaes
  echo "Wait for it database"
  wait-for-it ${OPENCART_DB_HOSTNAME:-mysql}:${OPENCART_DB_PORT:-3306}

  if [ $? -eq 0 ]; then
    # Check if an "install" directory exists
    if [ -d "install" ];then
      if [ -n "$OPENCART_ENABLE_SSL" ]; then
        # 判断变量的值是否为真
        if [ "$OPENCART_ENABLE_SSL" == "true" ]; then
          OPENCART_DOMAIN=https://${OPENCART_DOMAIN:-localhost}/
        else
          OPENCART_DOMAIN=http://${OPENCART_DOMAIN:-localhost}/
        fi
      else
          echo "OPENCART_ENABLE_SSL variable is not set"
      fi
      echo "Installing..."
      # Execute the OpenCart installation script with provided parameters
      php install/cli_install.php install --username    ${OPENCART_ADMIN_USERNAME:-admin} \
                                          --email       ${OPENCART_ADMIN_EMAIL:-'admin@admin.com'} \
                                          --password    ${OPENCART_ADMIN_PASSWORD:-1qaz@WSX3edc} \
                                          --http_server ${OPENCART_DOMAIN} \
                                          --db_driver   ${OPENCART_DB_DRIVER:-mysqli} \
                                          --db_hostname ${OPENCART_DB_HOSTNAME:-mysql} \
                                          --db_username ${OPENCART_DB_USERNAME:-opencart} \
                                          --db_password ${OPENCART_DB_PASSWORD:-1qaz@WSX3edc} \
                                          --db_database ${OPENCART_DB_DATABASE:-opencart} \
                                          --db_port     ${OPENCART_DB_PORT:-3306} \
                                          --db_prefix   ${OPENCART_DB_PREFIX:-cr_} &&
      # Remove the "install" directory after installation is complete
      rm -rf install

      # Move the storage directory
      echo "Move the storage directory"
      mv system/storage/* /var/www/opencart-storage/
      sed -i "s/DIR_SYSTEM.*storage\/./'\/var\/www\/opencart-storage\/'/" config.php
      sed -i "s/DIR_SYSTEM.*storage\/./'\/var\/www\/opencart-storage\/'/" admin/config.php
    else
        echo "Database connection failed!"
    fi

  else
    echo "No install directoty detected"
  fi
fi
exec "$@"